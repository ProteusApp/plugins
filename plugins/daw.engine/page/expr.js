// A tiny expression language for device patches. A patch field such as `'$cutoff * 2'` or
// `'freq * semis($tune)'` compiles once into a function, and the engine calls it again
// whenever a parameter moves. Nothing here can reach outside the numbers it is given.
//
//   expr   := term (('+' | '-') term)*
//   term   := unary (('*' | '/') unary)*
//   unary  := '-' unary | power
//   power  := atom ('^' unary)?
//   atom   := number | '$' name | name | name '(' expr (',' expr)* ')' | '(' expr ')'
//
// `$name` reads a device parameter. The bare names are the note being played: `freq` in
// hertz, `key` as a MIDI note number and `vel` from 0 to 1. `bpm` is the song's tempo.
//
// The page's scripts load in order, expr.js, patch.js, mixer.js, engine.js and main.js, and
// share their top-level names.

'use strict';

const FUNCTIONS = {
  min: Math.min,
  max: Math.max,
  pow: Math.pow,
  exp: Math.exp,
  log: Math.log,
  abs: Math.abs,
  floor: Math.floor,
  sqrt: Math.sqrt,
  clamp: (x, lo, hi) => Math.min(Math.max(x, lo), hi),
  /** A frequency ratio from semitones, so `semis(12)` is 2. */
  semis: (x) => Math.pow(2, x / 12),
  /** A gain from decibels, so `db(-6)` is about 0.5. */
  db: (x) => Math.pow(10, x / 20),
};

const NOTE_NAMES = new Set(['freq', 'key', 'vel', 'bpm']);

/** A parameter's value as a number. Yes/no values count as 1 and 0. */
function paramNumber(params, name) {
  const v = params[name];
  if (typeof v === 'number') return v;
  if (typeof v === 'boolean') return v ? 1 : 0;
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

const cache = new Map();

/** Compiles an expression. Throws with a readable message on a mistake. */
function compile(source) {
  const hit = cache.get(source);
  if (hit) return hit;
  let pos = 0;
  let live = false;
  const text = source;

  const skip = () => {
    while (pos < text.length && /\s/.test(text[pos])) pos++;
  };
  const fail = (msg) => {
    throw new Error(`${msg} in "${source}" at ${pos + 1}`);
  };
  const peek = () => {
    skip();
    return text[pos];
  };
  const name = () => {
    const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(pos));
    if (!m) fail('expected a name');
    pos += m[0].length;
    return m[0];
  };

  const atom = () => {
    const c = peek();
    if (c === '(') {
      pos++;
      const inner = expr();
      if (peek() !== ')') fail('expected )');
      pos++;
      return inner;
    }
    if (c === '$') {
      pos++;
      const key = name();
      live = true;
      return (s) => paramNumber(s.params, key);
    }
    const num = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(text.slice(pos));
    if (num) {
      pos += num[0].length;
      const v = Number(num[0]);
      return () => v;
    }
    if (c && /[A-Za-z_]/.test(c)) {
      const id = name();
      if (peek() === '(') {
        const f = FUNCTIONS[id];
        if (!f) fail(`unknown function ${id}`);
        pos++;
        const args = [expr()];
        while (peek() === ',') {
          pos++;
          args.push(expr());
        }
        if (peek() !== ')') fail('expected )');
        pos++;
        return (s) => f(...args.map((a) => a(s)));
      }
      if (id === 'pi') return () => Math.PI;
      if (!NOTE_NAMES.has(id)) fail(`unknown name ${id}`);
      // The tempo can change while a patch runs, the note cannot.
      if (id === 'bpm') live = true;
      return (s) => s[id];
    }
    return fail('expected a value');
  };

  const power = () => {
    const base = atom();
    if (peek() === '^') {
      pos++;
      const exp = unary();
      return (s) => Math.pow(base(s), exp(s));
    }
    return base;
  };

  const unary = () => {
    if (peek() === '-') {
      pos++;
      const inner = unary();
      return (s) => -inner(s);
    }
    return power();
  };

  const term = () => {
    let left = unary();
    for (;;) {
      const op = peek();
      if (op !== '*' && op !== '/') return left;
      pos++;
      const a = left;
      const b = unary();
      left = op === '*' ? (s) => a(s) * b(s) : (s) => a(s) / b(s);
    }
  };

  function expr() {
    let left = term();
    for (;;) {
      const op = peek();
      if (op !== '+' && op !== '-') return left;
      pos++;
      const a = left;
      const b = term();
      left = op === '+' ? (s) => a(s) + b(s) : (s) => a(s) - b(s);
    }
  }

  const fn = expr();
  if (peek() !== undefined) fail('unexpected text');
  const out = { fn, live };
  cache.set(source, out);
  return out;
}

/** A patch field as a function: a number stays fixed, a string compiles. */
function field(value, fallback) {
  if (typeof value === 'number') return { fn: () => value, live: false };
  if (typeof value === 'boolean') return { fn: () => (value ? 1 : 0), live: false };
  if (typeof value === 'string' && value.trim() !== '') return compile(value);
  return { fn: () => fallback, live: false };
}

/** A text field, such as a wave shape. `'$wave'` reads the parameter named wave. */
function textField(value, params, fallback) {
  if (typeof value !== 'string') return fallback;
  if (value.startsWith('$')) {
    const v = params[value.slice(1)];
    return v === undefined || v === null ? fallback : String(v);
  }
  return value;
}

/** A yes/no field. `'$loop'` reads the parameter named loop. */
function flagField(value, params) {
  if (typeof value === 'string' && value.startsWith('$')) return paramNumber(params, value.slice(1)) !== 0;
  return value === true || value === 1;
}
