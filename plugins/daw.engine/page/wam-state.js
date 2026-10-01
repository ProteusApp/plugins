// A Web Audio Module's state as text a song keeps. getState may return any value a message
// can carry: it travels as JSON, where bytes such as an ArrayBuffer or a Float32Array go as
// base64. Both the engine's page and a module's editor load this script.

'use strict';

const TYPED = ['Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array', 'Int32Array',
  'Uint32Array', 'Float32Array', 'Float64Array', 'BigInt64Array', 'BigUint64Array'];

function toBase64(bytes) {
  let text = '';
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(text);
}

function fromBase64(text) {
  const raw = atob(text);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

/** A module's state as text. Undefined when it keeps none. */
function encodeWamState(value) {
  if (value === undefined) return undefined;
  return JSON.stringify(value, (_key, v) => {
    if (v instanceof ArrayBuffer) return { $bytes: toBase64(new Uint8Array(v)), $type: 'ArrayBuffer' };
    if (ArrayBuffer.isView(v)) {
      const type = TYPED.includes(v.constructor.name) ? v.constructor.name : 'Uint8Array';
      return { $bytes: toBase64(new Uint8Array(v.buffer, v.byteOffset, v.byteLength)), $type: type };
    }
    return v;
  });
}

/** The value `encodeWamState` wrote. */
function decodeWamState(text) {
  return JSON.parse(text, (_key, v) => {
    if (v && typeof v === 'object' && typeof v.$bytes === 'string' && typeof v.$type === 'string') {
      const bytes = fromBase64(v.$bytes);
      if (v.$type === 'ArrayBuffer') return bytes.buffer;
      return TYPED.includes(v.$type) ? new globalThis[v.$type](bytes.buffer) : bytes;
    }
    return v;
  });
}
