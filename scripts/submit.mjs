// Turns a submission issue into a pull request. The submission workflow runs it whenever a
// submission issue opens or changes, or its author comments on it.
//
// It never runs the submitted code. It reads the issue's text, checks the plugin against the
// registry's rules, writes the files to a branch named submission/<issue>, and opens or
// updates a pull request from that branch. It explains what it did, or what is wrong, in one
// comment on the issue that it keeps up to date.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import {
  BOT_MARKER,
  LABEL,
  collectParts,
  decodePayload,
  isSubmission,
  manifestFor,
  pullRequestBody,
  validate,
} from './registry.mjs';

const token = process.env.GITHUB_TOKEN;
const repoName = process.env.GITHUB_REPOSITORY;
const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
const issue = event.issue;
const base = `https://api.github.com/repos/${repoName}`;

async function api(method, path, body) {
  const res = await fetch(path.startsWith('http') ? path : base + path, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'proteus-registry',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 404) return null;
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

async function allComments() {
  const out = [];
  for (let page = 1; page < 20; page++) {
    const batch = await api('GET', `/issues/${issue.number}/comments?per_page=100&page=${page}`);
    out.push(...(batch ?? []));
    if (!batch || batch.length < 100) break;
  }
  return out;
}

/** Writes the one bot comment on the issue, or updates it when there is one already. */
async function say(comments, lines) {
  const body = [BOT_MARKER, ...lines].join('\n');
  const mine = comments.find((c) => c.user?.type === 'Bot' && (c.body ?? '').startsWith(BOT_MARKER));
  if (mine) await api('PATCH', `/issues/comments/${mine.id}`, { body });
  else await api('POST', `/issues/${issue.number}/comments`, { body });
}

/** Every file under a folder of the checkout, as paths from that folder. */
function filesUnder(dir, prefix = '') {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const rel = prefix ? `${prefix}/${name}` : name;
    if (statSync(full).isDirectory()) out.push(...filesUnder(full, rel));
    else out.push(rel);
  }
  return out;
}

async function main() {
  if (!issue || issue.pull_request || issue.state !== 'open' || !isSubmission(issue)) {
    console.log('Not an open submission issue.');
    return;
  }
  // A comment counts only from the person who opened the issue.
  if (event.comment && event.comment.user?.id !== issue.user.id) {
    console.log('A comment by someone else.');
    return;
  }
  await api('POST', `/issues/${issue.number}/labels`, { labels: [LABEL] });

  const comments = await allComments();
  const texts = [issue.body ?? '', ...comments.filter((c) => c.user?.id === issue.user.id).map((c) => c.body ?? '')];
  const parts = collectParts(texts);
  if (!parts.complete) {
    console.log(`Waiting for the rest of the submission: ${parts.have} of ${parts.total || '?'} parts.`);
    return;
  }

  let sub;
  try {
    sub = decodePayload(parts.data);
  } catch (err) {
    await say(comments, [`This submission could not be read. ${err.message}`]);
    process.exitCode = 1;
    return;
  }

  const reserved = JSON.parse(readFileSync('reserved.json', 'utf8'));
  const id = typeof sub.id === 'string' ? sub.id : '';
  const existingPath = join('plugins', id, 'proteus.json');
  const existing = id && existsSync(existingPath) ? JSON.parse(readFileSync(existingPath, 'utf8')) : null;
  const problems = validate(sub, { existing, author: issue.user, reserved });
  if (problems.length > 0) {
    await say(comments, [
      'This submission cannot become a pull request yet:',
      '',
      ...problems.map((p) => `- ${p}`),
      '',
      'Fix the plugin in Proteus and publish it again. A new submission replaces this one.',
    ]);
    process.exitCode = 1;
    return;
  }

  const manifest = manifestFor(sub, issue.user, issue.number);
  const folder = `plugins/${manifest.id}`;
  const main = await api('GET', '/git/ref/heads/main');
  const head = await api('GET', `/git/commits/${main.object.sha}`);

  // The plugin's folder ends up holding exactly the submitted files and proteus.json.
  const entries = [];
  const files = { ...sub.files, 'proteus.json': JSON.stringify(manifest, null, 2) + '\n' };
  for (const [name, content] of Object.entries(files)) {
    const blob = await api('POST', '/git/blobs', { content, encoding: 'utf-8' });
    entries.push({ path: `${folder}/${name}`, mode: '100644', type: 'blob', sha: blob.sha });
  }
  for (const old of filesUnder(folder)) {
    if (!(old in files)) entries.push({ path: `${folder}/${old}`, mode: '100644', type: 'blob', sha: null });
  }
  const tree = await api('POST', '/git/trees', { base_tree: head.tree.sha, tree: entries });
  const updating = existing !== null;
  const title = `${updating ? 'Update' : 'Add'} ${manifest.name} (${manifest.id}) ${manifest.version}`;
  const commit = await api('POST', '/git/commits', {
    message: `${title}\n\nFrom #${issue.number}.`,
    tree: tree.sha,
    parents: [main.object.sha],
    author: {
      name: issue.user.login,
      email: `${issue.user.id}+${issue.user.login}@users.noreply.github.com`,
      date: new Date().toISOString(),
    },
  });

  const branch = `submission/${issue.number}`;
  if (await api('GET', `/git/ref/heads/${branch}`)) {
    await api('PATCH', `/git/refs/heads/${branch}`, { sha: commit.sha, force: true });
  } else {
    await api('POST', '/git/refs', { ref: `refs/heads/${branch}`, sha: commit.sha });
  }

  const owner = repoName.split('/')[0];
  const body = pullRequestBody(manifest, sub, issue.number, updating);
  const open = await api('GET', `/pulls?head=${owner}:${encodeURIComponent(branch)}&state=open`);
  let pr = open && open[0];
  if (pr) pr = await api('PATCH', `/pulls/${pr.number}`, { title, body });
  else pr = await api('POST', '/pulls', { title, head: branch, base: 'main', body, maintainer_can_modify: true });
  await api('POST', `/issues/${pr.number}/labels`, { labels: [LABEL] });

  await say(comments, [
    `Thanks, @${issue.user.login}. This submission is now ${pr.html_url}.`,
    '',
    'A maintainer reviews the code there. Once it is merged, the plugin shows in the Proteus store.',
  ]);
  console.log(`Pull request ${pr.html_url}`);
}

main().catch(async (err) => {
  console.error(err);
  process.exitCode = 1;
});
