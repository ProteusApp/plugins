// A Web Audio Module's own editor, in a window of its own. The module plays in the engine's
// page, and an editor must share a page with the instance it edits, so this page makes a
// second, silent instance of the same module and shows its editor. Values move both ways:
// what the editor changes goes to the plugin, which changes the song, and the engine plays it;
// what changes in the song comes back here.
//
// Messages from the plugin:
//   { type: 'open', url, values }   the module, under the page's mounts, and its values
//   { type: 'set', values }         values that changed in the song
// Messages to the plugin:
//   { type: 'values', values }      values the editor changed, by parameter id
//   { type: 'editor', has }         whether the module has an editor of its own

import { initializeWamHost } from './wam/index.js';

const note = document.getElementById('note');
const box = document.getElementById('editor');
let node = null;
let last = {};

const plain = (values) => {
  const out = {};
  for (const [id, v] of Object.entries(values || {})) out[id] = { id, value: Number(v), normalized: false };
  return out;
};

async function open(url, values) {
  const ctx = new AudioContext();
  const [groupId] = await initializeWamHost(ctx);
  const mod = await import('./' + url);
  const instance = await mod.default.createInstance(groupId, ctx, {});
  node = instance.audioNode;
  await node.setParameterValues(plain(values));
  last = { ...values };
  const gui = await instance.createGui();
  proteus.post({ type: 'editor', has: !!gui });
  if (!gui) {
    note.textContent = 'This module has no editor of its own. Its controls are in Channel settings.';
    return;
  }
  note.remove();
  box.append(gui);
  // An editor sets values on the node, so the page watches them and passes on each change.
  setInterval(async () => {
    const now = await node.getParameterValues(false);
    const changed = {};
    let any = false;
    for (const [id, p] of Object.entries(now)) {
      if (Math.abs((last[id] ?? NaN) - p.value) > 1e-6 || !(id in last)) {
        changed[id] = p.value;
        last[id] = p.value;
        any = true;
      }
    }
    if (any) proteus.post({ type: 'values', values: changed });
  }, 80);
}

proteus.on((m) => {
  if (!m || typeof m !== 'object') return;
  if (m.type === 'open' && !node) {
    open(String(m.url), m.values).catch((err) => {
      note.textContent = 'The editor did not load: ' + (err?.message ?? err);
    });
  } else if (m.type === 'set' && node) {
    Object.assign(last, m.values);
    void node.setParameterValues(plain(m.values));
  }
});
proteus.post({ type: 'ready' });
