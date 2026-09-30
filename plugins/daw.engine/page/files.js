// Audio files the user gave the DAW. The page never names a file on disk: it knows each one
// by the id of the grant the user made in an open dialog. It asks the plugin for a file it
// needs, the app sends the bytes, and the page decodes them once for every context to share.
//
// Messages to the plugin:
//   { type: 'want', file }                           the page needs this file
//   { type: 'file', file, seconds, peaks }           it decoded, with 1000 peaks to draw
//   { type: 'file_failed', file, error }             it could not be read or decoded

'use strict';

const PEAKS = 1000;

class Files {
  buffers = new Map();
  pending = new Set();
  failed = new Set();
  decode = null;
  post = null;

  buffer(id) {
    return this.buffers.get(id);
  }

  want(id) {
    if (!id || this.buffers.has(id) || this.pending.has(id) || this.failed.has(id)) return;
    this.pending.add(id);
    this.post?.({ type: 'want', file: id });
  }

  /** The plugin could not send a file, such as one the user took back. */
  missing(id, error) {
    this.pending.delete(id);
    this.failed.add(id);
    this.post?.({ type: 'file_failed', file: id, error: error || 'the file is not available' });
  }

  /** Tries a file that failed again, such as after the user picked it once more. */
  retry(id) {
    this.failed.delete(id);
    this.buffers.delete(id);
    this.want(id);
  }

  receive(f) {
    const id = String(f.id);
    if (this.buffers.has(id)) return;
    if (!f.bytes) return this.missing(id, f.error);
    this.pending.add(id);
    this.failed.delete(id);
    this.decode(f.bytes)
      .then((buf) => {
        this.pending.delete(id);
        this.buffers.set(id, buf);
        this.post?.({ type: 'file', file: id, seconds: buf.duration, peaks: peaks(buf, PEAKS) });
      })
      .catch((err) => this.missing(id, `it is not an audio file the browser can read (${err?.message ?? err})`));
  }
}

/** The loudest sample in each of `count` stretches of the first channel, from 0 to 1. */
function peaks(buf, count) {
  const data = buf.getChannelData(0);
  const step = Math.max(1, Math.floor(data.length / count));
  const out = [];
  for (let i = 0; i < count; i++) {
    let peak = 0;
    const end = Math.min(data.length, (i + 1) * step);
    for (let j = i * step; j < end; j += 4) peak = Math.max(peak, Math.abs(data[j]));
    out.push(Math.round(peak * 1000) / 1000);
  }
  return out;
}

const FILES = new Files();

/** Writes rendered audio as a 16-bit PCM WAV file. */
function encodeWav(buffer) {
  const channels = buffer.numberOfChannels;
  const frames = buffer.length;
  const bytes = frames * channels * 2;
  const out = new DataView(new ArrayBuffer(44 + bytes));
  const text = (at, s) => {
    for (let i = 0; i < s.length; i++) out.setUint8(at + i, s.charCodeAt(i));
  };
  text(0, 'RIFF');
  out.setUint32(4, 36 + bytes, true);
  text(8, 'WAVE');
  text(12, 'fmt ');
  out.setUint32(16, 16, true);
  out.setUint16(20, 1, true);
  out.setUint16(22, channels, true);
  out.setUint32(24, buffer.sampleRate, true);
  out.setUint32(28, buffer.sampleRate * channels * 2, true);
  out.setUint16(32, channels * 2, true);
  out.setUint16(34, 16, true);
  text(36, 'data');
  out.setUint32(40, bytes, true);
  const data = Array.from({ length: channels }, (_, ch) => buffer.getChannelData(ch));
  let at = 44;
  for (let i = 0; i < frames; i++) {
    for (let ch = 0; ch < channels; ch++) {
      const v = Math.max(-1, Math.min(1, data[ch][i]));
      out.setInt16(at, v < 0 ? v * 0x8000 : v * 0x7fff, true);
      at += 2;
    }
  }
  return out.buffer;
}
