// Merges a submission's pull request when a maintainer comments /approve <commit> on its
// issue. The submission workflow runs it for that comment, and for no other.
//
// Before it merges, it checks four things: the person who commented can write to this
// repository, the pull request is the one the workflow opened for this issue, its head is
// the commit the comment names, so a maintainer approves exactly what they read, and the
// check workflow passed on that commit. The merge names the same commit, so GitHub refuses
// it if the branch moved in between. After the merge, it starts the index workflow, because
// a merge made with the workflow's own token starts no other workflow. Then it closes the
// issue.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { allComments, client, say } from './github.mjs';
import { approvedCommit, branchFor, canApprove, commandOf, isSubmission } from './registry.mjs';

/** The job in check.yml whose run must pass before a merge. */
export const CHECK = 'check';

/**
 * Runs one /approve comment. `api` calls the GitHub API of `repo`. Returns what happened, as
 * a short word the tests check: ignored, refused, waiting, unnamed, changed, unchecked,
 * failing, failed or merged.
 */
export async function approve({ api, event, repo }) {
  const issue = event.issue;
  const comment = event.comment;
  if (!issue || !comment || issue.pull_request || issue.state !== 'open' || !isSubmission(issue)) {
    return 'ignored';
  }
  if (commandOf(comment.body) !== 'approve') return 'ignored';

  const login = comment.user.login;
  const reply = (text) => api('POST', `/issues/${issue.number}/comments`, { body: text });
  const react = (content) => api('POST', `/issues/comments/${comment.id}/reactions`, { content });

  const access = await api('GET', `/collaborators/${encodeURIComponent(login)}/permission`);
  if (!access || !canApprove(access.permission)) {
    await react('confused');
    await reply(`@${login}, only people who can write to this repository can approve a submission.`);
    return 'refused';
  }

  const owner = repo.split('/')[0];
  const open = await api('GET', `/pulls?head=${owner}:${encodeURIComponent(branchFor(issue.number))}&state=open`);
  const pr = open && open[0];
  if (!pr) {
    await react('confused');
    await reply(`@${login}, this submission has no open pull request to approve yet. The workflow links it in a comment once the plugin passes the rules.`);
    return 'waiting';
  }

  // A resubmission could replace the files while the approval was being written. The
  // comment names the commit the maintainer read, and only that commit merges.
  const sha = pr.head.sha;
  const named = approvedCommit(comment.body);
  if (!named) {
    await react('confused');
    await reply(`@${login}, name the commit you reviewed, so a later version is not approved by mistake: \`/approve ${sha.slice(0, 7)}\` for the head of ${pr.html_url} now.`);
    return 'unnamed';
  }
  if (!sha.toLowerCase().startsWith(named)) {
    await react('confused');
    await reply(`@${login}, ${pr.html_url} is at ${sha.slice(0, 7)} now, not ${named}. Review what changed, then comment \`/approve ${sha.slice(0, 7)}\`.`);
    return 'changed';
  }

  // The check workflow compares what init.lua declares with proteus.json, runs the plugin's
  // tests, StyLua and selene, and fetches each vendored file's source. It must have passed
  // on this very commit.
  const runs = (await api('GET', `/commits/${sha}/check-runs?check_name=${CHECK}&filter=latest&per_page=100`))?.check_runs ?? [];
  const ours = runs.filter((r) => r.name === CHECK && r.app?.slug === 'github-actions');
  if (ours.length === 0 || ours.some((r) => r.status !== 'completed')) {
    await react('confused');
    await reply(`@${login}, the check has not finished on ${sha.slice(0, 7)} yet. Comment \`/approve ${sha.slice(0, 7)}\` again once it passes.`);
    return 'unchecked';
  }
  if (ours.some((r) => r.conclusion !== 'success')) {
    await react('confused');
    const failed = ours.find((r) => r.conclusion !== 'success');
    await reply(`@${login}, the check did not pass on ${sha.slice(0, 7)}: ${failed.html_url ?? failed.conclusion}. It cannot be approved until it does.`);
    return 'failing';
  }

  // Rebasing keeps the submitter as the author of the commit. A repository that turns
  // rebasing off gets a merge commit instead.
  const merge = (method) => api('PUT', `/pulls/${pr.number}/merge`, { merge_method: method, sha });
  try {
    try {
      await merge('rebase');
    } catch (err) {
      if (err.status !== 405 || !/not allowed/i.test(err.message)) throw err;
      await merge('merge');
    }
  } catch (err) {
    await react('confused');
    await reply(`@${login}, GitHub would not merge ${pr.html_url}: ${err.message}`);
    return 'failed';
  }

  await react('rocket');
  await api('POST', '/actions/workflows/index.yml/dispatches', { ref: 'main' });
  const comments = await allComments(api, issue.number);
  await say(api, issue.number, comments, [
    `Approved by @${login} and merged in ${pr.html_url}.`,
    '',
    'The Proteus marketplace lists it once the index workflow finishes, in a minute or two.',
  ]);
  await api('PATCH', `/issues/${issue.number}`, { state: 'closed', state_reason: 'completed' });
  return 'merged';
}

// Run as the workflow step, not when a test imports this file.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const repo = process.env.GITHUB_REPOSITORY;
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  approve({ api: client(process.env.GITHUB_TOKEN, repo), event, repo })
    .then((result) => console.log(`/approve: ${result}`))
    .catch((err) => {
      console.error(err);
      process.exitCode = 1;
    });
}
