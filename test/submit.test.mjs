import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { crc32, deflateSync } from 'node:zlib';
import { submit } from '../scripts/submit.mjs';
import { fakeGitHub } from './fake-github.mjs';

const REPO = 'ProteusApp/plugins';
const SAMPLE = readFileSync(new URL('./fixtures/store-issue.md', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const checkout = { reserved: { ids: [], prefixes: [] }, existing: () => null };

/** The sample plugin's submission issue, number 7, as its author opened it. */
function opened() {
  return {
    issue: {
      number: 7,
      state: 'open',
      title: 'Plugin submission: hello.world 1.0.0',
      body: SAMPLE,
      labels: [],
      user: { login: 'ann', id: 1 },
    },
  };
}

/**
 * GitHub around the submission. `branch` is the head of submission/7 when it exists, and
 * `pr` its open pull request. `before` lists what the parent commit's tree holds, and
 * `result` is the tree the new files make.
 */
function world({ branch = null, pr = null, before = [], result = 'tnew', oldVersion = '0.9.0' } = {}) {
  let blobs = 0;
  return {
    'GET /issues/7/comments': [],
    'GET /pulls': pr ? [pr] : [],
    'GET /git/ref/heads/main': { object: { sha: 'main1' } },
    'GET /git/ref/heads/submission/7': branch ? { object: { sha: branch } } : null,
    'GET /git/commits/main1': { tree: { sha: 'tmain' } },
    ...(branch ? { [`GET /git/commits/${branch}`]: { tree: { sha: 'tbranch' } } } : {}),
    'GET /git/trees/tmain': { tree: before },
    'GET /git/trees/tbranch': { tree: before },
    'POST /git/blobs': () => ({ sha: `blob${++blobs}` }),
    'POST /git/trees': { sha: result },
    'POST /git/commits': { sha: 'new1' },
    'POST /pulls': { number: 12, html_url: 'https://github.com/ProteusApp/plugins/pull/12' },
    'PATCH /pulls/12': { number: 12, html_url: 'https://github.com/ProteusApp/plugins/pull/12' },
    'GET /git/blobs/oldmeta': { content: Buffer.from(JSON.stringify({ version: oldVersion })).toString('base64') },
    ...(branch
      ? {
          [`GET /compare/${branch}...new1`]: {
            files: [
              { filename: 'plugins/hello.world/init.lua', status: 'modified', additions: 1, deletions: 1, patch: '@@ -1 +1 @@\n-a\n+b' },
              { filename: 'plugins/hello.world/proteus.json', status: 'modified', additions: 1, deletions: 1, patch: 'x' },
            ],
          },
        }
      : {}),
  };
}

const OPEN_PR = { number: 12, html_url: 'https://github.com/ProteusApp/plugins/pull/12' };
const OLD_META = { path: 'plugins/hello.world/proteus.json', type: 'blob', sha: 'oldmeta' };

test('a first publish opens a PR from a branch off main', async () => {
  const gh = fakeGitHub(world());
  assert.equal(await submit({ api: gh.api, event: opened(), repo: REPO, checkout }), 'opened');
  assert.deepEqual(gh.find('POST', '/git/commits')[0].body.parents, ['main1']);
  assert.equal(gh.find('POST', '/git/refs')[0].body.ref, 'refs/heads/submission/7');
  assert.equal(gh.find('POST', '/pulls').length, 1);
  assert.equal(gh.did('GET', '/compare'), false);
  // Three files and proteus.json.
  assert.equal(gh.find('POST', '/git/blobs').length, 4);
});

test('publishing again in review adds a commit to the branch and comments the diff', async () => {
  const gh = fakeGitHub(world({ branch: 'b1', pr: OPEN_PR, before: [OLD_META] }));
  assert.equal(await submit({ api: gh.api, event: opened(), repo: REPO, checkout }), 'updated');
  assert.deepEqual(gh.find('POST', '/git/commits')[0].body.parents, ['b1']);
  assert.deepEqual(gh.find('PATCH', '/git/refs/heads/submission/7')[0].body, { sha: 'new1', force: false });
  assert.equal(gh.find('POST', '/pulls').length, 0);
  const changes = gh.find('POST', '/issues/7/comments').map((c) => c.body.body).find((b) => b.includes('### Changes'));
  assert.match(changes, /### Changes in 1\.0\.0/);
  assert.match(changes, /Since 0\.9\.0/);
  assert.match(changes, /<code>init\.lua<\/code>/);
  assert.doesNotMatch(changes, /proteus\.json/);
});

test('publishing the same files again adds nothing', async () => {
  const gh = fakeGitHub(world({ branch: 'b1', pr: OPEN_PR, result: 'tbranch' }));
  assert.equal(await submit({ api: gh.api, event: opened(), repo: REPO, checkout }), 'unchanged');
  assert.equal(gh.did('POST', '/git/commits'), false);
  assert.equal(gh.did('PATCH', '/git/refs'), false);
});

test('a branch whose PR was merged starts again from main with a new PR', async () => {
  const gh = fakeGitHub(world({ branch: 'b1', pr: null }));
  assert.equal(await submit({ api: gh.api, event: opened(), repo: REPO, checkout }), 'opened');
  assert.deepEqual(gh.find('POST', '/git/commits')[0].body.parents, ['main1']);
  assert.deepEqual(gh.find('PATCH', '/git/refs/heads/submission/7')[0].body, { sha: 'new1', force: true });
  assert.equal(gh.find('POST', '/pulls').length, 1);
});

test('a file left out of the new version is deleted', async () => {
  const old = { path: 'plugins/hello.world/old.lua', type: 'blob', sha: 'o1' };
  const gh = fakeGitHub(world({ before: [old] }));
  await submit({ api: gh.api, event: opened(), repo: REPO, checkout });
  const entries = gh.find('POST', '/git/trees')[0].body.tree;
  assert.ok(entries.some((e) => e.path === 'plugins/hello.world/old.lua' && e.sha === null));
  assert.ok(entries.some((e) => e.path === 'plugins/hello.world/init.lua' && e.sha));
});

test('a plugin that belongs to someone else is refused before anything is written', async () => {
  const theirs = { ...checkout, existing: () => ({ id: 'hello.world', version: '0.1.0', author: { login: 'bob', id: 2 } }) };
  const gh = fakeGitHub(world());
  assert.equal(await submit({ api: gh.api, event: opened(), repo: REPO, checkout: theirs }), 'refused');
  assert.equal(gh.did('POST', '/git'), false);
  assert.ok(gh.find('POST', '/issues/7/comments').some((c) => /belongs to @bob/.test(c.body.body)));
});

test('a taken-down id is refused to anyone but its owner', async () => {
  const gone = { ...checkout, removed: (id, kind) => (id === 'hello.world' && kind === 'plugin' ? { login: 'bob', id: 2 } : null) };
  const gh = fakeGitHub(world());
  assert.equal(await submit({ api: gh.api, event: opened(), repo: REPO, checkout: gone }), 'refused');
  assert.equal(gh.did('POST', '/git'), false);
  assert.ok(gh.find('POST', '/issues/7/comments').some((c) => /taken down, and its id stays with @bob/.test(c.body.body)));
  const mine = { ...checkout, removed: () => ({ login: 'ann', id: 1 }) };
  assert.equal(await submit({ api: gh.api, event: opened(), repo: REPO, checkout: mine }), 'opened');
});

test('a new version starts the check on its branch and says which commit to approve', async () => {
  const gh = fakeGitHub(world());
  await submit({ api: gh.api, event: opened(), repo: REPO, checkout });
  assert.deepEqual(gh.find('POST', '/actions/workflows/check.yml/dispatches')[0].body, { ref: 'submission/7' });
  assert.ok(gh.find('POST', '/issues/7/comments').some((c) => /`\/approve new1`/.test(c.body.body)));
});

test('an issue still missing a file waits', async () => {
  const event = opened();
  event.issue.body = SAMPLE.replace(/<details><summary><code>lib\/util\.lua[\s\S]*$/, '');
  const gh = fakeGitHub(world());
  assert.equal(await submit({ api: gh.api, event, repo: REPO, checkout }), 'waiting');
  assert.equal(gh.did('POST', '/git'), false);
});

test('comments by others and commands are left alone', async () => {
  const gh = fakeGitHub(world());
  const other = { ...opened(), comment: { body: 'nice', user: { id: 2 } } };
  assert.equal(await submit({ api: gh.api, event: other, repo: REPO, checkout }), 'ignored');
  const command = { ...opened(), comment: { body: '/approve', user: { id: 1 } } };
  assert.equal(await submit({ api: gh.api, event: command, repo: REPO, checkout }), 'ignored');
  assert.equal(gh.calls.length, 0);
});

test('a profile submission writes to profiles/<id>', async () => {
  const manifest = {
    format: 2,
    kind: 'profile',
    revision: 'r1',
    id: 'writer',
    name: 'Writer',
    description: 'Notes and a to-do list.',
    version: '1.0.0',
    plugins: ['app.notes'],
    files: ['profile.lua'],
  };
  const body = [
    '<!-- proteus-manifest -->',
    '```json',
    JSON.stringify(manifest),
    '```',
    '',
    '<!-- proteus-file path="profile.lua" part="1" of="1" rev="r1" -->',
    '```lua',
    "return { name = 'Writer', plugins = { 'app.notes' } }",
    '```',
  ].join('\n');
  const event = opened();
  event.issue.title = 'Profile submission: writer 1.0.0';
  event.issue.body = body;
  const asked = [];
  const look = { ...checkout, existing: (id, kind) => (asked.push([id, kind]), null) };
  const gh = fakeGitHub(world());
  assert.equal(await submit({ api: gh.api, event, repo: REPO, checkout: look }), 'opened');
  assert.deepEqual(asked, [['writer', 'profile']]);
  const paths = gh.find('POST', '/git/trees')[0].body.tree.map((e) => e.path).sort();
  assert.deepEqual(paths, ['profiles/writer/profile.lua', 'profiles/writer/proteus.json']);
  assert.match(gh.find('POST', '/pulls')[0].body.title, /^Add profile Writer \(writer\) 1\.0\.0$/);
});

/** A whole PNG of one see-through pixel. */
function png() {
  const chunk = (type, data) => {
    const head = Buffer.alloc(4);
    head.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([head, body, crc]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(1, 0);
  header.writeUInt32BE(1, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(Buffer.alloc(5))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

test('a PNG goes to GitHub as base64 bytes, and text as UTF-8', async () => {
  const fence = '```';
  const event = opened();
  event.issue.body = [
    '<!-- proteus-manifest -->',
    `${fence}json`,
    JSON.stringify({
      format: 2,
      id: 'hello.world',
      name: 'Hello',
      description: 'Says hello.',
      version: '1.0.0',
      files: ['init.lua', 'sheet.png'],
      requires: { features: ['png'] },
    }),
    fence,
    '<!-- proteus-file path="init.lua" part="1" of="1" -->',
    `${fence}lua`,
    'return {}',
    fence,
    '<!-- proteus-file path="sheet.png" part="1" of="1" -->',
    `${fence}base64`,
    png().toString('base64'),
    fence,
  ].join('\n');
  const gh = fakeGitHub(world());
  assert.equal(await submit({ api: gh.api, event, repo: REPO, checkout }), 'opened');
  const blobs = gh.find('POST', '/git/blobs').map((c) => c.body);
  assert.deepEqual(blobs[0], { content: 'return {}', encoding: 'utf-8' });
  assert.deepEqual(blobs[1], { content: png().toString('base64'), encoding: 'base64' });
});
