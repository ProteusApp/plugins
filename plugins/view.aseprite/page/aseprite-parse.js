// Reads an Aseprite file (.aseprite or .ase) into plain data: the sprite's size and color
// mode, its layers, its frames with their cels, its palette and its tags. It draws nothing.
// aseprite-render.js turns a frame into pixels.
//
// The file format is at https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
// Every number in the file is little-endian.
//
// AsepriteFile.parse(arrayBuffer) returns a promise of:
//   width, height        the sprite's size in pixels
//   depth                bits for each pixel: 32 (RGBA), 16 (grayscale) or 8 (indexed)
//   transparent          the palette index that is clear in an indexed sprite
//   pixelRatio           [w, h], the shape of one pixel, usually [1, 1]
//   layers               { name, kind, level, visible, background, reference, blend, opacity }
//                        in the file's order, which is bottom to top. kind is image, group
//                        or tilemap. level is how deep in groups the layer sits.
//   frames               { duration, cels } where duration is in milliseconds
//   cels                 { layer, x, y, opacity, z, width, height, pixels } with pixels raw,
//                        in the sprite's color mode. A linked cel shares its pixels.
//   palette              a Uint8Array of RGBA, four bytes for each color
//   tags                 { name, from, to, direction, repeat, color }. direction is forward,
//                        reverse, pingpong or pingpong-reverse.
//   tilemaps             how many cels belong to tilemap layers, which are not read

