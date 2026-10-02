// The rules of the registry, shared by the workflows and the tests. Nothing here talks to
// GitHub or touches the disk.
//
// A submission arrives as an issue. The Proteus app writes the plugin into the issue as
// readable code blocks: a manifest first, then each file. What does not fit in the issue
// continues in comments by the same person. Each block sits under a marker line:
//
//   <!-- proteus-manifest -->
//   ```json
//   {"format":2,"revision":"k2x9","id":"my.plugin","version":"1.0.0","files":["init.lua"]}
//   ```
//
//   <!-- proteus-file path="init.lua" part="1" of="1" rev="k2x9" -->
//   ```lua
//   return { name = 'My Plugin' }
//   ```
//
// A fence is always longer than any run of backticks in the file, so a file cannot close its
// own block. The block holds the file's text plus one newline before the closing fence. A
// file too big for one comment is split at a line break into numbered parts.
//
// Publishing again edits the same issue. Every publish has its own revision, on the manifest
// and on each block, and only blocks of the manifest's revision count. So an issue caught
// halfway through an edit is read as incomplete rather than as a mix of two versions.
//
// The registry holds two kinds of thing. A plugin is a folder of code in plugins/<id>/. A
// profile is a list of plugins with its settings, one profile.lua in profiles/<id>/. A
// manifest with `"kind": "profile"` holds a profile, and one without a kind holds a plugin.

import { createHash } from 'node:crypto';

/** The title every plugin submission issue starts with. */
export const TITLE_PREFIX = 'Plugin submission:';

/** The title every profile submission issue starts with. */
export const PROFILE_TITLE_PREFIX = 'Profile submission:';

/** The title of an issue in which an author asks to take down a plugin they published. */
export const REMOVAL_TITLE_PREFIX = 'Removal request:';

/** The title of an issue in which an author asks to take down a profile they published. */
export const PROFILE_REMOVAL_TITLE_PREFIX = 'Profile removal request:';

/**
 * What a removal request asks to take down, as `{ kind, id }`, from the issue's title, or null
 * for any other issue. Proteus opens these with Withdraw from the Registry.
 */
export function removalOf(issue) {
  const title = String(issue?.title ?? '');
  for (const [prefix, kind] of [
    [PROFILE_REMOVAL_TITLE_PREFIX, 'profile'],
    [REMOVAL_TITLE_PREFIX, 'plugin'],
  ]) {
    if (title.startsWith(prefix + ' ')) {
      const id = title.slice(prefix.length + 1).trim().split(/\s+/)[0] ?? '';
      return ID.test(id) && id.length <= 64 && !id.includes('..') ? { kind, id } : null;
    }
  }
  return null;
}

/** The two kinds of thing the registry lists. */
export const KINDS = ['plugin', 'profile'];

/** The kind a submission or a proteus.json holds: `profile`, or `plugin` when it names none. */
export function kindOf(manifest) {
  return manifest?.kind === 'profile' ? 'profile' : 'plugin';
}

/** The folder that holds one listed plugin or profile, such as plugins/my.plugin. */
export function folderFor(kind, id) {
  return `${kind === 'profile' ? 'profiles' : 'plugins'}/${id}`;
}

/** The file every submission of a kind must hold at its top. */
export const MAIN_FILE = { plugin: 'init.lua', profile: 'profile.lua' };

/**
 * The label on every submission issue and the pull request made from it. GitHub drops a label
 * that someone without push access asks for, so the workflow puts it on as well.
 */
export const LABEL = '[AUTOMATED] Plugin Request';

/** True for an issue that holds a submission, by its label, its title or its manifest. */
export function isSubmission(issue) {
  const labels = (issue.labels ?? []).map((l) => (typeof l === 'string' ? l : l.name));
  return (
    labels.includes(LABEL) ||
    String(issue.title ?? '').startsWith(TITLE_PREFIX) ||
    String(issue.title ?? '').startsWith(PROFILE_TITLE_PREFIX) ||
    removalOf(issue) !== null ||
    /<!--\s*proteus-manifest\s*-->/.test(String(issue.body ?? ''))
  );
}

/** The line a bot comment starts with, so the next run finds and updates it. */
export const BOT_MARKER = '<!-- proteus-registry-bot -->';

/**
 * The command a comment gives, such as `approve` for a comment that starts with /approve, or
 * null for an ordinary comment. Only the first line counts, and text after the command is a
 * note for people.
 */
export function commandOf(body) {
  const first = String(body ?? '').trim().split(/\r?\n/)[0].trim();
  const m = first.match(/^\/([a-z]+)(?:\s|$)/i);
  return m ? m[1].toLowerCase() : null;
}

/**
 * The commit an /approve comment names, such as `1a2b3c4` in `/approve 1a2b3c4 thanks!`, or
 * null when it names none. It is the first word after the command, as 7 to 40 hex digits.
 */
export function approvedCommit(body) {
  const first = String(body ?? '').trim().split(/\r?\n/)[0].trim();
  const m = first.match(/^\/[a-z]+\s+([0-9a-f]{7,40})(?:\s|$)/i);
  return m ? m[1].toLowerCase() : null;
}

/** True for a repository permission that lets a person approve a submission. */
export function canApprove(permission) {
  return ['admin', 'maintain', 'write'].includes(permission);
}

/** The branch the workflow writes an issue's submission to. */
export function branchFor(issue) {
  return `submission/${issue}`;
}

