// Draws one frame of a sprite that aseprite-parse.js read, as RGBA pixels.
//
// Layers stack from the bottom of the list to the top, as in Aseprite. A group draws its
// layers on a clear sheet of its own first, then lays that sheet on the layers below with
// the group's opacity and blend. A cel with a z-index moves up or down among the layers
// beside it. Layers that are hidden, and the layers inside a hidden group, do not draw.
//
// AsepriteRender.frame(sprite, index, visible) returns a Uint8ClampedArray of
// width * height * 4 bytes. visible[i] says whether layer i shows.
// AsepriteRender.BLENDS lists the blend names by number, for the layer list.

const AsepriteRender = (() => {
  'use strict';

  const BLENDS = [
    'normal',
    'multiply',
    'screen',
    'overlay',
    'darken',
    'lighten',
    'color dodge',
    'color burn',
    'hard light',
    'soft light',
    'difference',
    'exclusion',
    'hue',
    'saturation',
    'color',
    'luminosity',
    'addition',
    'subtract',
    'divide',
  ];

  // How each blend mixes one channel, from 0 to 255, of the layers below (b) and the layer
  // on top (s). Hue, saturation, color and luminosity mix all three channels at once, and
  // draw as normal here.
  const MIX = {
    1: (b, s) => (b * s) / 255,
    2: (b, s) => 255 - ((255 - b) * (255 - s)) / 255,
    3: (b, s) => (b < 128 ? (2 * b * s) / 255 : 255 - (2 * (255 - b) * (255 - s)) / 255),
    4: (b, s) => Math.min(b, s),
    5: (b, s) => Math.max(b, s),
    6: (b, s) => (b === 0 ? 0 : s >= 255 ? 255 : Math.min(255, (b * 255) / (255 - s))),
    7: (b, s) => (b >= 255 ? 255 : s <= 0 ? 0 : 255 - Math.min(255, ((255 - b) * 255) / s)),
    8: (b, s) => (s < 128 ? (2 * s * b) / 255 : 255 - (2 * (255 - s) * (255 - b)) / 255),
    9: (b, s) => {
      const bn = b / 255;
      const sn = s / 255;
      const d = bn <= 0.25 ? ((16 * bn - 12) * bn + 4) * bn : Math.sqrt(bn);
      const r = sn <= 0.5 ? bn - (1 - 2 * sn) * bn * (1 - bn) : bn + (2 * sn - 1) * (d - bn);
      return r * 255;
    },
    10: (b, s) => Math.abs(b - s),
    11: (b, s) => b + s - (2 * b * s) / 255,
    16: (b, s) => Math.min(255, b + s),
    17: (b, s) => Math.max(0, b - s),
    18: (b, s) => (b <= 0 ? 0 : s <= 0 ? 255 : Math.min(255, (b * 255) / s)),
  };

  // Turns a cel's pixels, in the sprite's color mode, into RGBA. The result is kept on the
  // cel, so each cel is turned once.
  function celColors(sprite, cel, layer) {
    const key = layer.background ? 'rgbaBackground' : 'rgba';
    const owner = cel.source || cel;
    if (owner[key]) return owner[key];
    const count = cel.width * cel.height;
    const src = cel.pixels;
    let out;
    if (sprite.depth === 32) {
      out = src;
    } else {
      out = new Uint8Array(count * 4);
      if (sprite.depth === 16) {
        for (let i = 0; i < count; i++) {
          const v = src[i * 2];
          out[i * 4] = v;
          out[i * 4 + 1] = v;
          out[i * 4 + 2] = v;
          out[i * 4 + 3] = src[i * 2 + 1];
        }
      } else {
        const palette = sprite.palette || new Uint8Array(0);
        // The clear index is clear on every layer but the background, which has no clear parts.
        const clear = layer.background ? -1 : sprite.transparent;
        for (let i = 0; i < count; i++) {
          const index = src[i];
          if (index === clear || index * 4 + 3 >= palette.length) continue;
          out[i * 4] = palette[index * 4];
          out[i * 4 + 1] = palette[index * 4 + 1];
          out[i * 4 + 2] = palette[index * 4 + 2];
          out[i * 4 + 3] = palette[index * 4 + 3];
        }
      }
    }
    owner[key] = out;
    return out;
  }

  // Lays the pixels src, of size sw by sh, at sx, sy on the sheet dst, which is the size of
  // the sprite. Both hold RGBA without the color already scaled by alpha.
  function lay(sprite, dst, src, sw, sh, sx, sy, opacity, blend) {
    if (opacity <= 0) return;
    const width = sprite.width;
    const height = sprite.height;
    const mix = MIX[blend];
    const x0 = Math.max(0, sx);
    const y0 = Math.max(0, sy);
    const x1 = Math.min(width, sx + sw);
    const y1 = Math.min(height, sy + sh);
    for (let y = y0; y < y1; y++) {
      let si = ((y - sy) * sw + (x0 - sx)) * 4;
      let di = (y * width + x0) * 4;
      for (let x = x0; x < x1; x++, si += 4, di += 4) {
        const alpha = src[si + 3];
        if (alpha === 0) continue;
        const sa = (alpha / 255) * opacity;
        const ba = dst[di + 3] / 255;
        // Most pixels cover what is below, or have nothing below, and need no mixing.
        if (!mix && (sa >= 1 || ba === 0)) {
          dst[di] = src[si];
          dst[di + 1] = src[si + 1];
          dst[di + 2] = src[si + 2];
          dst[di + 3] = sa >= 1 ? 255 : Math.round(sa * 255);
          continue;
        }
        const outA = sa + ba * (1 - sa);
        for (let k = 0; k < 3; k++) {
          const b = dst[di + k];
          let s = src[si + k];
          // A blend works against what is below, so over clear parts the color stays as it is.
          if (mix && ba > 0) s = s + (mix(b, s) - s) * ba;
          dst[di + k] = Math.round((s * sa + b * ba * (1 - sa)) / outA);
        }
        dst[di + 3] = Math.round(outA * 255);
      }
    }
  }

  // The layers as a tree: for each layer, the layers directly inside it. -1 is the top.
  function tree(sprite) {
    if (sprite.tree) return sprite.tree;
    const children = new Map([[-1, []]]);
    const parents = [];
    sprite.layers.forEach((layer, i) => {
      // The parent is the nearest group above in the list with a smaller level.
      let parent = -1;
      for (let j = i - 1; j >= 0; j--) {
        if (sprite.layers[j].level < layer.level) {
          if (sprite.layers[j].kind === 'group') parent = j;
          break;
        }
      }
      parents[i] = parent;
      if (!children.has(parent)) children.set(parent, []);
      children.get(parent).push(i);
      if (layer.kind === 'group' && !children.has(i)) children.set(i, []);
    });
    sprite.tree = { children, parents };
    return sprite.tree;
  }

  function frame(sprite, index, visible) {
    const out = new Uint8ClampedArray(sprite.width * sprite.height * 4);
    const f = sprite.frames[index];
    if (!f) return out;
    const { children } = tree(sprite);
    const celOf = new Map();
    for (const cel of f.cels) celOf.set(cel.layer, cel);

    const shows = (i) => (visible ? visible[i] : sprite.layers[i].visible) !== false;

    function draw(group, sheet) {
      const order = (children.get(group) || []).map((i) => {
        const cel = celOf.get(i);
        const z = cel && sprite.layers[i].kind === 'image' ? cel.z : 0;
        return { i, z, at: i + z };
      });
      // A cel with a z-index moves that many layers up or down. On a tie, the smaller
      // z-index goes below.
      order.sort((a, b) => a.at - b.at || a.z - b.z);
      for (const { i } of order) {
        const layer = sprite.layers[i];
        if (!shows(i)) continue;
        if (layer.kind === 'group') {
          if (layer.opacity >= 255 && layer.blend === 0) {
            draw(i, sheet);
          } else {
            const inner = new Uint8ClampedArray(sheet.length);
            draw(i, inner);
            lay(sprite, sheet, inner, sprite.width, sprite.height, 0, 0, layer.opacity / 255, layer.blend);
          }
        } else if (layer.kind === 'image') {
          const cel = celOf.get(i);
          if (!cel) continue;
          const colors = celColors(sprite, cel, layer);
          lay(sprite, sheet, colors, cel.width, cel.height, cel.x, cel.y, (cel.opacity / 255) * (layer.opacity / 255), layer.blend);
        }
      }
    }

    draw(-1, out);
    return out;
  }

  return { frame, tree, BLENDS };
})();
