import { test } from 'node:test';
import assert from 'node:assert/strict';
import { withdraw } from '../scripts/withdraw.mjs';
import { submit } from '../scripts/submit.mjs';
import { removalOf, isSubmission } from '../scripts/registry.mjs';
import { fakeGitHub } from './fake-github.mjs';

const REPO = 'ProteusApp/plugins';
const ANN = { login: 'ann', id: 1 };
const BOB = { login: 'bob', id: 2 };
const OPEN_PR = { number: 12, html_url: 'https://github.com/ProteusApp/plugins/pull/12' };

/** A listed hello.world by ann. */
const checkout = {
  existing: (id, kind) => (id === 'hello.world' && kind === 'plugin' ? { id, name: 'Hello World', author: ANN } : null),
};

/** A removal request for `id`, number 9, opened by `user`. */
function request(user = ANN, id = 'hello.world', title = `Removal request: ${id}`) {
  return {
    action: 'opened',
    sender: user,
    issue: { number: 9, state: 'open', title, body: 'Not needed any more.', labels: [], user },
  };
}

function world({ pr = null, tree = [{ path: 'plugins/hello.world/init.lua', type: 'blob' }] } = {}) {
  const removed = { plugins: { zeta: { login: 'zed', id: 9 } }, profiles: {} };
  return {
    'GET /git/blobs/removed1': { content: Buffer.from(JSON.stringify(removed)).toString('base64') },
    'POST /git/blobs': { sha: 'removed2' },
    'GET /issues/9/comments': [],
    'GET /pulls': pr ? [pr] : [],
    'GET /git/ref/heads/main': { object: { sha: 'main1' } },
    'GET /git/commits/main1': { tree: { sha: 'tmain' } },
    'GET /git/trees/tmain': {
      tree: [
        ...tree,
        { path: 'plugins/other/init.lua', type: 'blob' },
        { path: 'plugins/hello.world', type: 'tree' },
        { path: 'removed.json', type: 'blob', sha: 'removed1' },
      ],
    },
    'POST /git/trees': { sha: 'tgone' },
    'POST /git/commits': { sha: 'gone1' },
    'POST /pulls': OPEN_PR,
    'PATCH /pulls/12': OPEN_PR,
  };
}

test('a removal request is read from its title', () => {
  assert.deepEqual(removalOf({ title: 'Removal request: hello.world' }), { kind: 'plugin', id: 'hello.world' });
  assert.deepEqual(removalOf({ title: 'Profile removal request: writer' }), { kind: 'profile', id: 'writer' });
  assert.equal(removalOf({ title: 'Removal request: ../x' }), null);
  assert.equal(removalOf({ title: 'Plugin submission: hello.world 1.0.0' }), null);
  assert.equal(isSubmission({ title: 'Removal request: hello.world', labels: [] }), true);
});

test('the author’s removal request opens a pull request that deletes the folder', async () => {
  const gh = fakeGitHub(world());
  assert.equal(await withdraw({ api: gh.api, event: request(), repo: REPO, checkout }), 'opened');
  const tree = gh.find('POST', '/git/trees')[0].body;
  assert.equal(tree.base_tree, 'tmain');
  assert.deepEqual(tree.tree, [
    { path: 'plugins/hello.world/init.lua', mode: '100644', type: 'blob', sha: null },
    { path: 'removed.json', mode: '100644', type: 'blob', sha: 'removed2' },
  ]);
  // The id stays with ann, beside the ids kept already, in order.
  const kept = JSON.parse(gh.find('POST', '/git/blobs')[0].body.content);
  assert.deepEqual(Object.keys(kept.plugins), ['hello.world', 'zeta']);
  assert.deepEqual(kept.plugins['hello.world'], { login: 'ann', id: 1 });
  // On the branch a submission would use, so /approve merges it.
  assert.equal(gh.find('POST', '/git/refs')[0].body.ref, 'refs/heads/submission/9');
  const pr = gh.find('POST', '/pulls')[0].body;
  assert.equal(pr.title, 'Remove Hello World (hello.world)');
  assert.match(pr.body, /Closes #9\./);
  assert.ok(gh.did('POST', '/issues/9/labels'));
});

test('only the listed author can ask to take a plugin down', async () => {
  const gh = fakeGitHub(world());
  assert.equal(await withdraw({ api: gh.api, event: request(BOB), repo: REPO, checkout }), 'refused');
  assert.equal(gh.did('POST', '/git/trees'), false);
  assert.match(gh.find('POST', '/issues/9/comments')[0].body.body, /Only @ann/);
});

test('a removal request for something not listed is refused', async () => {
  const gh = fakeGitHub(world());
  const event = request(ANN, 'nothing.here');
  assert.equal(await withdraw({ api: gh.api, event, repo: REPO, checkout }), 'refused');
  assert.equal(gh.did('POST', '/pulls'), false);
});

test('submit leaves a removal request alone', async () => {
  const gh = fakeGitHub(world());
  assert.equal(await submit({ api: gh.api, event: request(), repo: REPO, checkout: { reserved: {}, existing: () => null } }), 'ignored');
  assert.equal(gh.calls.length, 0);
});

test('the author closing a submission closes its pull request and branch', async () => {
  const gh = fakeGitHub(world({ pr: OPEN_PR }));
  const event = {
    action: 'closed',
    sender: ANN,
    issue: { number: 9, state: 'closed', title: 'Plugin submission: hello.world 1.1.0', labels: [], user: ANN },
  };
  assert.equal(await withdraw({ api: gh.api, event, repo: REPO, checkout }), 'withdrawn');
  assert.deepEqual(gh.find('PATCH', '/pulls/12')[0].body, { state: 'closed' });
  assert.ok(gh.did('DELETE', '/git/refs/heads/submission/9'));
});

test('someone else closing a submission leaves its pull request', async () => {
  const gh = fakeGitHub(world({ pr: OPEN_PR }));
  const event = {
    action: 'closed',
    sender: BOB,
    issue: { number: 9, state: 'closed', title: 'Plugin submission: hello.world 1.1.0', labels: [], user: ANN },
  };
  assert.equal(await withdraw({ api: gh.api, event, repo: REPO, checkout }), 'ignored');
  assert.equal(gh.calls.length, 0);
});