export const LIMITS = {
  files: 200,
  fileBytes: 512 * 1024,
  totalBytes: 2 * 1024 * 1024,
  depth: 4,
  /** Parts of one file. */
  parts: 100,
};

/** A line longer than this hides code from a reviewer, as minified code does. */
export const MAX_LINE = 1000;

/** The longest note on what changed in a version that a submission may carry. */
export const MAX_CHANGES = 2000;

/**
 * What a plugin may ask to do beyond drawing and keeping its own data. Proteus knows the same
 * list. `full` marks the ones that amount to full access to the computer.
 */
export const PERMISSIONS = {
  net: { label: 'Network', full: false },
  clipboard: { label: 'Read the clipboard', full: false },
  midi: { label: 'MIDI keyboards', full: false },
  files: { label: 'Files on this computer', full: true },
  process: { label: 'Run programs', full: true },
  workspace: { label: 'Change the workspace', full: true },
  kernel: { label: 'Control plugins', full: true },
};

/** Workspace folders that belong to Proteus itself, so no plugin may claim one in `folders`. */
export const RESERVED_FOLDERS = ['data', 'plugins', 'profiles', 'lib', 'types', 'graphs', 'blocks', 'docs', 'tooling'];

// The manifest and the file blocks. A closing fence has exactly as many backticks as its
// opening fence, and must end its line.
const MANIFEST = /<!--\s*proteus-manifest\s*-->[ \t]*\n(`{3,})json[ \t]*\n([\s\S]*?)\n\1[ \t]*(?=\n|$)/;
const FILE =
  /<!--\s*proteus-file path="([^"\n]+)" part="(\d+)" of="(\d+)"(?: rev="([^"\n]*)")?\s*-->[ \t]*\n(`{3,})[^\n`]*\n([\s\S]*?)\n\5[ \t]*(?=\n|$)/g;

/**
 * Reads a submission out of the texts of an issue and its comments. Returns
 * `{ complete, sub, missing, error }`. `complete` is true once the manifest is there and every
 * file it lists has all its parts. `sub` is then the submission: the manifest's fields, with
 * `files` mapping each path to its text. A part that appears twice keeps its last copy, so an
 * edited comment replaces the old text. Line endings become \n.
 */
export function collectSubmission(texts) {
  const all = texts.map((t) => String(t ?? '').replace(/\r\n/g, '\n'));
  let manifest = null;
  for (const text of all) {
    const m = text.match(MANIFEST);
    if (!m) continue;
    try {
      manifest = JSON.parse(m[2]);
    } catch {
      return { complete: false, missing: [], error: 'The manifest could not be read. Publish the plugin again from Proteus.' };
    }
    break;
  }
  if (!manifest || typeof manifest !== 'object') return { complete: false, missing: [] };
  if (manifest.format !== 2) {
    return { complete: false, missing: [], error: 'The submission is in a format this registry does not know.' };
  }
  const found = new Map();
  for (const text of all) {
    for (const m of text.matchAll(FILE)) {
      const [, path, k, n, rev] = m;
      const part = Number(k);
      const of = Number(n);
      if (!(part >= 1 && part <= of && of <= LIMITS.parts)) continue;
      if ((rev ?? '') !== String(manifest.revision ?? '')) continue;
      const entry = found.get(path) ?? { of, pieces: new Map() };
      entry.pieces.set(part, m[6]);
      found.set(path, entry);
    }
  }
  const names = Array.isArray(manifest.files) ? manifest.files.filter((f) => typeof f === 'string') : [];
  const files = {};
  const missing = [];
  for (const name of names) {
    const entry = found.get(name);
    const pieces = [];
    for (let part = 1; entry && part <= entry.of; part++) {
      if (!entry.pieces.has(part)) break;
      pieces.push(entry.pieces.get(part));
    }
    if (!entry || pieces.length !== entry.of) missing.push(name);
    else files[name] = pieces.join('');
  }
  const complete = names.length > 0 && missing.length === 0;
  return { complete, missing, sub: complete ? { ...manifest, files } : null };
}

/**
 * Compares two versions such as 1.2.10 and 1.10.0 by semver precedence: the three numbers
 * first, then a version with a pre-release tag, such as 1.0.0-beta.1, comes before the same
 * version without one. Build metadata after `+` does not count. Returns -1, 0 or 1.
 */
export function compareVersions(a, b) {
  const split = (v) => {
    const text = String(v).split('+')[0];
    const dash = text.indexOf('-');
    const core = (dash < 0 ? text : text.slice(0, dash)).split('.').map((x) => Number.parseInt(x, 10) || 0);
    return { core, pre: dash < 0 ? [] : text.slice(dash + 1).split('.') };
  };
  const pa = split(a);
  const pb = split(b);
  for (let i = 0; i < Math.max(pa.core.length, pb.core.length, 3); i++) {
    const d = (pa.core[i] ?? 0) - (pb.core[i] ?? 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  if (pa.pre.length === 0 || pb.pre.length === 0) {
    return pa.pre.length === pb.pre.length ? 0 : pa.pre.length === 0 ? 1 : -1;
  }
  for (let i = 0; i < Math.max(pa.pre.length, pb.pre.length); i++) {
    const x = pa.pre[i];
    const y = pb.pre[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    const nx = /^\d+$/.test(x);
    const ny = /^\d+$/.test(y);
    // Numeric identifiers compare as numbers and come before words.
    if (nx && ny) {
      const d = Number(x) - Number(y);
      if (d !== 0) return d < 0 ? -1 : 1;
    } else if (nx !== ny) {
      return nx ? -1 : 1;
    } else if (x !== y) {
      return x < y ? -1 : 1;
    }
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
  if (path === 'proteus.json') return 'proteus.json is written by the registry, so a plugin cannot hold its own';
  return null;
}

/**
 * Why a file's text cannot go in the registry, or null. Every file is text a reviewer can
 * read: UTF-8 without control characters, without the characters that reorder text on screen
 * so code reads differently than it runs, and without lines so long that code hides in them.
 * `text` is a string, or the file's bytes.
 */
export function textProblem(path, text, { vendored = false } = {}) {
  let s = text;
  if (typeof text !== 'string') {
    try {
      s = new TextDecoder('utf-8', { fatal: true }).decode(text);
    } catch {
      return `${path} is not UTF-8 text`;
    }
  }
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(s)) return `${path} holds control characters`;
  if (/[\u202a-\u202e\u2066-\u2069]/.test(s)) return `${path} holds characters that reorder text`;
  // A vendored file is built code from elsewhere, checked by its hash against its source
  // instead of read line by line, so its lines may be as long as the build made them.
  if (vendored) return null;
  const lines = s.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if ([...lines[i]].length > MAX_LINE) return `${path} has a line longer than ${MAX_LINE} characters, at line ${i + 1}`;
  }
  return null;
}

/** The SHA-256 of a file's text or bytes, as hex. */
export function sha256(text) {
  return createHash('sha256').update(typeof text === 'string' ? Buffer.from(text, 'utf8') : text).digest('hex');
}

/**
 * The npm packages a plugin may vendor files from. A maintainer adds one here, in a pull
 * request of its own, after checking who publishes it. A vendored file is not read line by
 * line, so only a package the registry trusts may vouch for one.
 */
export const VENDOR_PACKAGES = ['@webaudiomodules/sdk'];

/** The kinds of file a plugin may vendor: built JavaScript and CSS. Never Lua. */
export const VENDOR_EXTENSIONS = ['.js', '.mjs', '.cjs', '.css'];

// npm:<package>@<exact version>/<path in the package>.
const NPM_SOURCE = /^npm:(@?[a-z0-9][a-z0-9._-]*(?:\/[a-z0-9][a-z0-9._-]*)?)@(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\/([A-Za-z0-9_@-][A-Za-z0-9._@/-]*)$/;

/** The package, version and path an npm source names, or null when it is not one. */
export function npmSource(source) {
  const m = typeof source === 'string' ? NPM_SOURCE.exec(source) : null;
  if (!m || m[3].split('/').some((part) => part === '' || part === '.' || part === '..')) return null;
  return { name: m[1], version: m[2], path: m[3] };
}

/**
 * The files a plugin vendors, from its vendor.json, and what is wrong with it. A vendored file
 * is built JavaScript or CSS the plugin copies from a published npm package, such as a
 * library's build: vendor.json names each one with its source, its license and its SHA-256,
 * so a reviewer checks it against the source instead of reading it, and
 * `node scripts/vendor.mjs verify`, a step of the check, fetches the source and compares.
 * Only packages in VENDOR_PACKAGES count, and only the kinds of file in VENDOR_EXTENSIONS.
 * `files` maps each path to its text.
 */
export function vendorOf(files) {
  const vendored = new Set();
  const problems = [];
  const text = files['vendor.json'];
  if (text === undefined) return { vendored, problems, entries: {} };
  let data;
  try {
    data = JSON.parse(typeof text === 'string' ? text : Buffer.from(text).toString('utf8'));
  } catch {
    return { vendored, problems: ['vendor.json is not valid JSON.'], entries: {} };
  }
  const entries = data && typeof data.files === 'object' && !Array.isArray(data.files) ? data.files : null;
  if (!entries) return { vendored, problems: ['vendor.json needs a files table: each path with its source, license and sha256.'], entries: {} };
  for (const [path, entry] of Object.entries(entries)) {
    if (files[path] === undefined) {
      problems.push(`vendor.json names ${path}, which the plugin does not have.`);
      continue;
    }
    let good = true;
    const ext = path.includes('.') ? path.slice(path.lastIndexOf('.')).toLowerCase() : '';
    if (!VENDOR_EXTENSIONS.includes(ext)) {
      problems.push(`vendor.json can vouch only for built JavaScript or CSS (${VENDOR_EXTENSIONS.join(', ')}), so ${path} is read line by line.`);
      good = false;
    }
    const npm = npmSource(entry?.source);
    if (!npm) {
      problems.push(`vendor.json must give ${path} a source: npm:<package>@<version>/<path>, with an exact version.`);
      good = false;
    } else if (!VENDOR_PACKAGES.includes(npm.name)) {
      problems.push(`${npm.name} is not a package this registry takes vendored files from. A maintainer adds one after checking it.`);
      good = false;
    }
    if (!entry || typeof entry.license !== 'string' || !entry.license.trim()) {
      problems.push(`vendor.json must give ${path} the license it comes under, such as MIT.`);
    }
    if (!entry || entry.sha256 !== sha256(files[path])) {
      problems.push(`${path} does not match the sha256 in vendor.json.`);
      continue;
    }
    if (good) vendored.add(path);
  }
  return { vendored, problems, entries };
}

/**
 * Why a name or a description cannot go in the pull request as it is, or null. Both show in
 * its text, so they hold no line breaks, and none of `<`, `>` or backticks, which could
 * open an HTML comment or a code block that hides the rest, such as the permissions.
 */
export function plainTextProblem(text) {
  if (/[\u0000-\u001f\u007f\u2028\u2029]/.test(text)) return 'must be one line, without control characters';
  if (/[<>`]/.test(text)) return 'cannot hold <, > or backticks';
  return null;
}

