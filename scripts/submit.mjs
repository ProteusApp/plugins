// Turns a submission issue, of a plugin or a profile, into a pull request. The submission workflow runs it whenever a
// submission issue opens or changes, or its author comments on it.
//
// It never runs the submitted code. It reads the issue's text, checks the plugin against the
// registry's rules, and writes the files to a branch named submission/<issue>, with a pull
// request from that branch. It explains what it did, or what is wrong, in one comment on the
// issue that it keeps up to date.
//
// Publishing again while the pull request is in review edits the same issue. The new version
// then goes on top of the branch as a new commit, and a comment on the issue shows what
// changed. Once the pull request is merged or closed, the branch starts again from main, with
// a new pull request.
//
// GitHub starts no workflow for a branch or a pull request made with the workflow's own
// token, so it starts the check workflow on the branch itself. /approve merges only once
// that check has passed on the commit the maintainer names.

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { allComments, client, say } from './github.mjs';
import {
  LABEL,
  branchFor,
  changesComment,
  collectSubmission,
  commandOf,
  folderFor,
  isSubmission,
  kindOf,
  manifestFor,
  pullRequestBody,
  removalOf,
  validate,
} from './registry.mjs';

/**
 * Runs one issue event. `api` calls the GitHub API of `repo`. `checkout` reads the main
 * branch: `reserved` is reserved.json, `existing(id, kind)` is a listed plugin's or
 * profile's proteus.json, or null, `removed(id, kind)`, when there, the owner of an id that
 * was taken down, from removed.json, or null, and `listed()`, when there, the ids of the
 * listed plugins. Returns what happened, as a word the tests check: ignored, unreadable,
 * waiting, refused, unchanged, opened or updated.
 */
