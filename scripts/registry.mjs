// The rules of the registry, shared by the workflows and the tests. Nothing here talks to
// GitHub or touches the disk.
//
// A submission arrives as an issue. The Proteus app puts the plugin in the issue as base64
// text, split into numbered parts: the first in the issue itself, the rest in comments by
// the same person. Each part sits in a fenced block under a marker line:
//
//   <!-- proteus-submission part 1 of 2 -->
//   ```text
//   eyJmb3JtYXQiOjEs...
//   ```
//
// Joined and decoded, the parts are one JSON object: { format: 1, id, name, description,
// version, depends, optional, files: { "init.lua": "..." } }.

/** The title every submission issue starts with. */
export const TITLE_PREFIX = 'Plugin submission:';

/**
 * The label on every submission issue and the pull request made from it. GitHub drops a label
 * that someone without push access asks for, so the workflow puts it on as well.
 */
export const LABEL = '[AUTOMATED] Plugin Request';

/** True for an issue that holds a submission, by its label, its title or its first part. */
export function isSubmission(issue) {
  const labels = (issue.labels ?? []).map((l) => (typeof l === 'string' ? l : l.name));
  return (
    labels.includes(LABEL) ||
    String(issue.title ?? '').startsWith(TITLE_PREFIX) ||
    /<!--\s*proteus-submission part 1 of \d+\s*-->/.test(String(issue.body ?? ''))
  );
}

/** The line a bot comment starts with, so the next run finds and updates it. */
export const BOT_MARKER = '<!-- proteus-registry-bot -->';

export const LIMITS = {
  /** Base64 text across every part. */
  payload: 4 * 1024 * 1024,
  files: 200,
  fileBytes: 512 * 1024,
  totalBytes: 2 * 1024 * 1024,
  depth: 4,
  parts: 60,
};

/** Files a plugin may hold. Everything is text, so a reviewer can read all of it. */
export const EXTENSIONS = ['lua', 'md', 'json', 'css', 'txt', 'toml', 'yml', 'yaml', 'html', 'svg'];

const PART = /<!--\s*proteus-submission part (\d+) of (\d+)\s*-->\s*```[a-z]*[ \t]*\r?\n([A-Za-z0-9+/=\s]*?)```/g;

/**
 * Finds the parts of a submission in the texts of an issue and its comments. `complete` is
 * true once every part from 1 to the total is there, and `data` is then the joined base64.
 * A part that appears twice keeps its last copy, so an edited comment replaces the old text.
 */
export function collectParts(texts) {
  const parts = new Map();
  let total = 0;
  for (const text of texts) {
    for (const m of String(text ?? '').matchAll(PART)) {
      const k = Number(m[1]);
      const n = Number(m[2]);
      if (!(k >= 1 && k <= n && n <= LIMITS.parts)) continue;
      if (k === 1 || total === 0) total = n;
      parts.set(k, m[3].replace(/\s+/g, ''));
    }
  }
  let complete = total > 0;
  const pieces = [];
  for (let k = 1; k <= total; k++) {
    if (!parts.has(k)) {
      complete = false;
      break;
    }
    pieces.push(parts.get(k));
  }
  return { total, have: parts.size, complete, data: complete ? pieces.join('') : '' };
}

/** Turns the joined base64 back into the submission. Throws a readable error. */
export function decodePayload(b64) {
  if (b64.length > LIMITS.payload) throw new Error('The submission is larger than the registry takes.');
  let sub;
  try {
    sub = JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));
  } catch {
    throw new Error('The submission could not be read. Publish it again from Proteus.');
  }
  if (!sub || typeof sub !== 'object' || sub.format !== 1) {
    throw new Error('The submission is in a format this registry does not know.');
  }
  return sub;
}