/** Why a `requires.proteus` condition such as `>=0.2.0 <1.0.0` cannot be read, or null. */
export function versionSpecProblem(spec) {
  if (typeof spec !== 'string' || !spec.trim()) return 'requires.proteus must be a version such as >=0.2.0';
  for (const cond of spec.trim().split(/\s+/)) {
    if (!/^(>=|>|<=|<|==?|)v?\d+(\.\d+){0,2}$/.test(cond)) return `requires.proteus cannot read ${cond}`;
  }
  return null;
}

/**
 * Every problem with a submission, as sentences for the person who sent it. An empty list
 * means it can become a pull request. `existing` is the plugin's or profile's proteus.json on
 * the main branch, when it is listed already. `author` is the GitHub user who sent it.
 * `reserved` holds the ids of what ships with Proteus: `ids` and `prefixes` for plugins, and
 * `profiles` for profiles. `official` lists reserved ids the maintainers publish here, such as
 * `proteus.git`. Only the check of a pull request passes it, so an issue never publishes one.
 * `removed` is the owner of an id that was taken down, from removed.json, or null: only that
 * owner may use the id again, so installed copies are never offered someone else's code.
 */
export function validate(
  sub,
  { existing = null, author = null, reserved = { ids: [], prefixes: [] }, known = null, official = [], removed = null } = {},
) {
  const problems = [];
  const kind = kindOf(sub);
  const noun = kind === 'profile' ? 'profile' : 'plugin';
  const id = sub.id;
  const taken =
    typeof id === 'string' &&
    !official.includes(id) &&
    (kind === 'profile'
      ? (reserved.profiles ?? []).includes(id)
      : (reserved.ids ?? []).includes(id) || (reserved.prefixes ?? []).some((p) => id.startsWith(p)));
  if (sub.kind !== undefined && !KINDS.includes(sub.kind)) {
    problems.push(`The kind must be one of ${KINDS.join(' or ')}.`);
  }
  if (typeof id !== 'string' || !ID.test(id) || id.length > 64) {
    problems.push(`The ${noun} id must be lower case letters, digits, dots, dashes and underscores, such as my.${noun}.`);
  } else if (taken) {
    problems.push(`The id ${id} belongs to a ${noun} that ships with Proteus. Pick another.`);
  } else if (removed && (!author || removed.id !== author.id)) {
    problems.push(`The ${noun} ${id} was taken down, and its id stays with @${removed.login}. Pick another id.`);
  }
  if (typeof sub.name !== 'string' || !sub.name.trim() || sub.name.length > 80) {
    problems.push(`The ${noun} needs a name of up to 80 characters.`);
  } else if (plainTextProblem(sub.name)) {
    problems.push(`The name ${plainTextProblem(sub.name)}.`);
  }
  if (typeof sub.description !== 'string' || !sub.description.trim()) {
    problems.push(`The ${noun} needs a description, one sentence on what it does.`);
  } else if (sub.description.length > 300) {
    problems.push('The description is longer than 300 characters.');
  } else if (plainTextProblem(sub.description)) {
    problems.push(`The description ${plainTextProblem(sub.description)}.`);
  }
  if (typeof sub.version !== 'string' || !VERSION.test(sub.version)) {
    problems.push('The version must look like 1.0.0.');
  }
  if (sub.changes !== undefined && (typeof sub.changes !== 'string' || sub.changes.length > MAX_CHANGES)) {
    problems.push(`What changed must be text of at most ${MAX_CHANGES} characters.`);
  }
  for (const key of kind === 'profile' ? ['plugins'] : ['depends', 'optional']) {
    const list = sub[key] ?? [];
    if (!Array.isArray(list) || list.some((d) => typeof d !== 'string' || !ID.test(d))) {
      problems.push(`${key} must be a list of plugin ids.`);
    }
  }
  if (kind === 'profile' && (!Array.isArray(sub.plugins) || sub.plugins.length === 0)) {
    problems.push('A profile needs at least one plugin in its plugins list.');
  }
  // Every plugin it needs ships with Proteus, is listed here, or arrives in the same change.
  if (known) {
    const needed = kind === 'profile' ? (sub.plugins ?? []) : (sub.depends ?? []);
    for (const dep of Array.isArray(needed) ? needed : []) {
      if (typeof dep === 'string' && ID.test(dep) && dep !== id && !known.has(dep)) {
        problems.push(`${dep} is neither a plugin that ships with Proteus nor one listed in this registry.`);
      }
    }
  }
  if (kind === 'plugin') {
    const perms = sub.permissions ?? [];
    if (!Array.isArray(perms) || perms.some((p) => typeof p !== 'string')) {
      problems.push('permissions must be a list of names.');
    } else {
      for (const p of perms) {
        if (!Object.hasOwn(PERMISSIONS, p)) {
          problems.push(`There is no permission called ${p}. Proteus knows ${Object.keys(PERMISSIONS).join(', ')}.`);
        }
      }
    }
    const exports = sub.exports ?? [];
    if (!Array.isArray(exports) || exports.some((f) => typeof f !== 'string' || !/^[A-Za-z0-9_-]+$/.test(f))) {
      problems.push('exports must be a list of folders right inside the plugin.');
    } else if (sub.files && typeof sub.files === 'object') {
      for (const f of exports) {
        if (!Object.keys(sub.files).some((name) => name.startsWith(f + '/'))) problems.push(`The plugin exports ${f}, which holds no files.`);
      }
    }
    const folders = sub.folders ?? [];
    if (!Array.isArray(folders) || folders.some((f) => typeof f !== 'string')) {
      problems.push('folders must be a list of folder names.');
    } else {
      for (const f of folders) {
        if (!/^[A-Za-z0-9_-]+$/.test(f)) problems.push(`${f} is not a plain folder name.`);
        else if (RESERVED_FOLDERS.includes(f.toLowerCase())) problems.push(`The folder ${f} belongs to Proteus itself.`);
      }
    }
  }
  if (sub.requires !== undefined) {
    const req = sub.requires;
    if (!req || typeof req !== 'object' || Array.isArray(req)) {
      problems.push('requires must be a table with proteus and features.');
    } else {
      if (req.proteus !== undefined) {
        const problem = versionSpecProblem(req.proteus);
        if (problem) problems.push(problem[0].toUpperCase() + problem.slice(1) + '.');
      }
      const features = req.features ?? [];
      if (!Array.isArray(features) || features.some((f) => typeof f !== 'string' || !/^[a-z][a-z-]*$/.test(f))) {
        problems.push('requires.features must be a list of feature names.');
      }
    }
  }
  const files = sub.files && typeof sub.files === 'object' && !Array.isArray(sub.files) ? sub.files : null;
  if (!files) {
    problems.push('The submission holds no files.');
    return problems;
  }
  const names = Object.keys(files);
  const main = MAIN_FILE[kind];
  if (!names.includes(main)) problems.push(`A ${noun} needs a${main === 'init.lua' ? 'n' : ''} ${main} at its top.`);
  if (names.length > LIMITS.files) problems.push(`A ${noun} can hold at most ${LIMITS.files} files.`);
  const vendor = vendorOf(files);
  problems.push(...vendor.problems);
  // Windows and macOS see init.lua and INIT.lua as one file, so whichever is written last
  // would run there instead of the one a reviewer read.
  const lower = new Map();
  for (const name of names) {
    const key = name.toLowerCase();
    if (lower.has(key)) problems.push(`${lower.get(key)} and ${name} differ only in case. Rename one.`);
    else lower.set(key, name);
  }
  let total = 0;
  for (const name of names) {
    const problem = pathProblem(name) ?? textProblem(name, files[name], { vendored: vendor.vendored.has(name) });
    if (problem) problems.push(problem[0].toUpperCase() + problem.slice(1) + '.');
    if (typeof files[name] !== 'string' && !(files[name] instanceof Uint8Array)) {
      problems.push(`${name} is not text.`);
      continue;
    }
    const bytes = typeof files[name] === 'string' ? Buffer.byteLength(files[name], 'utf8') : files[name].length;
    total += bytes;
    if (bytes > LIMITS.fileBytes) problems.push(`${name} is larger than ${LIMITS.fileBytes / 1024} KB.`);
  }
  if (total > LIMITS.totalBytes) problems.push(`The ${noun} is larger than ${LIMITS.totalBytes / 1024 / 1024} MB.`);
  if (existing) {
    const owner = existing.author ?? {};
    if (author && owner.id && owner.id !== author.id) {
      problems.push(`${id} belongs to @${owner.login}. Only its author can update it, so pick another id for a new ${noun}.`);
    }
    if (typeof sub.version === 'string' && VERSION.test(sub.version) && compareVersions(sub.version, existing.version) <= 0) {
      problems.push(`${id} is at version ${existing.version} already. Raise the version to publish an update.`);
    }
  }
  return problems;
}

