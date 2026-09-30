// A small client for the GitHub REST API, shared by the workflow scripts. Each call returns
// the decoded answer, null for a 404, and throws for any other failure. The error carries the
// status and GitHub's message, so a caller can tell a refusal from an outage.

import { BOT_MARKER } from './registry.mjs';

export class GitHubError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/** A function that calls the API of one repository with one token. */
export function client(token, repo) {
  const base = `https://api.github.com/repos/${repo}`;
  return async function api(method, path, body) {
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
    if (!res.ok) {
      let message = text;
      try {
        message = JSON.parse(text).message ?? text;
      } catch {
        // The body was not JSON, so it is the message as it is.
      }
      throw new GitHubError(res.status, `${method} ${path}: ${res.status} ${message}`);
    }
    return text ? JSON.parse(text) : null;
  };
}

/** Every comment on an issue, oldest first. */
export async function allComments(api, number) {
  const out = [];
  for (let page = 1; page < 20; page++) {
    const batch = await api('GET', `/issues/${number}/comments?per_page=100&page=${page}`);
    out.push(...(batch ?? []));
    if (!batch || batch.length < 100) break;
  }
  return out;
}

/** Writes the one bot comment on an issue, or updates it when there is one already. */
export async function say(api, number, comments, lines) {
  const body = [BOT_MARKER, ...lines].join('\n');
  const mine = comments.find((c) => c.user?.type === 'Bot' && (c.body ?? '').startsWith(BOT_MARKER));
  if (mine) await api('PATCH', `/issues/comments/${mine.id}`, { body });
  else await api('POST', `/issues/${number}/comments`, { body });
}
