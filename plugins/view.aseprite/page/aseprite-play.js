// The order frames play in, for the whole sprite or for one tag.
//
// AsepritePlay.order(frameCount, tag) returns a list of frame numbers, counted from 0, that
// plays once round and then starts again. With no tag, it is every frame in turn. A tag plays
// from its first frame to its last (forward), from its last to its first (reverse), there and
// back (pingpong), or back and there (pingpong-reverse). There and back does not show the
// frames at either end twice in a row.

const AsepritePlay = (() => {
  'use strict';

  function range(from, to) {
    const out = [];
    if (from <= to) for (let i = from; i <= to; i++) out.push(i);
    else for (let i = from; i >= to; i--) out.push(i);
    return out;
  }

  function order(frameCount, tag) {
    if (frameCount <= 0) return [0];
    if (!tag) return range(0, frameCount - 1);
    const last = frameCount - 1;
    const from = Math.max(0, Math.min(tag.from, last));
    const to = Math.max(from, Math.min(tag.to, last));
    // The frames between the two ends, which the way back passes through.
    const between = to - from >= 2;
    switch (tag.direction) {
      case 'reverse':
        return range(to, from);
      case 'pingpong':
        return between ? range(from, to).concat(range(to - 1, from + 1)) : range(from, to);
      case 'pingpong-reverse':
        return between ? range(to, from).concat(range(from + 1, to - 1)) : range(to, from);
      default:
        return range(from, to);
    }
  }

  return { order };
})();