/** The proteus.json the registry keeps beside a plugin's or a profile's files. */
export function manifestFor(sub, author, issue) {
  const common = {
    id: sub.id,
    name: sub.name.trim(),
    description: sub.description.trim(),
    version: sub.version,
    // What changed in this version, in the author's words, for reviewers and for the marketplace.
    ...(typeof sub.changes === 'string' && sub.changes.trim() ? { changes: sub.changes.trim() } : {}),
  };
  const own =
    kindOf(sub) === 'profile'
      ? { kind: 'profile', plugins: sub.plugins ?? [] }
      : {
          depends: sub.depends ?? [],
          optional: sub.optional ?? [],
          permissions: sub.permissions ?? [],
          folders: sub.folders ?? [],
          ...(sub.exports?.length ? { exports: sub.exports } : {}),
        };
  const requires = sub.requires && typeof sub.requires === 'object' ? sub.requires : null;
  return {
    ...common,
    ...own,
    ...(requires ? { requires: { proteus: requires.proteus, features: requires.features ?? [] } } : {}),
    author: { login: author.login, id: author.id },
    issue,
    files: Object.keys(sub.files).sort(),
  };
}

/** How many past versions of a plugin or profile the index keeps, newest first. */
export const MAX_VERSIONS = 20;

/** The fields of an index entry that come from one version of a folder's proteus.json. */
function versionFields(kind, manifest, commit, updated) {
  const requires = manifest.requires ? { requires: manifest.requires } : {};
  const own =
    kind === 'profile'
      ? { ...requires, plugins: manifest.plugins ?? [] }
      : {
          depends: manifest.depends ?? [],
          optional: manifest.optional ?? [],
          permissions: manifest.permissions ?? [],
          folders: manifest.folders ?? [],
          ...(manifest.exports?.length ? { exports: manifest.exports } : {}),
          ...requires,
        };
  return {
    version: manifest.version,
    ...(manifest.changes ? { changes: manifest.changes } : {}),
    ...own,
    files: manifest.files ?? [],
    commit,
    updated,
  };
}

