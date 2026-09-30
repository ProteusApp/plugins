-- cargo_style: how the Cargo panel looks. Theme variables let every theme restyle it.

-- lang=css
local CSS = [[
.cargo { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.cargo-bar { flex: none; display: flex; align-items: center; gap: 2px; padding: 3px 6px; border-bottom: 1px solid var(--border); }
.cargo-job { display: inline-flex; align-items: center; gap: 5px; height: 22px; padding: 0 8px; border: none; border-radius: var(--radius); background: none; color: var(--fg-muted); font-size: 12px; cursor: pointer; }
.cargo-job:hover { background: var(--bg-hover); color: var(--fg); }
.cargo-job.active { background: var(--bg-active); color: var(--fg); }
.cargo-where { flex: 1; min-width: 0; text-align: right; color: var(--fg-faint); font-size: 11.5px; font-family: var(--font-mono); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; margin-right: 6px; }
.cargo-body { flex: 1; min-height: 0; position: relative; }
.cargo-pane { position: absolute; inset: 0; }
.cargo-empty { padding: 16px 12px; font-size: 12px; color: var(--fg-faint); }
]]

return CSS
