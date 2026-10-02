// The workflow files themselves. The scripts' tests run against a fake GitHub, so they cannot
// see what only the workflow files decide: which events start each workflow, which token makes
// each push or merge (a push with the workflow's own GITHUB_TOKEN starts no other workflow),
// and where `concurrency` holds runs back or cancels them.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

/**
 * Reads the YAML these workflow files use: maps, lists, plain and quoted scalars, flow lists
 * and block scalars. It is not a whole YAML reader, and fails on what it does not know.
 */
export function readYaml(text) {
  const lines = [];
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\s+$/, '');
    if (line.trim() === '' || line.trim().startsWith('#')) {
      lines.push({ indent: -1, text: '', raw: line });
      continue;
    }
    lines.push({ indent: line.length - line.trimStart().length, text: line.trim(), raw: line });
  }
  let i = 0;

  const scalar = (s) => {
    s = s.replace(/\s+#.*$/, '');
    if (/^'.*'$/.test(s)) return s.slice(1, -1).replace(/''/g, "'");
    if (/^".*"$/.test(s)) return JSON.parse(s);
    if (/^\[.*\]$/.test(s)) {
      const inner = s.slice(1, -1).trim();
      return inner === '' ? [] : inner.split(',').map((x) => scalar(x.trim()));
    }
    if (s === 'true') return true;
    if (s === 'false') return false;
    if (/^-?\d+$/.test(s)) return Number(s);
    return s;
  };

  const skipBlank = () => {
    while (i < lines.length && lines[i].indent === -1) i++;
  };

  // A block scalar: every line indented past `parent`, blank ones included.
  const block = (parent, folded) => {
    const out = [];
    while (i < lines.length && (lines[i].indent === -1 || lines[i].indent > parent)) {
      out.push(lines[i].raw);
      i++;
    }
    while (out.length > 0 && out[out.length - 1].trim() === '') out.pop();
    const cut = Math.min(...out.filter((l) => l.trim() !== '').map((l) => l.length - l.trimStart().length));
    const body = out.map((l) => l.slice(cut));
    return folded ? body.join(' ').replace(/\s+/g, ' ').trim() : body.join('\n') + '\n';
  };

  // The value after `key:` or `- `, at `indent`.
  const value = (rest, indent) => {
    if (rest === '|' || rest === '|-') return block(indent, false);
    if (rest === '>' || rest === '>-') return block(indent, true);
    if (rest !== '') return scalar(rest);
    skipBlank();
    if (i >= lines.length || lines[i].indent <= indent) {
      // A list may sit at the same indent as its key.
      if (i < lines.length && lines[i].indent === indent && lines[i].text.startsWith('- ')) return node(indent);
      return null;
    }
    return node(lines[i].indent);
  };

  const node = (indent) => {
    skipBlank();
    if (lines[i].text.startsWith('- ')) {
      const list = [];
      while (i < lines.length) {
        skipBlank();
        if (i >= lines.length || lines[i].indent !== indent || !lines[i].text.startsWith('- ')) break;
        const rest = lines[i].text.slice(2).trim();
        const inner = indent + 2;
        if (/^[\w-]+:(\s|$)/.test(rest)) {
          // A map that starts on the dash's line.
          lines[i] = { indent: inner, text: rest, raw: ' '.repeat(inner) + rest };
          list.push(node(inner));
        } else {
          i++;
          list.push(value(rest, indent));
        }
      }
      return list;
    }
    const map = {};
    while (i < lines.length) {
      skipBlank();
      if (i >= lines.length || lines[i].indent !== indent) break;
      const m = lines[i].text.match(/^([\w.-]+|'[^']*'|"[^"]*"):(?:\s+(.*))?$/);
      if (!m) throw new Error(`cannot read line ${i + 1}: ${lines[i].text}`);
      i++;
      map[scalar(m[1])] = value((m[2] ?? '').trim(), indent);
    }
    if (i < lines.length && lines[i].indent > indent) throw new Error(`cannot read line ${i + 1}: ${lines[i].text}`);
    return map;
  };

  return node(0);
}

const DIR = new URL('../.github/workflows/', import.meta.url);
const workflows = Object.fromEntries(
  readdirSync(DIR)
    .filter((f) => f.endsWith('.yml'))
    .map((f) => {
      const text = readFileSync(new URL(f, DIR), 'utf8');
      return [f, { text, yaml: readYaml(text) }];
    }),
);

/** Every step of every job in a workflow, with its job's id. */
const stepsOf = (wf) => Object.entries(wf.yaml.jobs).flatMap(([job, j]) => (j.steps ?? []).map((s) => ({ job, ...s })));

test('the YAML reader reads what the workflows use', () => {
  const got = readYaml(
    [
      '# a comment',
      'name: Test',
      'on:',
      '  push:',
      '    branches: [main]',
      "    paths: ['plugins/**']",
      '  workflow_dispatch:',
      'jobs:',
      '  a:',
      '    if: >-',
      '      ${{ x &&',
      '      y }}',
      '    steps:',
      '      - uses: actions/checkout@v4',
      '        with:',
      '          fetch-depth: 0',
      '      - run: |',
      '          one',
      '',
      '          two',
      '      - name: "quoted"',
    ].join('\n'),
  );
  assert.deepEqual(got, {
    name: 'Test',
    on: { push: { branches: ['main'], paths: ['plugins/**'] }, workflow_dispatch: null },
    jobs: {
      a: {
        if: '${{ x && y }}',
        steps: [{ uses: 'actions/checkout@v4', with: { 'fetch-depth': 0 } }, { run: 'one\n\ntwo\n' }, { name: 'quoted' }],
      },
    },
  });
});

test('every workflow reads, and none runs on pull_request_target', () => {
  assert.deepEqual(Object.keys(workflows).sort(), ['check.yml', 'index.yml', 'submission.yml']);
  for (const [file, wf] of Object.entries(workflows)) {
    // pull_request_target runs with write access on code from a fork.
    assert.ok(!('pull_request_target' in wf.yaml.on), `${file} runs on pull_request_target`);
    assert.ok(!('workflow_run' in wf.yaml.on), `${file} runs on workflow_run`);
  }
});

test('the check runs on every pull request and every push to main', () => {
  const on = workflows['check.yml'].yaml.on;
  assert.ok('pull_request' in on);
  assert.ok(!on.pull_request?.paths && !on.pull_request?.branches, 'no pull request skips the check');
  assert.deepEqual(on.push, { branches: ['main'] });
});

test('the check runs pull request code with a read-only token and no secrets', () => {
  const wf = workflows['check.yml'];
  assert.deepEqual(wf.yaml.permissions, { contents: 'read' });
  for (const job of Object.values(wf.yaml.jobs)) assert.equal(job.permissions, undefined, 'no job widens the token');
  assert.doesNotMatch(wf.text, /\$\{\{[^}]*secrets\./);
  for (const step of stepsOf(wf).filter((s) => s.uses?.startsWith('actions/checkout@'))) {
    assert.equal(step.with?.['persist-credentials'], false, 'the checkout keeps no token for the plugins to read');
  }
});

test('no run of the check is cancelled by a later one', () => {
  const c = workflows['check.yml'].yaml.concurrency;
  assert.ok(!c || c['cancel-in-progress'] !== true);
});

test('the index is rebuilt after a change to plugins or profiles on main, or when asked', () => {
  const on = workflows['index.yml'].yaml.on;
  assert.deepEqual(on.push.branches, ['main']);
  for (const path of ['plugins/**', 'profiles/**']) assert.ok(on.push.paths.includes(path), path);
  // approve.mjs merges with GITHUB_TOKEN, which starts no push workflow, so it starts this one.
  assert.ok('workflow_dispatch' in on);
});

test('one index run at a time, and none is cancelled', () => {
  const c = workflows['index.yml'].yaml.concurrency;
  assert.equal(typeof c?.group, 'string');
  assert.equal(c['cancel-in-progress'], false, 'a cancelled run would leave index.json behind main');
});

test("the index is pushed with the workflow's own token", () => {
  const wf = workflows['index.yml'];
  assert.deepEqual(wf.yaml.permissions, { contents: 'write' });
  assert.doesNotMatch(wf.text, /\$\{\{[^}]*secrets\.(?!GITHUB_TOKEN\b)/, 'no other token');
  const pushes = stepsOf(wf).filter((s) => /\bgit push\b/.test(s.run ?? ''));
  assert.equal(pushes.length, 1);
  // The checkout's own credentials make the push, so it starts no workflow, this one included.
  for (const step of stepsOf(wf).filter((s) => s.uses?.startsWith('actions/checkout@'))) {
    assert.equal(step.with?.token, undefined);
    assert.notEqual(step.with?.['persist-credentials'], false, 'the push needs the checkout token');
  }
});

test('submissions start from issues and comments, one submit run per issue', () => {
  const wf = workflows['submission.yml'];
  assert.deepEqual(Object.keys(wf.yaml.on).sort(), ['issue_comment', 'issues']);
  // Set on the workflow or on the submit job, so parts that arrive together make one pull
  // request, and a later part never cancels a run that is under way.
  const c = wf.yaml.jobs.submit.concurrency ?? wf.yaml.concurrency;
  assert.match(c.group, /github\.event\.issue\.number/);
  assert.equal(c['cancel-in-progress'], false);
});

test("submissions and approvals push and merge with the workflow's own token", () => {
  const wf = workflows['submission.yml'];
  assert.doesNotMatch(wf.text, /\$\{\{[^}]*secrets\.(?!GITHUB_TOKEN\b)/);
  for (const step of stepsOf(wf).filter((s) => s.run?.includes('node scripts/'))) {
    assert.equal(step.env?.GITHUB_TOKEN, '${{ secrets.GITHUB_TOKEN }}', `${step.job}: ${step.run}`);
  }
  // A merge with GITHUB_TOKEN starts no push workflow, so approve starts the index itself.
  assert.equal(wf.yaml.jobs.approve.permissions.actions, 'write');
  assert.match(readFileSync(new URL('../scripts/approve.mjs', import.meta.url), 'utf8'), /index\.yml/);
});

test('only the commands of the issue author start a submission, and only /approve approves', () => {
  const { submit, approve } = workflows['submission.yml'].yaml.jobs;
  assert.match(submit.if, /!github\.event\.issue\.pull_request/);
  assert.match(submit.if, /startsWith\(github\.event\.comment\.body, '\/'\)/, 'a command is not a part of the files');
  assert.match(approve.if, /github\.event\.action == 'created'/, 'an edited comment approves nothing');
  assert.match(approve.if, /startsWith\(github\.event\.comment\.body, '\/approve'\)/);
});
