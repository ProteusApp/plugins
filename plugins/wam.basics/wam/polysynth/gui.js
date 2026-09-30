// PolySynth's editor: a panel of sliders, one for each parameter, that reads and sets the
// module's values through its audio node, as any WAM host expects of an editor.

const CSS = `
.ps { font: 12px system-ui, sans-serif; color: #e6e9ee; background: linear-gradient(#3a4250, #2b313b);
  padding: 12px 14px; border-radius: 6px; display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 10px 14px; }
.ps h1 { grid-column: 1 / -1; margin: 0 0 4px; font-size: 13px; letter-spacing: .08em; text-transform: uppercase; color: #f0a030; }
.ps label { display: flex; flex-direction: column; gap: 4px; }
.ps .name { color: #aab4c2; font-size: 11px; text-transform: uppercase; letter-spacing: .05em; }
.ps .val { font-variant-numeric: tabular-nums; color: #fff; }
.ps input[type=range] { width: 100%; accent-color: #f0a030; }
.ps select { background: #1f242c; color: #fff; border: 1px solid #4a5260; border-radius: 4px; padding: 3px; }
`;

// The SDK's curve: a value's place along a slider, from 0 to 1, and back. Parameter info
// arrives from the audio thread as plain data, without its methods.
const toUnit = (v, p) => ((v - p.minValue) / (p.maxValue - p.minValue || 1)) ** (1.5 ** -(p.exponent || 0));
const fromUnit = (x, p) => x ** (1.5 ** (p.exponent || 0)) * (p.maxValue - p.minValue) + p.minValue;

/** @param {number} v @param {string} units */
const show = (v, units) => {
  if (units === 'Hz') return v >= 1000 ? (v / 1000).toFixed(2) + ' kHz' : Math.round(v) + ' Hz';
  if (units === 's') return v < 1 ? Math.round(v * 1000) + ' ms' : v.toFixed(2) + ' s';
  if (units === 'ct') return (v >= 0 ? '+' : '') + Math.round(v) + ' ct';
  return v.toFixed(2);
};

/** @param {import('../sdk/index.js').WebAudioModule} plugin */
export async function createElement(plugin) {
  const node = plugin.audioNode;
  const info = await node.getParameterInfo();
  const values = await node.getParameterValues(false);
  const root = document.createElement('div');
  const style = document.createElement('style');
  style.textContent = CSS;
  root.append(style);
  const panel = document.createElement('div');
  panel.className = 'ps';
  const title = document.createElement('h1');
  title.textContent = 'PolySynth';
  panel.append(title);
  for (const id of Object.keys(info)) {
    const p = info[id];
    const label = document.createElement('label');
    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = p.label || id;
    label.append(name);
    const value = values[id]?.value ?? p.defaultValue;
    if (p.type === 'choice') {
      const select = document.createElement('select');
      p.choices.forEach((c, i) => select.append(new Option(c, String(i), false, i === value)));
      select.addEventListener('change', () => node.setParameterValues({ [id]: { id, value: Number(select.value), normalized: false } }));
      label.append(select);
    } else {
      const out = document.createElement('span');
      out.className = 'val';
      out.textContent = show(value, p.units);
      const range = document.createElement('input');
      range.type = 'range';
      range.min = '0';
      range.max = '1';
      range.step = '0.001';
      range.value = String(toUnit(value, p));
      range.addEventListener('input', () => {
        const v = fromUnit(Number(range.value), p);
        out.textContent = show(v, p.units);
        node.setParameterValues({ [id]: { id, value: v, normalized: false } });
      });
      label.append(range, out);
    }
    panel.append(label);
  }
  root.append(panel);
  return root;
}
