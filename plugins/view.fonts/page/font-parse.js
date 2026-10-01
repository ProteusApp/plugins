// Reads what a font file says about itself: its names, its sizes and the characters it has.
// It reads TrueType and OpenType fonts (.ttf, .otf), collections of them (.ttc), and WOFF
// and WOFF2 files, which hold the same tables compressed. It draws nothing. The page hands
// the file to the browser to draw the letters.
//
// A font is a list of tables, each named by four letters, such as 'name' for its names and
// 'cmap' for the characters it maps to shapes. The format is at
// https://learn.microsoft.com/typography/opentype/spec/ and WOFF at https://www.w3.org/TR/WOFF/
// and https://www.w3.org/TR/WOFF2/. Every number in a font is big-endian.
//
// FontFile.kind(buffer)              'truetype', 'opentype', 'collection', 'woff', 'woff2' or null
// FontFile.faces(buffer)             how many fonts the file holds: more than 1 for a collection
// FontFile.tables(buffer, face)      a promise of a Map from table name to its bytes, or null
//                                    when the tables cannot be read
// FontFile.describe(tables)          { names, metrics, characters } from the tables
// FontFile.single(buffer, face)      one font of a collection as a font file of its own, which
//                                    the browser can load

const FontFile = (() => {
  'use strict';

  // The most characters the glyph list keeps, so a broken table cannot fill the memory.
  const MAX_CHARACTERS = 200000;

  // WOFF2 names the common tables by number, in this order.
  const WOFF2_TAGS = [
    'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ', 'fpgm', 'glyf', 'loca',
    'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp', 'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea',
    'vmtx', 'BASE', 'GDEF', 'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL',
    'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc', 'feat', 'fmtx', 'fvar',
    'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx', 'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat',
    'Gloc', 'Feat', 'Sill',
  ];

  const tagAt = (bytes, at) => String.fromCharCode(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]);

  function kind(buffer) {
    const bytes = new Uint8Array(buffer);
    if (bytes.length < 12) return null;
    const tag = tagAt(bytes, 0);
    if (tag === '\0\x01\0\0' || tag === 'true') return 'truetype';
    if (tag === 'OTTO') return 'opentype';
    if (tag === 'ttcf') return 'collection';
    if (tag === 'wOFF') return 'woff';
    if (tag === 'wOF2') return 'woff2';
    return null;
  }

  function faces(buffer) {
    if (kind(buffer) !== 'collection') return 1;
    return new DataView(buffer).getUint32(8);
  }

  // The table list of a plain font that starts at offset, as name to { offset, length }.
  function directory(buffer, offset) {
    const view = new DataView(buffer);
    const count = view.getUint16(offset + 4);
    const out = new Map();
    for (let i = 0; i < count; i++) {
      const at = offset + 12 + i * 16;
      if (at + 16 > buffer.byteLength) break;
      const tableOffset = view.getUint32(at + 8);
      const length = view.getUint32(at + 12);
      if (tableOffset + length > buffer.byteLength) continue;
      out.set(tagAt(new Uint8Array(buffer), at), { offset: tableOffset, length });
    }
    return out;
  }

  // Where the font numbered face starts. A plain font starts at 0.
  function faceOffset(buffer, face) {
    if (kind(buffer) !== 'collection') return 0;
    const count = faces(buffer);
    const index = Math.max(0, Math.min(face || 0, count - 1));
    return new DataView(buffer).getUint32(12 + index * 4);
  }

  async function decompress(bytes, format) {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream(format));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  // True when this browser can undo the compression WOFF2 uses.
  function canReadWoff2() {
    try {
      new DecompressionStream('brotli');
      return true;
    } catch {
      return false;
    }
  }

  async function tables(buffer, face) {
    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);
    const type = kind(buffer);
    const out = new Map();

    if (type === 'truetype' || type === 'opentype' || type === 'collection') {
      for (const [tag, t] of directory(buffer, faceOffset(buffer, face))) {
        out.set(tag, bytes.subarray(t.offset, t.offset + t.length));
      }
      return out;
    }

    if (type === 'woff') {
      // Each table is compressed on its own, unless that would not make it smaller.
      const count = view.getUint16(12);
      const work = [];
      for (let i = 0; i < count; i++) {
        const at = 44 + i * 20;
        if (at + 20 > bytes.length) break;
        const tag = tagAt(bytes, at);
        const offset = view.getUint32(at + 4);
        const compressed = view.getUint32(at + 8);
        const length = view.getUint32(at + 12);
        if (offset + compressed > bytes.length) continue;
        const data = bytes.subarray(offset, offset + compressed);
        if (compressed >= length) out.set(tag, data);
        else work.push(decompress(data, 'deflate').then((raw) => out.set(tag, raw), () => {}));
      }
      await Promise.all(work);
      return out;
    }

    if (type === 'woff2') {
      if (!canReadWoff2()) return null;
      // A collection in WOFF2 has a second list after the tables, which this does not read.
      if (tagAt(bytes, 4) === 'ttcf') return null;
      const count = view.getUint16(12);
      const compressedSize = view.getUint32(20);
      let at = 48;
      // A number of up to 5 bytes, 7 bits in each, with the top bit set on all but the last.
      const base128 = () => {
        let value = 0;
        for (let i = 0; i < 5; i++) {
          const b = bytes[at++];
          value = value * 128 + (b & 0x7f);
          if (!(b & 0x80)) return value;
        }
        throw new Error('A WOFF2 length is damaged.');
      };
      const list = [];
      for (let i = 0; i < count; i++) {
        const flags = bytes[at++];
        let tag = WOFF2_TAGS[flags & 0x3f];
        if ((flags & 0x3f) === 0x3f) {
          tag = tagAt(bytes, at);
          at += 4;
        }
        const length = base128();
        const version = flags >> 6;
        // glyf and loca are changed in shape unless their version is 3. Other tables are
        // changed unless their version is 0. A changed table gives its changed length too.
        const changed = tag === 'glyf' || tag === 'loca' ? version !== 3 : version !== 0;
        const stored = changed ? base128() : length;
        list.push({ tag, stored, changed });
      }
      const raw = await decompress(bytes.subarray(at, at + compressedSize), 'brotli');
      let p = 0;
      for (const t of list) {
        // The changed tables are the shapes of the letters, which the names, sizes and
        // characters do not need.
        if (!t.changed) out.set(t.tag, raw.subarray(p, p + t.stored));
        p += t.stored;
      }
      return out;
    }
    return null;
  }

  function single(buffer, face) {
    if (kind(buffer) !== 'collection') return buffer;
    const offset = faceOffset(buffer, face);
    const list = [...directory(buffer, offset)];
    const view = new DataView(buffer);
    const pad = (n) => (n + 3) & ~3;
    let size = 12 + list.length * 16;
    for (const [, t] of list) size += pad(t.length);
    const out = new Uint8Array(size);
    const outView = new DataView(out.buffer);
    // The header is the same, with the table list of this font.
    out.set(new Uint8Array(buffer, offset, 12), 0);
    outView.setUint16(4, list.length);
    let data = 12 + list.length * 16;
    list.forEach(([tag, t], i) => {
      const at = 12 + i * 16;
      for (let k = 0; k < 4; k++) out[at + k] = tag.charCodeAt(k);
      outView.setUint32(at + 4, view.getUint32(offset + 12 + i * 16 + 4));
      outView.setUint32(at + 8, data);
      outView.setUint32(at + 12, t.length);
      out.set(new Uint8Array(buffer, t.offset, t.length), data);
      data += pad(t.length);
    });
    return out.buffer;
  }

  // Names --------------------------------------------------------------------------------

  // The name ids worth showing.
  const NAME_IDS = {
    0: 'copyright',
    1: 'family',
    2: 'style',
    4: 'full',
    5: 'version',
    8: 'maker',
    9: 'designer',
    11: 'website',
    13: 'license',
    16: 'typoFamily',
    17: 'typoStyle',
  };

  function names(table) {
    if (!table || table.length < 6) return {};
    const view = new DataView(table.buffer, table.byteOffset, table.byteLength);
    const count = view.getUint16(2);
    const strings = view.getUint16(4);
    // A name in US English for Windows wins, then any for Windows, then Unicode, then Mac.
    const rank = (platform, encoding, language) => {
      if (platform === 3 && (encoding === 1 || encoding === 10)) return language === 0x409 ? 4 : 3;
      if (platform === 0) return 2;
      if (platform === 1 && encoding === 0) return language === 0 ? 1 : 0.5;
      return 0;
    };
    const best = {};
    for (let i = 0; i < count; i++) {
      const at = 6 + i * 12;
      if (at + 12 > table.length) break;
      const platform = view.getUint16(at);
      const encoding = view.getUint16(at + 2);
      const language = view.getUint16(at + 4);
      const key = NAME_IDS[view.getUint16(at + 6)];
      const length = view.getUint16(at + 8);
      const offset = strings + view.getUint16(at + 10);
      const score = rank(platform, encoding, language);
      if (!key || score === 0 || offset + length > table.length) continue;
      if (best[key] && best[key].score >= score) continue;
      const raw = table.subarray(offset, offset + length);
      let text = '';
      if (platform === 1) {
        for (const b of raw) text += String.fromCharCode(b);
      } else {
        for (let k = 0; k + 1 < raw.length; k += 2) text += String.fromCharCode((raw[k] << 8) | raw[k + 1]);
      }
      best[key] = { score, text: text.replace(/\0/g, '').trim() };
    }
    const out = {};
    for (const key of Object.keys(best)) if (best[key].text) out[key] = best[key].text;
    return out;
  }

  // Sizes --------------------------------------------------------------------------------

  function metrics(found) {
    const read = (tag, fn) => {
      const t = found.get(tag);
      if (!t) return;
      try {
        fn(new DataView(t.buffer, t.byteOffset, t.byteLength), t.length);
      } catch {
        // A table too short for what it should hold gives nothing.
      }
    };
    const out = {};
    read('head', (v) => {
      out.unitsPerEm = v.getUint16(18);
    });
    read('maxp', (v) => {
      out.glyphs = v.getUint16(4);
    });
    read('hhea', (v) => {
      out.ascender = v.getInt16(4);
      out.descender = v.getInt16(6);
      out.lineGap = v.getInt16(8);
    });
    read('OS/2', (v, length) => {
      out.weight = v.getUint16(4);
      // Bit 7 of fsSelection says to use the typographic sizes rather than those of hhea.
      if (length >= 74 && v.getUint16(62) & 0x80) {
        out.ascender = v.getInt16(68);
        out.descender = v.getInt16(70);
        out.lineGap = v.getInt16(72);
      }
      if (v.getUint16(0) >= 2 && length >= 90) {
        out.xHeight = v.getInt16(86);
        out.capHeight = v.getInt16(88);
      }
    });
    read('post', (v) => {
      out.italicAngle = v.getInt32(4) / 65536;
      out.monospace = v.getUint32(12) !== 0;
    });
    return out;
  }

  // Characters ---------------------------------------------------------------------------

  // The characters the font has a shape for, from its 'cmap' table, in order.
  function characters(table) {
    if (!table || table.length < 4) return [];
    const view = new DataView(table.buffer, table.byteOffset, table.byteLength);
    const count = view.getUint16(2);
    // Sub-tables for all of Unicode win over those for the first 65536 characters only.
    // A symbol font's table puts its characters at U+F000 and up.
    const rank = (platform, encoding, format) => {
      if (format === 12 && ((platform === 3 && encoding === 10) || platform === 0)) return 6;
      if (format === 4 && platform === 3 && encoding === 1) return 5;
      if ((format === 4 || format === 6) && platform === 0) return 4;
      if (format === 4 && platform === 3 && encoding === 0) return 3;
      if ((format === 0 || format === 6) && platform === 1) return 1;
      return 0;
    };
    let best = null;
    for (let i = 0; i < count; i++) {
      const at = 4 + i * 8;
      if (at + 8 > table.length) break;
      const offset = view.getUint32(at + 4);
      if (offset + 2 > table.length) continue;
      const score = rank(view.getUint16(at), view.getUint16(at + 2), view.getUint16(offset));
      if (score > 0 && (!best || score > best.score)) best = { score, offset };
    }
    if (!best) return [];

    const seen = new Set();
    const add = (code) => {
      if (seen.size < MAX_CHARACTERS) seen.add(code);
    };
    try {
      const at = best.offset;
      const format = view.getUint16(at);
      if (format === 4) {
        const segments = view.getUint16(at + 6) / 2;
        const ends = at + 14;
        const starts = ends + segments * 2 + 2;
        const deltas = starts + segments * 2;
        const ranges = deltas + segments * 2;
        for (let s = 0; s < segments; s++) {
          const end = view.getUint16(ends + s * 2);
          const start = view.getUint16(starts + s * 2);
          const delta = view.getUint16(deltas + s * 2);
          const rangeAt = ranges + s * 2;
          const range = view.getUint16(rangeAt);
          for (let c = start; c <= end && c !== 0xffff; c++) {
            let glyph;
            if (range === 0) {
              glyph = (c + delta) & 0xffff;
            } else {
              const where = rangeAt + range + (c - start) * 2;
              if (where + 2 > table.length) break;
              glyph = view.getUint16(where);
              if (glyph !== 0) glyph = (glyph + delta) & 0xffff;
            }
            if (glyph !== 0) add(c);
          }
        }
      } else if (format === 12) {
        const groups = view.getUint32(at + 12);
        for (let g = 0; g < groups && seen.size < MAX_CHARACTERS; g++) {
          const p = at + 16 + g * 12;
          if (p + 12 > table.length) break;
          const start = view.getUint32(p);
          const end = Math.min(view.getUint32(p + 4), 0x10ffff);
          const glyph = view.getUint32(p + 8);
          for (let c = start; c <= end && seen.size < MAX_CHARACTERS; c++) if (glyph + (c - start) !== 0) add(c);
        }
      } else if (format === 6) {
        const first = view.getUint16(at + 6);
        const entries = view.getUint16(at + 8);
        for (let i = 0; i < entries; i++) if (view.getUint16(at + 10 + i * 2) !== 0) add(first + i);
      } else if (format === 0) {
        for (let c = 0; c < 256; c++) if (table[at + 6 + c]) add(c);
      }
    } catch {
      // A table cut short gives the characters read before the cut.
    }
    return [...seen].sort((a, b) => a - b);
  }

  function describe(found) {
    if (!found) return { names: {}, metrics: {}, characters: null };
    return { names: names(found.get('name')), metrics: metrics(found), characters: characters(found.get('cmap')) };
  }

  return { kind, faces, tables, describe, single, canReadWoff2 };
})();
