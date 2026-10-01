// The Aseprite viewer's page. The plugin sends it a file. aseprite-parse.js reads it,
// aseprite-render.js draws each frame, and this shows the frames on a canvas with sharp
// square pixels. Under the picture is a timeline to play the frames, step through them and
// pick a tag. At the side is the layer list, where each layer can be hidden or shown.
//
// Messages from the plugin:
//   { type: 'config', checkerboard, autoplay }   the settings
//   { type: 'zoom', to }                         to: fit, actual, in or out
//   { type: 'play' }                             plays or pauses
//   { type: 'step', by }                         moves by a number of frames, and pauses
//   { type: 'failed', error }                    the plugin could not ask for the file
// Messages to the plugin:
//   { type: 'view', width, height, frames, depth, bytes, zoom }   after each change
//   { type: 'error', error }                                      the file did not load

(() => {
  'use strict';

  // Rendered frames are kept up to this many bytes, so playing does not draw them again.
  const CACHE_BYTES = 256 * 1024 * 1024;

  const ICONS = {
    play: '<svg viewBox="0 0 16 16"><path d="M4 2.5v11l9-5.5z"/></svg>',
    pause: '<svg viewBox="0 0 16 16"><path d="M4 2.5h3v11H4zM9 2.5h3v11H9z"/></svg>',
    prev: '<svg viewBox="0 0 16 16"><path d="M3 2.5h2v11H3zM14 2.5v11L6 8z"/></svg>',
    next: '<svg viewBox="0 0 16 16"><path d="M11 2.5h2v11h-2zM2 2.5v11L10 8z"/></svg>',
  };

  const $ = (id) => document.getElementById(id);
  const frame = $('frame');
  const box = $('box');
  const canvas = $('sprite');
  const context = canvas.getContext('2d');
  const note = $('note');
  const timeline = $('timeline');
  const playButton = $('play');
  const scrub = $('scrub');
  const frameLabel = $('frame-label');
  const tagPicker = $('tag');
  const layerList = $('layers');
  const sideNote = $('side-note');

  $('prev').innerHTML = ICONS.prev;
  $('next').innerHTML = ICONS.next;

  let sprite = null;
  let bytes = 0;
  let visible = [];
  let current = 0;
  let order = [0];
  let position = 0;
  let tagIndex = -1;
  let playing = false;
  let timer = 0;
  let cache = new Map();
  let config = { checkerboard: true, autoplay: true };

  const zoomer = makeZoomer(frame, box, report);
  // Sprites grow by whole steps, so every pixel stays the same size.
  zoomer.setFitRule((scale) => (scale > 1 ? Math.floor(scale) : scale));

  function report(state) {
    if (!sprite) return;
    proteus.post({
      type: 'view',
      width: sprite.width,
      height: sprite.height,
      frames: sprite.frames.length,
      depth: sprite.depth,
      bytes,
      zoom: state.zoom,
    });
  }

  function showNote(text, isError) {
    note.textContent = text;
    note.classList.toggle('error', !!isError);
    note.hidden = !text;
  }

  function fail(message) {
    stop();
    showNote(message, true);
    proteus.post({ type: 'error', error: message });
  }

  // Draws a frame, from the kept ones when it was drawn before.
  function draw(index) {
    current = index;
    let image = cache.get(index);
    if (!image) {
      image = new ImageData(AsepriteRender.frame(sprite, index, visible), sprite.width, sprite.height);
      if ((cache.size + 1) * image.data.length <= CACHE_BYTES) cache.set(index, image);
    }
    context.putImageData(image, 0, 0);
    scrub.value = String(index);
    const tag = tagIndex >= 0 ? sprite.tags[tagIndex] : null;
    frameLabel.textContent =
      'Frame ' + (index + 1) + ' of ' + sprite.frames.length + ' · ' + sprite.frames[index].duration + ' ms' + (tag ? ' · ' + tag.name : '');
  }

  function stop() {
    clearTimeout(timer);
    timer = 0;
  }

  function tick() {
    position = (position + 1) % order.length;
    draw(order[position]);
    timer = setTimeout(tick, sprite.frames[current].duration);
  }

  function setPlaying(on) {
    playing = !!on && !!sprite && order.length > 1;
    stop();
    playButton.innerHTML = playing ? ICONS.pause : ICONS.play;
    playButton.title = playing ? 'Pause (Space)' : 'Play (Space)';
    if (playing) timer = setTimeout(tick, sprite.frames[current].duration);
  }

  // Shows a frame and pauses, from the scrubber, the step buttons or the arrow keys.
  function goTo(index) {
    if (!sprite) return;
    const count = sprite.frames.length;
    const next = ((index % count) + count) % count;
    setPlaying(false);
    const at = order.indexOf(next);
    if (at >= 0) position = at;
    draw(next);
  }

  function step(by) {
    if (!sprite) return;
    const at = order.indexOf(current);
    if (at >= 0 && order.length > 1) goTo(order[(at + by + order.length) % order.length]);
    else goTo(current + by);
  }

  function pickTag(index) {
    tagIndex = index;
    order = AsepritePlay.order(sprite.frames.length, index >= 0 ? sprite.tags[index] : null);
    position = 0;
    draw(order[0]);
    if (playing) setPlaying(true);
  }

  // A layer shows when it and every group around it shows.
  function showsInList(i) {
    const { parents } = AsepriteRender.tree(sprite);
    for (let j = parents[i]; j >= 0; j = parents[j]) if (!visible[j]) return false;
    return true;
  }

  function drawLayers() {
    layerList.textContent = '';
    for (let i = sprite.layers.length - 1; i >= 0; i--) {
      const layer = sprite.layers[i];
      const row = document.createElement('li');
      row.className = 'layer ' + layer.kind;
      row.style.paddingLeft = 6 + layer.level * 14 + 'px';
      row.classList.toggle('off', !visible[i] || !showsInList(i));

      const check = document.createElement('input');
      check.type = 'checkbox';
      check.checked = visible[i];
      check.title = visible[i] ? 'Hide this layer' : 'Show this layer';
      check.disabled = layer.kind === 'tilemap';
      check.addEventListener('change', () => {
        visible[i] = check.checked;
        cache = new Map();
        drawLayers();
        draw(current);
      });

      const name = document.createElement('span');
      name.className = 'name';
      name.textContent = layer.name || 'Layer ' + (i + 1);
      name.title = name.textContent;

      const facts = [];
      if (layer.kind === 'group') facts.push('group');
      if (layer.kind === 'tilemap') facts.push('tilemap, not drawn');
      if (layer.reference) facts.push('reference');
      if (layer.blend) facts.push(AsepriteRender.BLENDS[layer.blend] || 'blend ' + layer.blend);
      if (layer.opacity < 255) facts.push(Math.round((layer.opacity / 255) * 100) + '%');
      const detail = document.createElement('span');
      detail.className = 'detail';
      detail.textContent = facts.join(' · ');

      const label = document.createElement('label');
      label.append(check, name, detail);
      row.append(label);
      layerList.append(row);
    }
    const notes = [];
    if (sprite.tilemaps > 0) notes.push('Tilemap layers are not drawn.');
    if (sprite.layers.some((l) => l.blend >= 12 && l.blend <= 15)) notes.push('Hue, saturation, color and luminosity layers draw as normal.');
    sideNote.textContent = notes.join(' ');
    sideNote.hidden = notes.length === 0;
  }

  function drawTags() {
    tagPicker.textContent = '';
    const all = document.createElement('option');
    all.value = '-1';
    all.textContent = 'All frames';
    tagPicker.append(all);
    sprite.tags.forEach((tag, i) => {
      const option = document.createElement('option');
      option.value = String(i);
      const way = { reverse: ' ←', pingpong: ' ↔', 'pingpong-reverse': ' ↔' }[tag.direction] || '';
      option.textContent = tag.name + ' (' + (tag.from + 1) + '–' + (tag.to + 1) + ')' + way;
      tagPicker.append(option);
    });
    tagPicker.value = String(tagIndex);
    tagPicker.hidden = sprite.tags.length === 0;
  }

  proteus.onFile(async (file) => {
    if (!file.bytes) {
      fail(file.error || 'The file could not be read.');
      return;
    }
    let next;
    try {
      next = await AsepriteFile.parse(file.bytes);
    } catch (err) {
      fail(err && err.message ? err.message : String(err));
      return;
    }
    if (next.frames.length === 0 || next.width === 0 || next.height === 0) {
      fail('This sprite has nothing to draw.');
      return;
    }

    // Reading the same sprite again keeps the frame, the tag and which layers show.
    const same =
      sprite !== null &&
      next.width === sprite.width &&
      next.height === sprite.height &&
      next.layers.length === sprite.layers.length;
    const wasPlaying = playing;
    stop();
    sprite = next;
    bytes = file.bytes.byteLength;
    cache = new Map();
    if (!same) {
      visible = sprite.layers.map((l) => l.visible && !l.reference && l.kind !== 'tilemap');
      tagIndex = -1;
      current = 0;
    } else {
      tagIndex = Math.min(tagIndex, sprite.tags.length - 1);
      current = Math.min(current, sprite.frames.length - 1);
    }

    canvas.width = sprite.width;
    canvas.height = sprite.height;
    scrub.max = String(sprite.frames.length - 1);
    timeline.hidden = sprite.frames.length < 2;
    drawTags();
    drawLayers();
    order = AsepritePlay.order(sprite.frames.length, tagIndex >= 0 ? sprite.tags[tagIndex] : null);
    position = Math.max(0, order.indexOf(current));
    draw(current);

    box.hidden = false;
    showNote('');
    zoomer.setSize(sprite.width * sprite.pixelRatio[0], sprite.height * sprite.pixelRatio[1], same);
    setPlaying(same ? wasPlaying : config.autoplay);
    report({ zoom: zoomer.zoom() });
  });

  playButton.addEventListener('click', () => setPlaying(!playing));
  $('prev').addEventListener('click', () => step(-1));
  $('next').addEventListener('click', () => step(1));
  scrub.addEventListener('input', () => goTo(Number(scrub.value)));
  tagPicker.addEventListener('change', () => pickTag(Number(tagPicker.value)));

  proteus.on((message) => {
    if (!message) return;
    if (message.type === 'config') {
      config = { checkerboard: message.checkerboard !== false, autoplay: message.autoplay !== false };
      box.classList.toggle('checker', config.checkerboard);
    } else if (message.type === 'zoom') {
      if (message.to === 'fit') zoomer.fit();
      else if (message.to === 'actual') zoomer.actual();
      else if (message.to === 'in') zoomer.zoomIn();
      else if (message.to === 'out') zoomer.zoomOut();
    } else if (message.type === 'play') {
      setPlaying(!playing);
    } else if (message.type === 'step') {
      step(Number(message.by) || 1);
    } else if (message.type === 'failed') {
      fail(message.error || 'The file could not be read.');
    }
  });

  document.addEventListener('keydown', (ev) => {
    if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
    if (ev.target instanceof HTMLInputElement && ev.target.type !== 'range' && ev.target.type !== 'checkbox') return;
    if (ev.target instanceof HTMLSelectElement) return;
    if (ev.key === '+' || ev.key === '=') zoomer.zoomIn();
    else if (ev.key === '-' || ev.key === '_') zoomer.zoomOut();
    else if (ev.key === '0') zoomer.fit();
    else if (ev.key === '1') zoomer.actual();
    else if (ev.key === ' ') setPlaying(!playing);
    else if (ev.key === 'ArrowLeft' || ev.key === ',') step(-1);
    else if (ev.key === 'ArrowRight' || ev.key === '.') step(1);
    else return;
    ev.preventDefault();
  });

  playButton.innerHTML = ICONS.play;
  showNote('Loading…');
})();
