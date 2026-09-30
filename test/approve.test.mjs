import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GitHubError } from '../scripts/github.mjs';
import { approve } from '../scripts/approve.mjs';
import { LABEL } from '../scripts/registry.mjs';
import { fakeGitHub } from './fake-github.mjs';

const REPO = 'ProteusApp/plugins';

/** An /approve comment on submission issue 7, written at noon. */
function event(login = 'ken', body = '/approve') {
  return {
    issue: { number: 7, state: 'open', title: 'Plugin submission: a.b 1.0.0', labels: [{ name: LABEL }], user: { login: 'ann', id: 1 } },
    comment: { id: 99, body, user: { login }, created_at: '2026-09-30T12:00:00Z' },
  };
}

/** GitHub as it looks with an open PR written at 11 o'clock, before the comment. */
function withPullRequest(extra = {}) {
  return {
    'GET /collaborators/ken/permission': { permission: 'admin' },
    'GET /pulls': [{ number: 12, html_url: 'https://github.com/ProteusApp/plugins/pull/12', head: { sha: 'abc' } }],
    'GET /commits/abc': { commit: { committer: { date: '2026-09-30T11:00:00Z' } } },
    'PUT /pulls/12/merge': { merged: true },
    'GET /issues/7/comments': [],
    ...extra,
  };
}

test('a maintainer\'s /approve merges the PR, rebuilds the index and closes the issue', async () => {
  const gh = fakeGitHub(withPullRequest());
  assert.equal(await approve({ api: gh.api, event: event(), repo: REPO }), 'merged');
  const merge = gh.calls.find((c) => c.method === 'PUT');
  assert.deepEqual(merge.body, { merge_method: 'rebase', sha: 'abc' });
  assert.ok(gh.did('POST', '/actions/workflows/index.yml/dispatches'));
  assert.ok(gh.calls.some((c) => c.method === 'PATCH' && c.path === '/issues/7' && c.body.state === 'closed'));
  assert.ok(gh.calls.some((c) => c.path === '/issues/comments/99/reactions' && c.body.content === 'rocket'));
});

test('someone without write access cannot approve', async () => {
  const gh = fakeGitHub(withPullRequest({ 'GET /collaborators/eve/permission': { permission: 'read' } }));
  assert.equal(await approve({ api: gh.api, event: event('eve'), repo: REPO }), 'refused');
  assert.ok(!gh.did('PUT', '/pulls'));
});

test('an approval waits for the PR to exist', async () => {
  const gh = fakeGitHub(withPullRequest({ 'GET /pulls': [] }));
  assert.equal(await approve({ api: gh.api, event: event(), repo: REPO }), 'waiting');
  assert.ok(!gh.did('PUT', '/pulls'));
});

test('a PR that changed after the comment is not merged', async () => {
  const gh = fakeGitHub(withPullRequest({ 'GET /commits/abc': { commit: { committer: { date: '2026-09-30T12:05:00Z' } } } }));
  assert.equal(await approve({ api: gh.api, event: event(), repo: REPO }), 'changed');
  assert.ok(!gh.did('PUT', '/pulls'));
});

test('a repository that turns rebasing off gets a merge commit', async () => {
  const methods = [];
  const gh = fakeGitHub(
    withPullRequest({
      'PUT /pulls/12/merge': (body) => {
        methods.push(body.merge_method);
        if (body.merge_method === 'rebase') throw new GitHubError(405, 'Rebase merges are not allowed on this repository.');
        return { merged: true };
      },
    }),
  );
  assert.equal(await approve({ api: gh.api, event: event(), repo: REPO }), 'merged');
  assert.deepEqual(methods, ['rebase', 'merge']);
});

test('a merge GitHub refuses is reported on the issue', async () => {
  const gh = fakeGitHub(
    withPullRequest({
      'PUT /pulls/12/merge': () => {
        throw new GitHubError(405, 'Pull Request is not mergeable');
      },
    }),
  );
  assert.equal(await approve({ api: gh.api, event: event(), repo: REPO }), 'failed');
  assert.ok(gh.calls.some((c) => c.path === '/issues/7/comments' && /not mergeable/.test(c.body?.body ?? '')));
});

test('an ordinary comment or a closed issue is ignored', async () => {
  const gh = fakeGitHub(withPullRequest());
  assert.equal(await approve({ api: gh.api, event: event('ken', 'looks good'), repo: REPO }), 'ignored');
  const closed = event();
  closed.issue.state = 'closed';
  assert.equal(await approve({ api: gh.api, event: closed, repo: REPO }), 'ignored');
  assert.equal(gh.calls.length, 0);
});
