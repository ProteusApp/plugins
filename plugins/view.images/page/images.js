// The image viewer's page. The plugin sends it a file, and it shows the picture in the
// middle of the tab, fitted, over a checkerboard. zoom.js does the zooming and moving.
//
// Messages from the plugin:
//   { type: 'config', checkerboard, pixelated }   the settings. pixelated: auto, always, never
//   { type: 'zoom', to }                          to: fit, actual, in or out
//   { type: 'pixelated' }                         turns sharp square pixels on or off
//   { type: 'failed', error }                     the plugin could not ask for the file
// Messages to the plugin:
//   { type: 'view', width, height, bytes, zoom, pixelated, vector }   after each change
//   { type: 'error', error }                                          the picture did not load

(() => {
  'use strict';

  // A picture no larger than this on its longer side counts as pixel art.
  const PIXEL_ART = 256;

  const frame = document.getElementById('frame');
  const box = document.getElementById('box');
  const note = document.getElementById('note');

  // What shows now.
  let url = null;
  let picture = null;
  let width = 0;
  let height = 0;
  let bytes = 0;
  let vector = false;
  // Sharp square pixels, as the user last chose for this picture, or null to follow the setting.
  let chosen = null;
  let config = { checkerboard: true, pixelated: 'auto' };

  function pixelated() {
    if (vector || !picture) return false;
    if (chosen !== null) return chosen;
    if (config.pixelated === 'always') return true;
    if (config.pixelated === 'never') return false;
    return Math.max(width, height) <= PIXEL_ART;
  }

  function report(state) {
    if (!picture) return;
    proteus.post({ type: 'view', width, height, bytes, zoom: state.zoom, pixelated: pixelated(), vector });
  }

  const zoomer = makeZoomer(frame, box, report);

  // A fitted picture fills the frame. A photo grows no larger than its own size, since it
  // would only blur, but pixel art grows by whole steps, so every pixel stays the same size.
  const fitRule = (scale) => {
    if (scale <= 1 || vector) return scale;
    return pixelated() ? Math.floor(scale) : 1;
  };
  zoomer.setFitRule(fitRule);

  function applyLook() {
    box.classList.toggle('checker', config.checkerboard !== false);
    box.classList.toggle('pixelated', pixelated());
  }

  function showNote(text, isError) {
    note.textContent = text;
    note.classList.toggle('error', !!isError);
    note.hidden = !text;
  }

  function fail(message) {
    showNote(message, true);
    proteus.post({ type: 'error', error: message });
  }

  const TYPES = {
    png: 'image/png',
    apng: 'image/apng',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    jfif: 'image/jpeg',
    gif: 'image/gif',
    webp: 'image/webp',
    avif: 'image/avif',
    bmp: 'image/bmp',
    ico: 'image/x-icon',
    svg: 'image/svg+xml',
  };

  function typeOf(file) {
    if (file.tag && typeof file.tag.kind === 'string') return file.tag.kind;
    const ext = /\.([^.]+)$/.exec(file.name || '');
    return (ext && TYPES[ext[1].toLowerCase()]) || 'application/octet-stream';
  }

  proteus.onFile(async (file) => {
    if (!file.bytes) {
      fail(file.error || 'The file could not be read.');
      return;
    }
    const type = typeOf(file);
    const isSvg = type === 'image/svg+xml';
    const next = URL.createObjectURL(new Blob([file.bytes], { type }));
    const img = new Image();
    img.draggable = false;
    img.alt = '';
    img.src = next;
    try {
      await img.decode();
    } catch {
      URL.revokeObjectURL(next);
      fail(isSvg ? 'This SVG did not draw. It may have a mistake in it.' : 'This picture did not load. The file may be damaged, or in a form this app cannot show.');
      return;
    }

    let size = null;
    if (isSvg) size = svgSize(new TextDecoder().decode(file.bytes));
    const w = size ? size.width : img.naturalWidth || 300;
    const h = size ? size.height : img.naturalHeight || 150;

    const same = picture !== null && w === width && h === height && isSvg === vector;
    if (picture) picture.remove();
    if (url) URL.revokeObjectURL(url);
    url = next;
    picture = img;
    width = w;
    height = h;
    bytes = file.bytes.byteLength;
    vector = isSvg;
    if (!same) chosen = null;
    box.appendChild(img);
    box.hidden = false;
    showNote('');
    applyLook();
    zoomer.setSize(w, h, same);
    report({ zoom: zoomer.zoom() });
  });

  proteus.on((message) => {
    if (!message) return;
    if (message.type === 'config') {
      config = { checkerboard: message.checkerboard !== false, pixelated: message.pixelated || 'auto' };
      applyLook();
      // Fits again when the picture is fitted, since sharp pixels fit by whole steps.
      zoomer.setFitRule(fitRule);
      report({ zoom: zoomer.zoom() });
    } else if (message.type === 'zoom') {
      if (message.to === 'fit') zoomer.fit();
      else if (message.to === 'actual') zoomer.actual();
      else if (message.to === 'in') zoomer.zoomIn();
      else if (message.to === 'out') zoomer.zoomOut();
    } else if (message.type === 'pixelated') {
      togglePixelated();
    } else if (message.type === 'failed') {
      fail(message.error || 'The file could not be read.');
    }
  });

  function togglePixelated() {
    if (!picture || vector) return;
    chosen = !pixelated();
    applyLook();
    zoomer.setFitRule(fitRule);
    report({ zoom: zoomer.zoom() });
  }

  document.addEventListener('keydown', (ev) => {
    if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
    if (ev.key === '+' || ev.key === '=') zoomer.zoomIn();
    else if (ev.key === '-' || ev.key === '_') zoomer.zoomOut();
    else if (ev.key === '0') zoomer.fit();
    else if (ev.key === '1') zoomer.actual();
    else if (ev.key === 'p' || ev.key === 'P') togglePixelated();
    else return;
    ev.preventDefault();
  });

  showNote('Loading…');
})();
