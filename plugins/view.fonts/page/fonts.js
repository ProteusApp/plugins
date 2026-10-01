// The font viewer's page. The plugin sends it a font file. The browser loads the font, and
// font-parse.js reads its names, sizes and characters. The page shows the names, a sample
// to type in, the sample at many sizes, the alphabet and digits, and every character the
// font has.
//
// Messages from the plugin:
//   { type: 'config', sample }    the sample text from the settings
//   { type: 'failed', error }     the plugin could not ask for the file
// Messages to the plugin:
//   { type: 'view', family, style, format, glyphs, characters, faces, bytes }   once it loads
//   { type: 'error', error }                                                     it did not load

(() => {
  'use strict';

  const SIZES = [10, 12, 14, 16, 20, 24, 32, 40, 48, 64, 80, 96];
  // The glyph list adds this many characters at a time, so a large font opens quickly.
  const PAGE = 1500;
  const FORMATS = {
    truetype: 'TrueType',
    opentype: 'OpenType',
    collection: 'TrueType collection',
    woff: 'WOFF',
    woff2: 'WOFF2',
  };
  const LINES = [
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    'abcdefghijklmnopqrstuvwxyz',
    '0123456789',
    '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~',
  ];

  const $ = (id) => document.getElementById(id);
  const root = $('font');
  const note = $('note');
  const facePicker = $('face');
  const sampleInput = $('sample-input');
  const sizeInput = $('size');
  const sizeLabel = $('size-label');
  const glyphGrid = $('glyphs');
  const moreButton = $('more');

  let sample = 'The quick brown fox jumps over the lazy dog.';
  // The file now shown, and which font of a collection.
  let file = null;
  let face = 0;
  let loaded = null;
  let count = 0;
  let characters = [];
  let shown = 0;

  function showNote(text, isError) {
    note.textContent = text;
    note.classList.toggle('error', !!isError);
    note.hidden = !text;
  }

  function fail(message) {
    root.hidden = true;
    showNote(message, true);
    proteus.post({ type: 'error', error: message });
  }

  // Loads the font into the page under a name of its own, and drops the one before.
  async function load(bytes) {
    const family = 'viewed-font-' + ++count;
    let next = new FontFace(family, bytes);
    try {
      await next.load();
    } catch {
      // Some browsers load a font only from an address. A data: address is allowed.
      let text = '';
      const raw = new Uint8Array(bytes);
      for (let i = 0; i < raw.length; i += 0x8000) text += String.fromCharCode.apply(null, raw.subarray(i, i + 0x8000));
      next = new FontFace(family, 'url(data:font/ttf;base64,' + btoa(text) + ')');
      await next.load();
    }
    document.fonts.add(next);
    if (loaded) document.fonts.delete(loaded);
    loaded = next;
    root.style.setProperty('--font', '"' + family + '"');
  }

  function fact(label, value) {
    if (value === undefined || value === null || value === '') return;
    const dt = document.createElement('dt');
    dt.textContent = label;
    const dd = document.createElement('dd');
    dd.textContent = String(value);
    const pair = document.createElement('div');
    pair.append(dt, dd);
    $('facts').append(pair);
  }

  function drawSamples() {
    const text = sample || 'The quick brown fox jumps over the lazy dog.';
    $('big').textContent = text;
    const list = $('sizes');
    list.textContent = '';
    for (const size of SIZES) {
      const row = document.createElement('div');
      row.className = 'size-row';
      const label = document.createElement('span');
      label.className = 'size-label';
      label.textContent = size + ' px';
      const line = document.createElement('span');
      line.className = 'size-line sample';
      line.style.fontSize = size + 'px';
      line.textContent = text;
      row.append(label, line);
      list.append(row);
    }
  }

  function drawLines() {
    const box = $('lines');
    box.textContent = '';
    for (const text of LINES) {
      const line = document.createElement('div');
      line.className = 'sample';
      line.textContent = text;
      box.append(line);
    }
  }

  // Control characters have no shape to show.
  const showable = (c) => c >= 0x20 && !(c >= 0x7f && c <= 0x9f) && !(c >= 0xd800 && c <= 0xdfff);

  function drawMoreGlyphs() {
    const end = Math.min(characters.length, shown + PAGE);
    const part = document.createDocumentFragment();
    for (let i = shown; i < end; i++) {
      const code = characters[i];
      const cell = document.createElement('div');
      cell.className = 'glyph';
      const hex = 'U+' + code.toString(16).toUpperCase().padStart(4, '0');
      cell.title = hex;
      const shape = document.createElement('span');
      shape.className = 'shape sample';
      shape.textContent = String.fromCodePoint(code);
      const label = document.createElement('span');
      label.className = 'code';
      label.textContent = hex;
      cell.append(shape, label);
      part.append(cell);
    }
    glyphGrid.append(part);
    shown = end;
    const left = characters.length - shown;
    moreButton.hidden = left <= 0;
    moreButton.textContent = 'Show ' + Math.min(left, PAGE).toLocaleString() + ' more of ' + left.toLocaleString();
  }

  async function show() {
    const bytes = file.bytes;
    const kind = FontFile.kind(bytes);
    if (!kind) {
      fail('This is not a font file this viewer can read.');
      return;
    }
    const faces = FontFile.faces(bytes);
    face = Math.min(face, faces - 1);

    try {
      await load(kind === 'collection' ? FontFile.single(bytes, face) : bytes);
    } catch {
      fail('This font did not load. The file may be damaged.');
      return;
    }

    let about = { names: {}, metrics: {}, characters: null };
    try {
      about = FontFile.describe(await FontFile.tables(bytes, face));
    } catch {
      // The font still draws. Only its facts are missing.
    }
    const names = about.names;
    const metrics = about.metrics;
    const family = names.typoFamily || names.family || file.name;
    const style = names.typoStyle || names.style || '';

    $('family').textContent = family;
    $('style').textContent = [style, names.version].filter(Boolean).join(' · ');
    $('facts').textContent = '';
    fact('Format', FORMATS[kind]);
    fact('Full name', names.full);
    fact('Designer', names.designer);
    fact('Maker', names.maker);
    fact('Units per em', metrics.unitsPerEm);
    fact('Glyphs', metrics.glyphs !== undefined ? metrics.glyphs.toLocaleString() : undefined);
    fact('Characters', about.characters ? about.characters.length.toLocaleString() : undefined);
    fact('Ascender', metrics.ascender);
    fact('Descender', metrics.descender);
    fact('Line gap', metrics.lineGap);
    fact('x-height', metrics.xHeight);
    fact('Cap height', metrics.capHeight);
    fact('Weight', metrics.weight);
    if (metrics.italicAngle) fact('Italic angle', metrics.italicAngle + '°');
    if (metrics.monospace) fact('Spacing', 'Monospace');
    $('legal').textContent = [names.copyright, names.license].filter(Boolean).join('\n\n');
    $('legal').hidden = !names.copyright && !names.license;

    facePicker.textContent = '';
    facePicker.hidden = faces < 2;
    for (let i = 0; i < faces && faces > 1; i++) {
      const option = document.createElement('option');
      option.value = String(i);
      option.textContent = 'Font ' + (i + 1) + ' of ' + faces;
      facePicker.append(option);
    }
    facePicker.value = String(face);
    if (faces > 1) {
      // Each font of a collection names itself once read.
      for (let i = 0; i < faces; i++) {
        FontFile.tables(bytes, i)
          .then((t) => {
            const n = FontFile.describe(t).names;
            const option = facePicker.options[i];
            if (option) option.textContent = [n.typoFamily || n.family, n.typoStyle || n.style].filter(Boolean).join(' ') || option.textContent;
          })
          .catch(() => {});
      }
    }

    glyphGrid.textContent = '';
    shown = 0;
    characters = (about.characters || []).filter(showable);
    $('glyph-note').textContent = about.characters
      ? characters.length === 0
        ? 'This font maps no characters.'
        : ''
      : kind === 'woff2'
        ? 'This app cannot unpack the tables inside a WOFF2 file, so it cannot list the characters.'
        : 'The list of characters could not be read.';
    $('glyph-note').hidden = !$('glyph-note').textContent;
    drawMoreGlyphs();

    drawSamples();
    root.hidden = false;
    showNote('');
    proteus.post({
      type: 'view',
      family,
      style,
      format: FORMATS[kind],
      glyphs: metrics.glyphs,
      characters: about.characters ? about.characters.length : undefined,
      faces,
      bytes: bytes.byteLength,
    });
  }

  proteus.onFile((next) => {
    if (!next.bytes) {
      fail(next.error || 'The file could not be read.');
      return;
    }
    file = next;
    show();
  });

  proteus.on((message) => {
    if (!message) return;
    if (message.type === 'config') {
      if (typeof message.sample === 'string' && message.sample) {
        // The settings give the first sample. What is typed in the page stays.
        if (sampleInput.value === '' || sampleInput.value === sample) sampleInput.value = message.sample;
        sample = sampleInput.value;
        drawSamples();
      }
    } else if (message.type === 'failed') {
      fail(message.error || 'The file could not be read.');
    }
  });

  sampleInput.addEventListener('input', () => {
    sample = sampleInput.value;
    drawSamples();
  });
  sizeInput.addEventListener('input', () => {
    root.style.setProperty('--big', sizeInput.value + 'px');
    sizeLabel.textContent = sizeInput.value + ' px';
  });
  facePicker.addEventListener('change', () => {
    face = Number(facePicker.value) || 0;
    if (file) show();
  });
  moreButton.addEventListener('click', drawMoreGlyphs);

  sampleInput.value = sample;
  drawLines();
  drawSamples();
  showNote('Loading…');
})();