/**
 * The index the app reads: one entry per plugin and one per profile, each list in name order.
 * `commit` is the last commit that changed the folder, so the app installs exactly what was
 * approved. The format stays 1, since a version of the app that knows only plugins reads the
 * `plugins` list and leaves `profiles` alone, and one that knows no `versions` or `issue`
 * leaves them alone too.
 *
 * Each entry may carry `versions`, the past versions historyOf found, newest first, and
 * `issue`, the number of the issue that first submitted it, whose reactions the marketplace
 * shows as its rating.
 */
export function buildIndex(entries) {
  const byName = (a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()) || a.id.localeCompare(b.id);
  const build = (kind) => (e) => {
    const { version, ...fields } = versionFields(kind, e.manifest, e.commit, e.updated);
    return {
      id: e.manifest.id,
      name: e.manifest.name,
      description: e.manifest.description,
      version,
      author: e.manifest.author?.login ?? '',
      ...fields,
      ...(Number.isInteger(e.issue) && e.issue > 0 ? { issue: e.issue } : {}),
      ...(e.versions?.length ? { versions: e.versions.slice(0, MAX_VERSIONS) } : {}),
    };
  };
  const plugins = entries
    .filter((e) => kindOf(e.manifest) === 'plugin')
    .map(build('plugin'))
    .sort(byName);
  const profiles = entries
    .filter((e) => kindOf(e.manifest) === 'profile')
    .map(build('profile'))
    .sort(byName);
  return { format: 1, plugins, profiles };
}

