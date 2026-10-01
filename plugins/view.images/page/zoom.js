// Shows one picture in a frame and lets the user zoom and move it.
//
// The picture sits in a box. The box gets its size and place on the page directly, rather
// than through a scale, so a checkerboard behind the picture keeps the same size at every
// zoom. While the picture is smaller than the frame, it stays in the middle. While it is
// larger, it moves with a drag or the wheel, and its edges never come further in than the
// frame's edges. Ctrl and the wheel zoom around the pointer.
//
// makeZoomer(frame, box, onChange) returns:
//   setSize(width, height, keep)  a new picture. With keep, a picture of the same size keeps
//                                 its zoom and place, which suits reading a file again.
//   fit()  actual()  zoomIn()  zoomOut()
//   setFitRule(fn)                fn(scale) turns the scale that would fill the frame into
//                                 the scale to use, such as no larger than 1
//   zoom()                        the zoom now, where 1 is one screen pixel for each pixel
// onChange({ zoom, fitting }) runs after each change, at most once a frame.

function makeZoomer(frame, box, onChange) {
  'use strict';

  // The steps the buttons and keys go through.
  const STEPS = [
    0.02, 0.05, 0.1, 0.125, 0.25, 1 / 3, 0.5, 2 / 3, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64,
  ];
  const MIN = 0.01;
  const MAX = 64;
  // The most pixels the box may be across, so a huge zoom on a large picture stays drawable.
  const MAX_SIDE = 60000;
  // The space left around a fitted picture.
  const MARGIN = 16;

  let width = 0;
  let height = 0;
  let zoom = 1;
  let x = 0;
  let y = 0;
  let fitting = true;
  let fitRule = (scale) => scale;
  let pending = false;

  const frameSize = () => ({ w: frame.clientWidth, h: frame.clientHeight });

  function limit(z) {
    const side = Math.max(width, height, 1);
    return Math.min(Math.max(z, MIN), MAX, MAX_SIDE / side);
  }

  // Keeps a small picture in the middle, and a large one covering the frame.
  function clamp() {
    const f = frameSize();
    const w = width * zoom;
    const h = height * zoom;
    x = w <= f.w ? (f.w - w) / 2 : Math.min(0, Math.max(f.w - w, x));
    y = h <= f.h ? (f.h - h) / 2 : Math.min(0, Math.max(f.h - h, y));
  }

  function changed() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      onChange({ zoom, fitting });
    });
  }

  function layout() {
    clamp();
    box.style.left = Math.round(x) + 'px';
    box.style.top = Math.round(y) + 'px';
    box.style.width = Math.max(1, Math.round(width * zoom)) + 'px';
    box.style.height = Math.max(1, Math.round(height * zoom)) + 'px';
    changed();
  }

  // Zooms to z, keeping the point px, py of the frame over the same spot of the picture.
  function zoomAt(z, px, py) {
    const next = limit(z);
    if (!width || !height) return;
    x = px - (px - x) * (next / zoom);
    y = py - (py - y) * (next / zoom);
    zoom = next;
    fitting = false;
    layout();
  }

  function zoomCentered(z) {
    const f = frameSize();
    zoomAt(z, f.w / 2, f.h / 2);
  }

  function fit() {
    if (!width || !height) return;
    const f = frameSize();
    const room = Math.min((f.w - MARGIN * 2) / width, (f.h - MARGIN * 2) / height);
    zoom = limit(fitRule(Math.max(room, MIN)));
    fitting = true;
    layout();
  }

  function step(dir) {
    const next = dir > 0 ? STEPS.find((s) => s > zoom * 1.001) : [...STEPS].reverse().find((s) => s < zoom / 1.001);
    zoomCentered(next || (dir > 0 ? MAX : MIN));
  }

  // Ctrl and the wheel zoom. The wheel alone moves the picture, and Shift moves it sideways.
  frame.addEventListener(
    'wheel',
    (ev) => {
      ev.preventDefault();
      const r = frame.getBoundingClientRect();
      if (ev.ctrlKey || ev.metaKey) {
        const lines = ev.deltaMode === 1 ? 30 : 1;
        zoomAt(zoom * Math.exp(-ev.deltaY * lines * 0.0015), ev.clientX - r.left, ev.clientY - r.top);
        return;
      }
      const dx = ev.shiftKey && !ev.deltaX ? ev.deltaY : ev.deltaX;
      const dy = ev.shiftKey && !ev.deltaX ? 0 : ev.deltaY;
      x -= dx;
      y -= dy;
      layout();
    },
    { passive: false },
  );

  // A drag with the left or the middle button moves the picture.
  let drag = null;
  frame.addEventListener('pointerdown', (ev) => {
    if (ev.button !== 0 && ev.button !== 1) return;
    ev.preventDefault();
    // Takes the keys, which the page's own shortcuts listen for.
    frame.focus();
    drag = { id: ev.pointerId, sx: ev.clientX, sy: ev.clientY, x, y };
    frame.setPointerCapture(ev.pointerId);
    frame.classList.add('dragging');
  });
  frame.addEventListener('pointermove', (ev) => {
    if (!drag || drag.id !== ev.pointerId) return;
    x = drag.x + ev.clientX - drag.sx;
    y = drag.y + ev.clientY - drag.sy;
    layout();
  });
  const endDrag = (ev) => {
    if (!drag || drag.id !== ev.pointerId) return;
    drag = null;
    frame.classList.remove('dragging');
  };
  frame.addEventListener('pointerup', endDrag);
  frame.addEventListener('pointercancel', endDrag);

  // A fitted picture fits again when the frame changes size.
  new ResizeObserver(() => (fitting ? fit() : layout())).observe(frame);

  return {
    setSize(w, h, keep) {
      const same = keep && w === width && h === height;
      width = w;
      height = h;
      if (same && !fitting) layout();
      else fit();
    },
    setFitRule(fn) {
      fitRule = fn;
      if (fitting) fit();
    },
    fit,
    actual: () => zoomCentered(1),
    zoomIn: () => step(1),
    zoomOut: () => step(-1),
    zoom: () => zoom,
  };
}