const AsepriteFile = (() => {
  'use strict';

  const DIRECTIONS = ['forward', 'reverse', 'pingpong', 'pingpong-reverse'];
  const KINDS = ['image', 'group', 'tilemap'];

  // Chunk types.
  const OLD_PALETTE = 0x0004;
  const OLD_PALETTE_64 = 0x0011;
  const LAYER = 0x2004;
  const CEL = 0x2005;
  const TAGS = 0x2018;
  const PALETTE = 0x2019;

  // Undoes zlib compression, as the cels use it. The browser's 'deflate' reads zlib data.
  async function inflate(bytes) {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  async function parse(buffer) {
    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);
    const size = buffer.byteLength;
    const u8 = (at) => bytes[at];
    const u16 = (at) => view.getUint16(at, true);
    const s16 = (at) => view.getInt16(at, true);
    const u32 = (at) => view.getUint32(at, true);
    const utf8 = new TextDecoder();
    // A string is its length in bytes, then its UTF-8 bytes.
    const string = (at) => {
      const n = u16(at);
      return { text: utf8.decode(bytes.subarray(at + 2, at + 2 + n)), end: at + 2 + n };
    };

    if (size < 128 || u16(4) !== 0xa5e0) throw new Error('This is not an Aseprite file.');

    const frameCount = u16(6);
    const sprite = {
      width: u16(8),
      height: u16(10),
      depth: u16(12),
      transparent: u8(28),
      pixelRatio: [u8(34) || 1, u8(35) || 1],
      layers: [],
      frames: [],
      palette: null,
      tags: [],
      tilemaps: 0,
    };
    const flags = u32(14);
    // Bit 1: the layers' opacity is set. Bit 2: groups have an opacity and a blend of their
    // own.
    const layerOpacity = (flags & 1) !== 0;
    const groupBlend = (flags & 2) !== 0;
    if (![8, 16, 32].includes(sprite.depth)) throw new Error('This sprite has a color mode this viewer does not know: ' + sprite.depth + ' bits.');
    const bpp = sprite.depth / 8;

    // Old palettes count only when the file has no new one.
    let oldPalette = null;
    const inflating = [];

    let at = 128;
    for (let f = 0; f < frameCount; f++) {
      if (at + 16 > size) throw new Error('The file ends in the middle of frame ' + (f + 1) + '.');
      const frameSize = u32(at);
      if (u16(at + 4) !== 0xf1fa || frameSize < 16) throw new Error('Frame ' + (f + 1) + ' is damaged.');
      const frameEnd = Math.min(size, at + frameSize);
      const oldCount = u16(at + 6);
      const newCount = u32(at + 12);
      const chunkCount = newCount || oldCount;
      const frame = { duration: u16(at + 8) || 100, cels: [] };
      sprite.frames.push(frame);

      let p = at + 16;
      for (let c = 0; c < chunkCount && p + 6 <= frameEnd; c++) {
        const chunkSize = u32(p);
        const type = u16(p + 4);
        const body = p + 6;
        const end = p + chunkSize;
        if (chunkSize < 6 || end > frameEnd) break;

        if (type === LAYER) {
          const layerFlags = u16(body);
          const kind = KINDS[u16(body + 2)] || 'image';
          const name = string(body + 16);
          const isGroup = kind === 'group';
          const layer = {
            name: name.text,
            kind,
            level: u16(body + 4),
            visible: (layerFlags & 1) !== 0,
            background: (layerFlags & 8) !== 0,
            reference: (layerFlags & 64) !== 0,
            blend: isGroup && !groupBlend ? 0 : u16(body + 10),
            opacity: (isGroup && !groupBlend) || !layerOpacity ? 255 : u8(body + 12),
          };
          // After the name, a tilemap layer names its tileset, and a layer may have an id.
          // Neither is needed to draw.
          sprite.layers.push(layer);
        } else if (type === CEL) {
          const cel = {
            layer: u16(body),
            x: s16(body + 2),
            y: s16(body + 4),
            opacity: u8(body + 6),
            z: s16(body + 9),
            width: 0,
            height: 0,
            pixels: null,
            link: -1,
          };
          const celType = u16(body + 7);
          const data = body + 16;
          if (celType === 1) {
            cel.link = u16(data);
          } else if (celType === 0 || celType === 2) {
            cel.width = u16(data);
            cel.height = u16(data + 2);
            const length = cel.width * cel.height * bpp;
            if (celType === 0) {
              cel.pixels = fit(bytes.subarray(data + 4, end), length);
            } else {
              inflating.push(
                inflate(bytes.subarray(data + 4, end)).then(
                  (raw) => (cel.pixels = fit(raw, length)),
                  () => (cel.pixels = new Uint8Array(length)),
                ),
              );
            }
          } else {
            // A tilemap cel holds tile numbers rather than pixels.
            sprite.tilemaps++;
            p = end;
            continue;
          }
          frame.cels.push(cel);
        } else if (type === PALETTE) {
          const count = u32(body);
          const first = u32(body + 4);
          const last = u32(body + 8);
          const palette = new Uint8Array(Math.max(count, last + 1, sprite.palette ? sprite.palette.length / 4 : 0) * 4);
          if (sprite.palette) palette.set(sprite.palette.subarray(0, palette.length));
          let q = body + 20;
          for (let i = first; i <= last && q + 6 <= end; i++) {
            const entryFlags = u16(q);
            palette.set(bytes.subarray(q + 2, q + 6), i * 4);
            q += 6;
            if (entryFlags & 1) q = string(q).end;
          }
          sprite.palette = palette;
        } else if (type === OLD_PALETTE || type === OLD_PALETTE_64) {
          // Packets of colors, each after a number of entries to skip. 0x0011 holds each
          // channel from 0 to 63.
          const scale = type === OLD_PALETTE_64 ? 255 / 63 : 1;
          const palette = new Uint8Array(256 * 4);
          if (oldPalette) palette.set(oldPalette);
          let index = 0;
          let q = body + 2;
          const packets = u16(body);
          for (let k = 0; k < packets && q + 2 <= end; k++) {
            index += u8(q);
            const colors = u8(q + 1) || 256;
            q += 2;
            for (let i = 0; i < colors && q + 3 <= end && index < 256; i++, index++, q += 3) {
              palette[index * 4] = Math.round(u8(q) * scale);
              palette[index * 4 + 1] = Math.round(u8(q + 1) * scale);
              palette[index * 4 + 2] = Math.round(u8(q + 2) * scale);
              palette[index * 4 + 3] = 255;
            }
          }
          oldPalette = palette;
        } else if (type === TAGS) {
          const count = u16(body);
          let q = body + 10;
          for (let k = 0; k < count && q + 17 <= end; k++) {
            const name = string(q + 17);
            sprite.tags.push({
              name: name.text,
              from: u16(q),
              to: u16(q + 2),
              direction: DIRECTIONS[u8(q + 4)] || 'forward',
              repeat: u16(q + 5),
              color: '#' + [u8(q + 13), u8(q + 14), u8(q + 15)].map((n) => n.toString(16).padStart(2, '0')).join(''),
            });
            q = name.end;
          }
        }
        // Every other chunk, such as slices, user data and color profiles, is not needed to
        // draw the sprite.
        p = end;
      }
      at += frameSize;
    }

    await Promise.all(inflating);
    if (!sprite.palette) sprite.palette = oldPalette;

    // A linked cel shows the pixels of the cel on the same layer in another frame.
    for (const frame of sprite.frames) {
      for (const cel of frame.cels) {
        if (cel.link < 0) continue;
        const target = sprite.frames[cel.link];
        const source = target && target.cels.find((other) => other.layer === cel.layer && other.link < 0);
        if (source) {
          cel.x = source.x;
          cel.y = source.y;
          cel.width = source.width;
          cel.height = source.height;
          cel.pixels = source.pixels;
          cel.source = source;
        }
      }
      frame.cels = frame.cels.filter((cel) => cel.pixels);
    }
    for (const tag of sprite.tags) {
      tag.from = Math.min(tag.from, sprite.frames.length - 1);
      tag.to = Math.max(tag.from, Math.min(tag.to, sprite.frames.length - 1));
    }
    return sprite;
  }

  // Makes the pixels exactly as long as the cel needs, so damaged data draws as clear.
  function fit(raw, length) {
    if (raw.length === length) return raw;
    const out = new Uint8Array(length);
    out.set(raw.subarray(0, length));
    return out;
  }

  return { parse };
})();