/**
 * The past versions of a plugin or profile, from the history of its folder. `log` lists the
 * commits that changed the folder, newest first, starting at the one the index names, each as
 * `{ commit, updated, manifest, files }`: its proteus.json then (or null) and the paths in the
 * folder apart from proteus.json.
 *
 * The walk stops where the folder was gone, since a plugin taken down and listed again starts
 * afresh, and where someone else published it, so an old version is always the same author's
 * code. A commit whose files do not match its proteus.json is skipped. Each version counts at
 * the last commit that had it, and only versions below the current one count.
 *
 * Returns `versions`, newest first, each with what the app needs to show and install it,
 * `issue`, the oldest submission issue in that span, or null, and `issues`, every issue there.
 */
export function historyOf(log) {
  const empty = { versions: [], issue: null, issues: [] };
  const current = log?.[0];
  if (!current?.manifest) return empty;
  const kind = kindOf(current.manifest);
  const { id, author } = current.manifest;
  const seen = new Set([current.manifest.version]);
  const versions = [];
  const issues = [];
  for (const step of log) {
    const m = step?.manifest;
    if (!m || kindOf(m) !== kind || m.id !== id) break;
    if ((m.author?.id ?? null) !== (author?.id ?? null)) break;
    if (Number.isInteger(m.issue) && m.issue > 0 && !issues.includes(m.issue)) issues.push(m.issue);
    if ([...(m.files ?? [])].sort().join('\n') !== [...(step.files ?? [])].sort().join('\n')) continue;
    if (typeof m.version !== 'string' || !VERSION.test(m.version) || seen.has(m.version)) continue;
    seen.add(m.version);
    if (compareVersions(m.version, current.manifest.version) >= 0) continue;
    versions.push(versionFields(kind, m, step.commit, step.updated));
  }
  versions.sort((a, b) => compareVersions(b.version, a.version));
  return { versions, issue: issues.length ? issues[issues.length - 1] : null, issues };
}

/** Fields every index entry carries, since the app installs and shows by them. */
const INDEX_REQUIRED = {
  plugin: ['id', 'name', 'version', 'author', 'files', 'commit', 'updated', 'depends', 'permissions', 'folders'],
  profile: ['id', 'name', 'version', 'author', 'files', 'commit', 'updated', 'plugins'],
};

/** True when two index fields say the same. Git writes a UTC date with Z or with +00:00, depending on its version. */
function sameField(field, a, b) {
  return field === 'updated' ? Date.parse(a) === Date.parse(b) : JSON.stringify(a) === JSON.stringify(b);
}

/**
 * Every way index.json departs from the history of main, as sentences. The app installs each
 * entry's files from its `commit`, and shows its permissions before the install, so each
 * entry must say what the folder held at that commit, and nothing else.
 *
 * `at(kind, id, commit)` looks in the checkout. It returns null when the commit is not in
 * the history of the branch checked out, and otherwise `{ manifest, files, last, updated,
 * history }`: the folder's proteus.json at that commit (or null), the paths in the folder then,
 * apart from proteus.json, the last commit up to then that changed the folder, the commit's
 * date, and the log historyOf reads, from that commit back. An entry may lag behind the folder,
 * since the index workflow rebuilds it after a merge, but never name a commit that did not
 * change the folder or fields it did not hold.
 *
 * Each past version in `versions` must be one historyOf finds from the entry's commit, with the
 * same fields, so an old version is installable at its commit too. `issue` must be a submission
 * issue of that span.
 */