/** Compares two versions such as 1.2.10 and 1.10.0, part by part. */
export function compareVersions(a, b) {
  const pa = String(a).split(/[.+-]/).map((x) => Number.parseInt(x, 10) || 0);
  const pb = String(b).split(/[.+-]/).map((x) => Number.parseInt(x, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

const ID = /^[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*$/;
const SEGMENT = /^[A-Za-z0-9_][A-Za-z0-9._-]*$/;
const VERSION = /^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$/;

/** Why a file path cannot go in a plugin, or null when it can. */
export function pathProblem(path) {
  if (typeof path !== 'string' || path === '') return 'a file has no name';
  const parts = path.split('/');
  if (parts.length > LIMITS.depth) return `${path} is nested too deep`;
  for (const part of parts) {
    if (!SEGMENT.test(part) || part === '.' || part === '..') return `${path} is not a plain file path`;
  }
  const ext = path.includes('.') ? path.slice(path.lastIndexOf('.') + 1).toLowerCase() : '';
  if (!EXTENSIONS.includes(ext)) return `${path} is not a kind of file a plugin may hold (${EXTENSIONS.join(', ')})`;
  if (path === 'proteus.json') return 'proteus.json is written by the registry, so a plugin cannot hold its own';
  return null;
}

/**
 * Every problem with a submission, as sentences for the person who sent it. An empty list
 * means it can become a pull request. `existing` is the plugin's proteus.json on the main
 * branch, when the plugin is listed already. `author` is the GitHub user who sent it.
 */
export function validate(sub, { existing = null, author = null, reserved = { ids: [], prefixes: [] } } = {}) {
  const problems = [];
  const id = sub.id;
  if (typeof id !== 'string' || !ID.test(id) || id.length > 64) {
    problems.push('The plugin id must be lower case letters, digits, dots, dashes and underscores, such as my.plugin.');
  } else if (reserved.ids.includes(id) || reserved.prefixes.some((p) => id.startsWith(p))) {
    problems.push(`The id ${id} belongs to a plugin that ships with Proteus. Pick another.`);
  }
  if (typeof sub.name !== 'string' || !sub.name.trim() || sub.name.length > 80) {
    problems.push('The plugin needs a name of up to 80 characters.');
  }
  if (typeof sub.description !== 'string' || !sub.description.trim()) {
    problems.push('The plugin needs a description, one sentence on what it does.');
  } else if (sub.description.length > 300) {
    problems.push('The description is longer than 300 characters.');
  }
  if (typeof sub.version !== 'string' || !VERSION.test(sub.version)) {
    problems.push('The version must look like 1.0.0.');
  }
  for (const key of ['depends', 'optional']) {
    const list = sub[key] ?? [];
    if (!Array.isArray(list) || list.some((d) => typeof d !== 'string' || !ID.test(d))) {
      problems.push(`${key} must be a list of plugin ids.`);
    }
  }
  const files = sub.files && typeof sub.files === 'object' && !Array.isArray(sub.files) ? sub.files : null;
  if (!files) {
    problems.push('The submission holds no files.');
    return problems;
  }
  const names = Object.keys(files);
  if (!names.includes('init.lua')) problems.push('A plugin needs an init.lua at its top.');
  if (names.length > LIMITS.files) problems.push(`A plugin can hold at most ${LIMITS.files} files.`);
  let total = 0;
  for (const name of names) {
    const problem = pathProblem(name);
    if (problem) problems.push(problem[0].toUpperCase() + problem.slice(1) + '.');
    if (typeof files[name] !== 'string') {
      problems.push(`${name} is not text.`);
      continue;
    }
    const bytes = Buffer.byteLength(files[name], 'utf8');
    total += bytes;
    if (bytes > LIMITS.fileBytes) problems.push(`${name} is larger than ${LIMITS.fileBytes / 1024} KB.`);
  }
  if (total > LIMITS.totalBytes) problems.push(`The plugin is larger than ${LIMITS.totalBytes / 1024 / 1024} MB.`);
  if (existing) {
    const owner = existing.author ?? {};
    if (author && owner.id && owner.id !== author.id) {
      problems.push(`${id} belongs to @${owner.login}. Only its author can update it, so pick another id for a new plugin.`);
    }
    if (typeof sub.version === 'string' && VERSION.test(sub.version) && compareVersions(sub.version, existing.version) <= 0) {
      problems.push(`${id} is at version ${existing.version} already. Raise the version to publish an update.`);
    }
  }
  return problems;
}

/** The proteus.json the registry keeps beside a plugin's files. */
export function manifestFor(sub, author, issue) {
  return {
    id: sub.id,
    name: sub.name.trim(),
    description: sub.description.trim(),
    version: sub.version,
    depends: sub.depends ?? [],
    optional: sub.optional ?? [],
    author: { login: author.login, id: author.id },
    issue,
    files: Object.keys(sub.files).sort(),
  };
}

/**
 * The index the app reads: one entry per plugin, newest first by name order. `commit` is the
 * last commit that changed the plugin's folder, so the app installs exactly what was
 * approved.
 */
export function buildIndex(entries) {
  const plugins = entries
    .map(({ manifest, commit, updated }) => ({
      id: manifest.id,
      name: manifest.name,
      description: manifest.description,
      version: manifest.version,
      author: manifest.author?.login ?? '',
      depends: manifest.depends ?? [],
      optional: manifest.optional ?? [],
      files: manifest.files ?? [],
      commit,
      updated,
    }))
    .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()) || a.id.localeCompare(b.id));
  return { format: 1, plugins };
}

/** The pull request's text: what the plugin is, its files, and what a reviewer checks. */
export function pullRequestBody(manifest, sub, issue, updating) {
  const lines = [
    `${updating ? 'Updates' : 'Adds'} **${manifest.name}** (\`${manifest.id}\`) ${manifest.version} by @${manifest.author.login}, from #${issue}.`,
    '',
    `> ${manifest.description.replace(/\n/g, ' ')}`,
    '',
    '### Files',
    '',
  ];
  for (const name of manifest.files) {
    const kb = (Buffer.byteLength(sub.files[name], 'utf8') / 1024).toFixed(1);
    lines.push(`- \`plugins/${manifest.id}/${name}\` (${kb} KB)`);
  }
  lines.push(
    '',
    '### Review',
    '',
    '- [ ] The code does what the description says, and nothing else.',
    '- [ ] It reads and writes only the files its purpose needs.',
    '- [ ] It sends nothing over the network, and runs no programs, beyond what its purpose needs.',
    '- [ ] It holds no secrets, tokens or personal data.',
    '',
    `Merging lists the plugin in the Proteus store. Closes #${issue}.`,
  );
  return lines.join('\n');
}
