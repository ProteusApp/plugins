-- The shader canvas's CSS. The parts every node canvas shares, such as frames and the
-- minimap, come from `node_canvas.CSS`.

-- lang=css
return [[
.sg-root { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.sg-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-bottom: 0.5px solid var(--border);
  background: var(--bg-alt);
  font-size: 12px;
}
.sg-bar .sg-status { margin-left: auto; color: var(--fg-muted); }
.sg-bar .sg-status.bad { color: var(--danger); cursor: pointer; }
.sg-viewport {
  position: relative;
  flex: 1;
  min-height: 0;
  overflow: hidden;
  background-color: var(--bg);
  background-image: radial-gradient(circle, var(--border) 1.1px, transparent 1.2px);
  background-size: 22px 22px;
  user-select: none;
  outline: none;
}
.sg-viewport.panning { cursor: grabbing; }
.sg-world { position: absolute; left: 0; top: 0; transform-origin: 0 0; }
.sg-wires { position: absolute; left: 0; top: 0; width: 1px; height: 1px; overflow: visible; }
.sg-wire { fill: none; stroke-width: 2.4; pointer-events: none; }
.sg-wire.selected { stroke-width: 4.5; }
.sg-wire.temp { stroke-dasharray: 6 5; }
.sg-hit { fill: none; stroke: transparent; stroke-width: 12; pointer-events: stroke; cursor: pointer; }
.sg-node {
  position: absolute;
  left: 0;
  top: 0;
  width: 232px;
  background: var(--bg-elev);
  border: 0.5px solid var(--border);
  border-radius: 9px;
  font-size: 12px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.18), 0 8px 22px rgba(0, 0, 0, 0.1);
}
.sg-node.selected { outline: 2px solid var(--accent); outline-offset: 1px; }
.sg-node.error { border-color: var(--danger); }
.sg-node.unused { opacity: 0.62; }
.sg-head {
  height: 34px;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 10px;
  border-radius: 9px 9px 0 0;
  border-top: 3px solid var(--cat, var(--border));
  cursor: grab;
}
.sg-head .sg-title { flex: 1; min-width: 0; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sg-head .sg-kind { color: var(--fg-muted); font-family: var(--font-mono); font-size: 10.5px; }
.sg-row {
  position: relative;
  height: 26px;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 12px 0 14px;
  border-top: 0.5px solid var(--border);
}
.sg-row.out { justify-content: flex-end; padding: 0 14px 0 12px; }
.sg-row .sg-label { flex: none; max-width: 92px; color: var(--fg-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sg-row.out .sg-label { color: var(--fg); }
.sg-row .sg-fill { flex: 1; min-width: 0; display: flex; gap: 3px; justify-content: flex-end; }
.sg-row .sg-t { color: var(--fg-muted); font-family: var(--font-mono); font-size: 10.5px; }
.sg-row .sg-builtin { color: var(--fg-muted); font-style: italic; font-size: 11px; }
.sg-row.message { color: var(--danger); height: auto; min-height: 26px; padding: 4px 10px; white-space: normal; line-height: 1.3; }
.sg-port {
  position: absolute;
  top: 7px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  box-sizing: border-box;
  border: 2px solid var(--bg-elev);
  box-shadow: 0 0 0 1px var(--border);
  cursor: crosshair;
  z-index: 2;
}
/* A wider target than the dot, so a port is easy to hit when zoomed out. */
.sg-port::before { content: ''; position: absolute; inset: -7px; border-radius: 50%; }
.sg-port.in { left: -6px; }
.sg-port.out { right: -6px; }
.sg-port.linked { box-shadow: 0 0 0 1.5px var(--fg-muted); }
.sg-num, .sg-text, .sg-select {
  min-width: 0;
  height: 19px;
  padding: 0 4px;
  border: 0.5px solid var(--border);
  border-radius: 4px;
  background: var(--bg);
  color: var(--fg);
  font: inherit;
  font-family: var(--font-mono);
  font-size: 11px;
  outline: none;
}
.sg-num { width: 100%; max-width: 54px; text-align: right; }
.sg-text { flex: 1; width: 100%; }
.sg-select { flex: 1; font-family: inherit; }
.sg-num:focus, .sg-text:focus, .sg-select:focus { border-color: var(--accent); }
.sg-color { width: 34px; height: 19px; padding: 0; border: 0.5px solid var(--border); border-radius: 4px; background: none; cursor: pointer; }
.sg-empty {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  color: var(--fg-muted);
  pointer-events: none;
  text-align: center;
  line-height: 1.6;
}
.sg-wire.insert { stroke-width: 5; }
.sg-frames { position: absolute; left: 0; top: 0; }
.sg-viewport .nc-minimap { bottom: 12px; }
]]