export function indexProblems(index, at) {
  if (!index || typeof index !== 'object' || index.format !== 1) return ['index.json is not an index of format 1.'];
  const problems = [];
  for (const [key, kind] of [
    ['plugins', 'plugin'],
    ['profiles', 'profile'],
  ]) {
    const list = index[key];
    if (!Array.isArray(list)) {
      problems.push(`index.json has no ${key} list.`);
      continue;
    }
    const seen = new Set();
    for (const entry of list) {
      const id = entry?.id;
      if (typeof id !== 'string' || !ID.test(id)) {
        problems.push(`index.json lists a ${kind} without a valid id.`);
        continue;
      }
      const name = `${key}/${id}`;
      if (seen.has(id)) problems.push(`index.json lists ${name} twice.`);
      seen.add(id);
      if (typeof entry.commit !== 'string' || !/^[0-9a-f]{40}$/.test(entry.commit)) {
        problems.push(`index.json gives ${name} no full commit.`);
        continue;
      }
      const found = at(kind, id, entry.commit);
      if (!found) {
        problems.push(`index.json names ${entry.commit} for ${name}, which is not in the history of main.`);
        continue;
      }
      if (found.last !== entry.commit) {
        problems.push(`index.json names ${entry.commit} for ${name}, which did not change that folder.`);
        continue;
      }
      if (!found.manifest || kindOf(found.manifest) !== kind || found.manifest.id !== id) {
        problems.push(`${name} has no proteus.json of its own at ${entry.commit}.`);
        continue;
      }
      if ([...(found.manifest.files ?? [])].sort().join('\n') !== [...found.files].sort().join('\n')) {
        problems.push(`At ${entry.commit}, the files in ${name} do not match its proteus.json.`);
      }
      const built = buildIndex([{ manifest: found.manifest, commit: entry.commit, updated: found.updated }])[key][0];
      for (const field of INDEX_REQUIRED[kind]) {
        if (!(field in entry)) problems.push(`index.json gives ${name} no ${field}.`);
      }
      // An index from before a field was added may lack it, but what it says must hold.
      for (const field of Object.keys(entry)) {
        if (field === 'versions' || field === 'issue') continue;
        if (!(field in built)) problems.push(`index.json gives ${name} a ${field}, which proteus.json does not have.`);
        else if (!sameField(field, entry[field], built[field])) {
          problems.push(`index.json says ${field} of ${name} is ${JSON.stringify(entry[field])}, but at ${entry.commit.slice(0, 7)} it is ${JSON.stringify(built[field])}.`);
        }
      }
      if (!('versions' in entry) && !('issue' in entry)) continue;
      const past = historyOf(found.history ?? [{ commit: entry.commit, updated: found.updated, manifest: found.manifest, files: found.files }]);
      if ('issue' in entry && !past.issues.includes(entry.issue)) {
        problems.push(`index.json gives ${name} the issue ${JSON.stringify(entry.issue)}, which no version of it up to ${entry.commit.slice(0, 7)} was submitted in.`);
      }
      if (!('versions' in entry)) continue;
      if (!Array.isArray(entry.versions)) {
        problems.push(`index.json gives ${name} versions that are not a list.`);
        continue;
      }
      if (entry.versions.length > MAX_VERSIONS) problems.push(`index.json gives ${name} more than ${MAX_VERSIONS} past versions.`);
      const listed = new Set();
      for (const v of entry.versions) {
        const label = `${name} ${JSON.stringify(v?.version)}`;
        if (listed.has(v?.version)) problems.push(`index.json lists ${label} twice.`);
        listed.add(v?.version);
        const real = past.versions.find((p) => p.version === v?.version);
        if (!real) {
          problems.push(`index.json lists ${label} as a past version, but no commit of its folder up to ${entry.commit.slice(0, 7)} by the same author holds it.`);
          continue;
        }
        const fields = new Set([...Object.keys(v), ...Object.keys(real)]);
        for (const field of fields) {
          if (!(field in v) || !(field in real) || !sameField(field, v[field], real[field])) {
            problems.push(`index.json says ${field} of ${label} is ${JSON.stringify(v[field])}, but the history says ${JSON.stringify(real[field])}.`);
          }
        }
      }
      for (let i = 1; i < entry.versions.length; i++) {
        if (compareVersions(entry.versions[i - 1]?.version, entry.versions[i]?.version) <= 0) {
          problems.push(`index.json lists the past versions of ${name} out of order, newest first.`);
          break;
        }
      }
    }
  }
  return problems;
}

/**
 * Text as it reads, in Markdown: on one line, with the characters that could start a link,
 * emphasis, a code span or HTML escaped. validate refuses the worst of them already.
 */
