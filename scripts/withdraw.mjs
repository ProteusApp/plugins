// Lets authors take back what they sent. The submission workflow runs it for issue events.
//
// - When the author of a submission issue closes it, which Proteus does with Withdraw from
//   the Registry, the pull request made from it closes too, and its branch goes.
// - A removal request is an issue titled "Removal request: <id>", or "Profile removal
//   request: <id>", which Proteus opens for a plugin or profile that is listed already. When
//   the person who opened it is the listed author, it opens a pull request that deletes the
//   folder, on the same branch a submission would use, so /approve merges it the same way.
//   The index workflow then drops it. Copies people installed stay on their machines.

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { allComments, client, say } from './github.mjs';
import { LABEL, branchFor, folderFor, isSubmission, removalOf } from './registry.mjs';

/**
 * Runs one issue event. `checkout.existing(id, kind)` is a listed plugin's or profile's
 * proteus.json on main, or null. Returns what happened, as a word the tests check: ignored,
 * withdrawn, refused, opened or unchanged.
 */
export async function withdraw({ api, event, repo, checkout }) {
  const issue = event.issue;
  if (!issue || issue.pull_request || !isSubmission(issue)) return 'ignored';
  const owner = repo.split('/')[0];
  const branch = branchFor(issue.number);
  const openPulls = async () => (await api('GET', `/pulls?head=${owner}:${encodeURIComponent(branch)}&state=open`)) ?? [];

  if (event.action === 'closed') {
    // Only the author withdraws. A maintainer who closes an issue decides about the pull
    // request themselves, and /approve closes the issue once it has merged.
    if (event.sender?.id !== issue.user?.id) return 'ignored';
    const pr = (await openPulls())[0];
    if (!pr) return 'ignored';
    await api('POST', `/issues/${pr.number}/comments`, {
      body: `@${issue.user.login} withdrew this in #${issue.number}.`,
    });
    await api('PATCH', `/pulls/${pr.number}`, { state: 'closed' });
    await api('DELETE', `/git/refs/heads/${branch}`);
    return 'withdrawn';
  }

  const removal = removalOf(issue);
  if (!removal || issue.state !== 'open' || !['opened', 'edited', 'reopened'].includes(event.action)) return 'ignored';
  await api('POST', `/issues/${issue.number}/labels`, { labels: [LABEL] });
  const comments = await allComments(api, issue.number);
  const { kind, id } = removal;
  const noun = kind === 'profile' ? 'profile' : 'plugin';
  const listed = checkout.existing(id, kind);
  if (!listed) {
    await say(api, issue.number, comments, [`The registry lists no ${noun} called \`${id}\`, so there is nothing to take down.`]);
    return 'refused';
  }
  if (listed.author?.id !== issue.user.id) {
    await say(api, issue.number, comments, [
      `Only @${listed.author?.login ?? 'its author'}, who published \`${id}\`, can ask to take it down here. A maintainer can still remove it.`,
    ]);
    return 'refused';
  }

  const folder = folderFor(kind, id);
  const main = await api('GET', '/git/ref/heads/main');
  const parent = await api('GET', `/git/commits/${main.object.sha}`);
  const listing = await api('GET', `/git/trees/${parent.tree.sha}?recursive=1`);
  const gone = (listing?.tree ?? [])
    .filter((e) => e.type === 'blob' && e.path.startsWith(folder + '/'))
    .map((e) => ({ path: e.path, mode: '100644', type: 'blob', sha: null }));
  if (gone.length === 0) {
    await say(api, issue.number, comments, [`\`${folder}\` is gone from main already.`]);
    return 'unchanged';
  }
  const tree = await api('POST', '/git/trees', { base_tree: parent.tree.sha, tree: gone });
  const title = `Remove ${kind === 'profile' ? 'profile ' : ''}${listed.name} (${id})`;
  const commit = await api('POST', '/git/commits', {
    message: `${title}\n\nAsked by its author in #${issue.number}.`,
    tree: tree.sha,
    parents: [main.object.sha],
  });
  const current = await api('GET', `/git/ref/heads/${branch}`);
  if (current) await api('PATCH', `/git/refs/heads/${branch}`, { sha: commit.sha, force: true });
  else await api('POST', '/git/refs', { ref: `refs/heads/${branch}`, sha: commit.sha });

  const body = [
    `Removes the ${noun} **${listed.name}** (\`${id}\`), as its author @${issue.user.login} asked in #${issue.number}.`,
    '',
    `Merging deletes \`${folder}/\`, and the index workflow drops it from the marketplace. Copies people installed stay on their machines.`,
    '',
    `Closes #${issue.number}.`,
  ].join('\n');
  let pr = (await openPulls())[0];
  if (pr) pr = await api('PATCH', `/pulls/${pr.number}`, { title, body });
  else pr = await api('POST', '/pulls', { title, head: branch, base: 'main', body, maintainer_can_modify: true });
  await api('POST', `/issues/${pr.number}/labels`, { labels: [LABEL] });
  await say(api, issue.number, comments, [
    `Thanks, @${issue.user.login}. The removal is in ${pr.html_url}.`,
    '',
    'A maintainer approves it by commenting /approve on this issue or by merging the PR.',
  ]);
  return 'opened';
}

// Run as the workflow step, not when a test imports this file.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const repo = process.env.GITHUB_REPOSITORY;
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const checkout = {
    existing(id, kind) {
      const path = join(folderFor(kind, id), 'proteus.json');
      return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : null;
    },
  };
  withdraw({ api: client(process.env.GITHUB_TOKEN, repo), event, repo, checkout })
    .then((result) => console.log(`withdraw: ${result}`))
    .catch((err) => {
      console.error(err);
      process.exitCode = 1;
    });
}