export async function submit({ api, event, repo, checkout }) {
  const issue = event.issue;
  if (!issue || issue.pull_request || issue.state !== 'open' || !isSubmission(issue)) return 'ignored';
  // A request to take something down holds no files. withdraw.mjs handles it.
  if (removalOf(issue)) return 'ignored';
  // A comment counts only from the person who opened the issue, and a command such as
  // /approve is handled by its own job.
  if (event.comment && event.comment.user?.id !== issue.user.id) return 'ignored';
  if (event.comment && commandOf(event.comment.body)) return 'ignored';
  await api('POST', `/issues/${issue.number}/labels`, { labels: [LABEL] });

  const comments = await allComments(api, issue.number);
  const texts = [issue.body ?? '', ...comments.filter((c) => c.user?.id === issue.user.id).map((c) => c.body ?? '')];
  const found = collectSubmission(texts);
  if (found.error) {
    await say(api, issue.number, comments, [`This submission could not be read. ${found.error}`]);
    return 'unreadable';
  }
  if (!found.complete) return 'waiting';
  const sub = found.sub;

  const kind = kindOf(sub);
  const existing = typeof sub.id === 'string' ? checkout.existing(sub.id, kind) : null;
  // A plugin it needs must ship with Proteus or be listed here already.
  const known = checkout.listed ? new Set([...(checkout.reserved.ids ?? []), ...checkout.listed()]) : null;
  const removed = typeof sub.id === 'string' && checkout.removed ? checkout.removed(sub.id, kind) : null;
  const problems = validate(sub, { existing, author: issue.user, reserved: checkout.reserved, known, removed });
  if (problems.length > 0) {
    await say(api, issue.number, comments, [
      'This submission cannot become a pull request yet:',
      '',
      ...problems.map((p) => `- ${p}`),
      '',
      `Fix the ${kind} in Proteus and publish it again. The new version replaces this one.`,
    ]);
    return 'refused';
  }

  const manifest = manifestFor(sub, issue.user, issue.number);
  const folder = folderFor(kind, manifest.id);
  const branch = branchFor(issue.number);
  const owner = repo.split('/')[0];
  const open = (await api('GET', `/pulls?head=${owner}:${encodeURIComponent(branch)}&state=open`)) ?? [];
  let pr = open[0] ?? null;
  const main = await api('GET', '/git/ref/heads/main');
  const current = await api('GET', `/git/ref/heads/${branch}`);

  // While the pull request is in review, the new version goes on top of its branch. A branch
  // with no open pull request, such as one already merged, starts again from main.
  const inReview = Boolean(current && pr);
  const parentSha = inReview ? current.object.sha : main.object.sha;
  const parent = await api('GET', `/git/commits/${parentSha}`);
  const listing = await api('GET', `/git/trees/${parent.tree.sha}?recursive=1`);
  const before = (listing?.tree ?? []).filter((e) => e.type === 'blob' && e.path.startsWith(folder + '/'));

  // The folder ends up holding exactly the submitted files and proteus.json.
  const files = { ...sub.files, 'proteus.json': JSON.stringify(manifest, null, 2) + '\n' };
  const entries = [];
  for (const [name, content] of Object.entries(files)) {
    const blob = await api('POST', '/git/blobs', { content, encoding: 'utf-8' });
    entries.push({ path: `${folder}/${name}`, mode: '100644', type: 'blob', sha: blob.sha });
  }
  for (const e of before) {
    if (!(e.path.slice(folder.length + 1) in files)) {
      entries.push({ path: e.path, mode: '100644', type: 'blob', sha: null });
    }
  }
  const tree = await api('POST', '/git/trees', { base_tree: parent.tree.sha, tree: entries });

  if (inReview && tree.sha === parent.tree.sha) {
    await say(api, issue.number, comments, [
      `Thanks, @${issue.user.login}. This submission is ${pr.html_url}.`,
      '',
      'The last publish changed nothing, so the pull request stays as it was.',
      '',
      approveLine(current.object.sha),
    ]);
    return 'unchanged';
  }

  const updating = existing !== null;
  const noun = kind === 'profile' ? ' profile' : '';
  const title = `${updating ? 'Update' : 'Add'}${noun} ${manifest.name} (${manifest.id}) ${manifest.version}`;
  const commit = await api('POST', '/git/commits', {
    message: `${title}\n\nFrom #${issue.number}.`,
    tree: tree.sha,
    parents: [parentSha],
    author: {
      name: issue.user.login,
      email: `${issue.user.id}+${issue.user.login}@users.noreply.github.com`,
      date: new Date().toISOString(),
    },
  });
  if (current) {
    // On top of the branch in review, this moves it forward. A branch left from a merged pull
    // request is set back onto main.
    await api('PATCH', `/git/refs/heads/${branch}`, { sha: commit.sha, force: !inReview });
  } else {
    await api('POST', '/git/refs', { ref: `refs/heads/${branch}`, sha: commit.sha });
  }

  const body = pullRequestBody(manifest, sub, issue.number, updating);
  if (pr) pr = await api('PATCH', `/pulls/${pr.number}`, { title, body });
  else pr = await api('POST', '/pulls', { title, head: branch, base: 'main', body, maintainer_can_modify: true });
  await api('POST', `/issues/${pr.number}/labels`, { labels: [LABEL] });

  // The check workflow runs on the branch's new commit. A dispatch made with the workflow's
  // token starts it, where a push or a pull request made with it would not.
  let checking = true;
  try {
    await api('POST', '/actions/workflows/check.yml/dispatches', { ref: branch });
  } catch (err) {
    console.error(`The check did not start: ${err.message}`);
    checking = false;
  }

  if (inReview) {
    // The version the branch held before, from its proteus.json.
    let from = null;
    const oldMeta = before.find((e) => e.path === `${folder}/proteus.json`);
    if (oldMeta) {
      const blob = await api('GET', `/git/blobs/${oldMeta.sha}`);
      try {
        from = JSON.parse(Buffer.from(blob.content, 'base64').toString('utf8')).version ?? null;
      } catch {
        from = null;
      }
    }
    const compare = await api('GET', `/compare/${parentSha}...${commit.sha}`);
    await api('POST', `/issues/${issue.number}/comments`, {
      body: changesComment({ id: manifest.id, kind, from, to: manifest.version, files: compare?.files ?? [], pullRequest: pr.html_url }),
    });
  }

  await say(api, issue.number, comments, [
    `Thanks, @${issue.user.login}. Version ${manifest.version} of this submission is in ${pr.html_url}.`,
    '',
    `A maintainer reviews it there, then approves it on this issue or merges the PR. The Proteus marketplace lists the ${kind} once it is merged. Publishing again before then updates this same submission.`,
    '',
    checking
      ? approveLine(commit.sha)
      : `${approveLine(commit.sha)} The check workflow did not start, so a maintainer starts it on \`${branch}\` from the Actions tab first.`,
  ]);
  return inReview ? 'updated' : 'opened';
}

/** How a maintainer approves the commit `sha`, once the check has passed on it. */
function approveLine(sha) {
  return `To approve this version once its check passes, comment \`/approve ${sha.slice(0, 7)}\`.`;
}

// Run as the workflow step, not when a test imports this file.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const repo = process.env.GITHUB_REPOSITORY;
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const checkout = {
    reserved: JSON.parse(readFileSync('reserved.json', 'utf8')),
    existing(id, kind) {
      // Validation checks the id after this, so a malformed one never reaches a path.
      if (!/^[a-z0-9][a-z0-9._-]*$/.test(id) || id.includes('..')) return null;
      const path = join(folderFor(kind, id), 'proteus.json');
      return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : null;
    },
    removed(id, kind) {
      const all = existsSync('removed.json') ? JSON.parse(readFileSync('removed.json', 'utf8')) : {};
      const list = all[kind === 'profile' ? 'profiles' : 'plugins'] ?? {};
      return Object.hasOwn(list, id) ? list[id] : null;
    },
    listed() {
      return existsSync('plugins') ? readdirSync('plugins').filter((id) => existsSync(join('plugins', id, 'proteus.json'))) : [];
    },
  };
  submit({ api: client(process.env.GITHUB_TOKEN, repo), event, repo, checkout })
    .then((result) => {
      console.log(`submission: ${result}`);
      if (result === 'unreadable' || result === 'refused') process.exitCode = 1;
    })
    .catch((err) => {
      console.error(err);
      process.exitCode = 1;
    });
}