export function plainMarkdown(text) {
  return String(text)
    .replace(/[\u0000-\u001f\u007f\u2028\u2029]+/g, ' ')
    .replace(/[\\`*_[\]|~#!]/g, (c) => `\\${c}`)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/** The pull request's text: what the plugin or profile is, its files, and what a reviewer checks. */
export function pullRequestBody(manifest, sub, issue, updating) {
  const kind = kindOf(manifest);
  const folder = folderFor(kind, manifest.id);
  const lines = [
    `${updating ? 'Updates' : 'Adds'} ${kind === 'profile' ? 'the profile ' : ''}**${plainMarkdown(manifest.name)}** (\`${manifest.id}\`) ${manifest.version} by @${manifest.author.login}, from #${issue}.`,
    '',
    `> ${plainMarkdown(manifest.description)}`,
    '',
  ];
  if (manifest.changes) {
    lines.push('### What changed', '', ...manifest.changes.split('\n').map((line) => `> ${line}`), '');
  }
  if (kind === 'profile') {
    lines.push('### Plugins', '', (manifest.plugins ?? []).map((id) => `\`${id}\``).join(', ') || 'None.', '');
  } else {
    const perms = manifest.permissions ?? [];
    const shown = perms.map((p) => `**${PERMISSIONS[p]?.label ?? p}**${PERMISSIONS[p]?.full ? ' (full access)' : ''}`);
    lines.push(
      '### Permissions',
      '',
      shown.length ? shown.join(', ') : 'None. It can draw and keep its own data, and nothing more.',
      '',
    );
    if ((manifest.folders ?? []).length) {
      lines.push(`Writes in the workspace folders ${manifest.folders.map((f) => `\`${f}/\``).join(', ')}.`, '');
    }
    if ((manifest.exports ?? []).length) {
      lines.push(`Offers its folders ${manifest.exports.map((f) => `\`${f}/\``).join(', ')} to every plugin's web views.`, '');
    }
    const { entries } = vendorOf(sub.files);
    const vendored = Object.entries(entries);
    if (vendored.length) {
      lines.push('### Vendored files', '', 'Checked by hash against their source instead of line by line:', '');
      for (const [path, e] of vendored) {
        lines.push(`- \`${folder}/${path}\` from \`${String(e.source).replace(/`/g, '')}\` (${plainMarkdown(e.license)})`);
      }
      lines.push('');
    }
  }
  lines.push('### Files', '');
  for (const name of manifest.files) {
    const kb = (Buffer.byteLength(sub.files[name], 'utf8') / 1024).toFixed(1);
    lines.push(`- \`${folder}/${name}\` (${kb} KB)`);
  }
  const review =
    kind === 'profile'
      ? [
          '- [ ] The profile does what the description says, and nothing else.',
          '- [ ] Every plugin it names ships with Proteus or is listed in this registry.',
          '- [ ] Its settings hold no secrets, tokens or personal data.',
        ]
      : [
          '- [ ] The code does what the description says, and nothing else.',
          '- [ ] It asks only for the permissions its purpose needs. A full-access permission needs a clear reason.',
          '- [ ] It reads and writes only the files its purpose needs.',
          '- [ ] It sends nothing over the network, and runs no programs, beyond what its purpose needs.',
          '- [ ] It holds no secrets, tokens or personal data.',
          '- [ ] Every vendored file comes from the source vendor.json names, under a license that lets it be shared, and `node scripts/vendor.mjs verify` agrees.',
        ];
  lines.push('', '### Review', '', ...review, '', `Merging lists the ${kind} in the Proteus marketplace. Closes #${issue}.`);
  return lines.join('\n');
}

/** The line the changes comment starts with, so it is told apart from the status comment. */
export const CHANGES_MARKER = '<!-- proteus-registry-changes -->';

/** A code fence longer than any run of backticks in the text. */
export function fenceFor(text) {
  const longest = Math.max(0, ...(String(text).match(/`+/g) ?? []).map((run) => run.length));
  return '`'.repeat(Math.max(3, longest + 1));
}

/**
 * The comment that shows what changed between two versions of a submission. `files` comes
 * from GitHub's compare API: `filename`, `status`, `additions`, `deletions` and `patch`.
 * proteus.json is left out, since the registry writes it. Past about 60,000 characters the
 * rest are named only, and the pull request shows them.
 */
export function changesComment({ id, kind = 'plugin', from, to, files, pullRequest, limit = 60000 }) {
  const prefix = `${folderFor(kind, id)}/`;
  const shown = files.filter((f) => f.filename.startsWith(prefix) && f.filename !== prefix + 'proteus.json');
  const lines = [
    CHANGES_MARKER,
    `### Changes in ${to}`,
    '',
    from && from !== to ? `Since ${from}, in ${pullRequest}:` : `Since the last publish, in ${pullRequest}:`,
  ];
  if (shown.length === 0) {
    lines.push('', 'Only the manifest changed.');
    return lines.join('\n');
  }
  let size = lines.join('\n').length;
  const left = [];
  for (const f of shown) {
    const name = f.filename.slice(prefix.length);
    const counts = `+${f.additions ?? 0} −${f.deletions ?? 0}`;
    const what = { added: 'new', removed: 'deleted', renamed: 'renamed' }[f.status];
    const summary = `<code>${name}</code> ${what ? what + ', ' : ''}${counts}`;
    const patch = f.patch ?? '';
    const fence = fenceFor(patch);
    const piece = patch
      ? `<details><summary>${summary}</summary>\n\n${fence}diff\n${patch}\n${fence}\n\n</details>`
      : `- ${summary}. The pull request shows this one.`;
    if (size + piece.length + 2 > limit) {
      left.push(name);
      continue;
    }
    lines.push('', piece);
    size += piece.length + 2;
  }
  if (left.length > 0) {
    lines.push('', `Too long to show here: ${left.map((n) => `\`${n}\``).join(', ')}. The pull request shows them.`);
  }
  return lines.join('\n');
}
