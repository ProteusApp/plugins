// Reads the size an SVG file asks for, from the width, height and viewBox of its <svg> tag.
// A browser gives an SVG with no size of its own a size of its choosing, so the page asks
// this first.
//
// svgSize(text) returns { width, height } in CSS pixels, or null when the tag says nothing
// usable. A width or height in percent says nothing, since it depends on the page around it.

function svgSize(text) {
  'use strict';

  // The pixels in one of each unit, as CSS counts them.
  const UNITS = { '': 1, px: 1, pt: 4 / 3, pc: 16, in: 96, cm: 96 / 2.54, mm: 96 / 25.4, em: 16, rem: 16, ex: 8 };

  const tag = /<svg\b[^>]*>/i.exec(String(text).slice(0, 65536));
  if (!tag) return null;

  const attr = (name) => {
    const m = new RegExp('\\s' + name + '\\s*=\\s*("([^"]*)"|\'([^\']*)\')', 'i').exec(tag[0]);
    return m ? (m[2] !== undefined ? m[2] : m[3]).trim() : null;
  };

  const length = (value) => {
    if (value === null) return null;
    const m = /^([0-9]*\.?[0-9]+(?:e[-+]?[0-9]+)?)\s*([a-z]*)$/i.exec(value);
    if (!m) return null;
    const unit = UNITS[m[2].toLowerCase()];
    const n = parseFloat(m[1]) * (unit || 0);
    return n > 0 && isFinite(n) ? n : null;
  };

  let box = null;
  const viewBox = attr('viewBox');
  if (viewBox) {
    const parts = viewBox.split(/[\s,]+/).map(Number);
    if (parts.length === 4 && parts[2] > 0 && parts[3] > 0) box = { width: parts[2], height: parts[3] };
  }

  const w = length(attr('width'));
  const h = length(attr('height'));
  if (w && h) return { width: w, height: h };
  if (box && w) return { width: w, height: (w * box.height) / box.width };
  if (box && h) return { width: (h * box.width) / box.height, height: h };
  return box;
}
