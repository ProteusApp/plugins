-- api_css: the API client's styles: the request editor with its tabs and key and value grids,
-- the response, the lists of requests and history, and the environments view.

-- lang=css
return [[
.api { flex: 1; min-height: 0; height: 100%; display: flex; flex-direction: column;
  background: var(--bg); color: var(--fg); font-family: var(--font-ui); font-size: var(--font-size); }
.api-editor { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.api-editor.api-dragging, .api-editor.api-dragging * { user-select: none; cursor: row-resize !important; }
.api-top { flex: none; height: var(--api-top, 46%); min-height: 110px; max-height: calc(100% - 90px);
  display: flex; flex-direction: column; min-width: 0; }
.api-head { flex: none; display: flex; align-items: center; gap: 8px; padding: 12px 16px 0; min-width: 0; }
.api-title { font-weight: 600; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.api-title.untitled { font-style: italic; font-weight: 500; color: var(--fg-muted); }
.api-where { color: var(--fg-faint); font-size: 12px; white-space: nowrap; }
.api-dot { flex: none; width: 7px; height: 7px; border-radius: 50%; background: var(--accent); }
.api-line { flex: none; display: flex; align-items: center; gap: 6px; padding: 10px 16px; }
.api-method { flex: none; width: 100px; height: 32px; padding: 0 8px; border: 1px solid var(--border);
  border-radius: var(--radius); background: var(--bg-elev); font-family: var(--font-mono); font-size: 12px;
  font-weight: 700; outline: none; cursor: pointer; }
.api-method:focus { border-color: var(--accent); }
.api-method option { background: var(--bg-elev); font-weight: 700; }
.api-url { flex: 1; height: 32px; font-family: var(--font-mono); }
.api-send { flex: none; height: 32px; min-width: 96px; justify-content: center; }
.api-send:not(.primary) { color: var(--danger); }
.api-m-get { color: var(--success); }
.api-m-post { color: var(--warning); }
.api-m-put { color: var(--syn-function); }
.api-m-patch { color: var(--syn-keyword); }
.api-m-delete { color: var(--danger); }
.api-m-head { color: var(--syn-builtin); }
.api-m-options { color: var(--syn-constant); }
.api-tabs { flex: none; display: flex; gap: 4px; padding: 0 12px; border-bottom: 1px solid var(--border); }
.api-tab { display: inline-flex; align-items: center; gap: 6px; padding: 6px 8px 7px; margin-bottom: -1px;
  border: none; border-bottom: 2px solid transparent; background: none; color: var(--fg-muted); cursor: pointer; }
.api-tab:hover { color: var(--fg); }
.api-tab.on { color: var(--fg); border-bottom-color: var(--accent); }
.api-count { font-size: 11px; font-weight: 600; color: var(--accent); }
.api-mark { width: 5px; height: 5px; border-radius: 50%; background: var(--accent); }
.api-pane { flex: 1; min-height: 0; overflow: auto; display: flex; flex-direction: column; padding: 10px 16px 12px; }
.api-part { display: flex; flex-direction: column; gap: 8px; }
.api-part.fill { flex: 1; min-height: 0; }
.api-kv { display: flex; flex-direction: column; gap: 4px; }
.api-kv-head, .api-kv-row { display: grid; grid-template-columns: 22px minmax(0, 1fr) minmax(0, 1.5fr) 28px;
  gap: 6px; align-items: center; }
.api-kv-head { font-size: 11px; color: var(--fg-faint); }
.api-kv-row input[type=checkbox] { margin: 0 auto; accent-color: var(--accent); cursor: pointer; }
.api-kv-in { height: 28px; min-width: 0; padding: 0 8px; border: 1px solid var(--border); border-radius: var(--radius);
  background: var(--bg); color: var(--fg); font-family: var(--font-mono); font-size: 12px; outline: none; }
.api-kv-in:focus { border-color: var(--accent); }
.api-kv-row.off .api-kv-in { color: var(--fg-faint); }
.api-kv-del { display: inline-grid; place-items: center; width: 28px; height: 28px; border: none;
  border-radius: var(--radius); background: none; color: var(--fg-faint); cursor: pointer; }
.api-kv-del:hover { background: var(--bg-hover); color: var(--danger); }
.api-kv-row:last-child input[type=checkbox], .api-kv-row:last-child .api-kv-del { visibility: hidden; }
.api-kv.files .api-kv-head, .api-kv.files .api-kv-row {
  grid-template-columns: 22px minmax(0, 1fr) minmax(0, 1.5fr) 28px 28px; }
.api-kv-file { display: flex; align-items: center; gap: 6px; height: 28px; min-width: 0; padding: 0 8px;
  border: 1px dashed var(--border); border-radius: var(--radius); background: var(--bg); color: var(--fg);
  font-family: var(--font-mono); font-size: 12px; cursor: pointer; overflow: hidden; white-space: nowrap; }
.api-kv-file:hover { border-color: var(--accent); }
.api-kv-file.need { color: var(--warning); }
.api-kv-kind { display: inline-grid; place-items: center; width: 28px; height: 28px; border: none;
  border-radius: var(--radius); background: none; color: var(--fg-faint); cursor: pointer; }
.api-kv-kind:hover { background: var(--bg-hover); color: var(--fg); }
.api-kv-kind.on { color: var(--accent); }
.api-filebox { display: flex; align-items: center; gap: 8px; min-width: 0; }
.api-file-name { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  font-family: var(--font-mono); font-size: 12px; }
.api-file-name.need { color: var(--warning); }
.api-label { font-size: 12px; color: var(--fg-muted); }
.api-code.vars { flex: 0 0 110px; min-height: 60px; }
.api-check { display: flex; align-items: center; gap: 8px; font-size: 12px; cursor: pointer; }
.api-check input { accent-color: var(--accent); }
.api-inline { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.api-num { width: 110px; }
.api-to { color: var(--fg-muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.api-note { color: var(--fg-faint); font-size: 12px; }
.api-modes-row { flex: none; display: flex; align-items: center; gap: 8px; }
.api-modes { display: flex; flex-wrap: wrap; gap: 4px; }
.api-mode { padding: 3px 12px; border: 1px solid var(--border); border-radius: 99px; background: none;
  color: var(--fg-muted); font-size: 12px; cursor: pointer; }
.api-mode:hover { color: var(--fg); background: var(--bg-hover); }
.api-mode.on { background: var(--accent); border-color: var(--accent); color: var(--accent-fg); }
.api-small { padding: 3px 8px; font-size: 12px; }
.api-code { flex: 1; min-height: 90px; border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; }
.api-code .cm-editor { height: 100%; }
.api-fields { display: flex; flex-direction: column; gap: 10px; max-width: 520px; }
.api-field { display: flex; flex-direction: column; gap: 4px; }
.api-field > span { font-size: 12px; color: var(--fg-muted); }
.api-mono { font-family: var(--font-mono); }
.api-pass { display: flex; gap: 4px; }
.api-pass .ui-input { flex: 1; }
.api-split { flex: none; position: relative; z-index: 2; height: 7px; margin: -3px 0; cursor: row-resize; }
.api-split::after { content: ""; position: absolute; left: 0; right: 0; top: 3px; height: 1px; background: var(--border); }
.api-split:hover::after, .api-dragging .api-split::after { top: 2px; height: 3px; background: var(--accent); }
.api-bottom { flex: 1; min-height: 70px; display: flex; flex-direction: column; background: var(--bg-alt); }
.api-sum { flex: none; display: flex; flex-wrap: wrap; align-items: center; gap: 12px; min-height: 40px;
  padding: 4px 16px; border-bottom: 1px solid var(--border); }
.api-sum-label { font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; color: var(--fg-muted); }
.api-status { font-family: var(--font-mono); font-weight: 700; }
.api-s-info { color: var(--fg-muted); }
.api-s-success { color: var(--success); }
.api-s-redirect { color: var(--accent); }
.api-s-client { color: var(--warning); }
.api-s-server, .api-s-none { color: var(--danger); }
.api-meta { color: var(--fg-muted); font-size: 12px; }
.api-grow { flex: 1; }
.api-seg { display: inline-flex; border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; }
.api-seg button { display: inline-flex; align-items: center; gap: 5px; padding: 3px 10px; border: none;
  background: none; color: var(--fg-muted); font-size: 12px; cursor: pointer; }
.api-seg button + button { border-left: 1px solid var(--border); }
.api-seg button:hover { color: var(--fg); background: var(--bg-hover); }
.api-seg button.on { color: var(--fg); background: var(--bg-active); }
.api-icon-btn { display: inline-grid; place-items: center; width: 28px; height: 26px; border: none;
  border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.api-icon-btn:hover { color: var(--fg); background: var(--bg-hover); }
.api-warn { flex: none; padding: 8px 16px 0; color: var(--warning); font-size: 12px; }
.api-res { flex: 1; min-height: 0; display: flex; flex-direction: column; padding: 10px 16px 14px; }
.api-hint { margin: auto; color: var(--fg-faint); text-align: center; }
.api-error { color: var(--danger); font-family: var(--font-mono); font-size: 12px; white-space: pre-wrap; overflow: auto; }
.api-hdrs { flex: 1; min-height: 0; overflow: auto; }
.api-htable { width: 100%; border-collapse: collapse; font-family: var(--font-mono); font-size: 12px; }
.api-htable td { padding: 5px 8px; border-bottom: 1px solid var(--border); vertical-align: top; word-break: break-all; }
.api-htable td:first-child { width: 32%; color: var(--fg-muted); word-break: normal; }
.api-none { flex: 1; display: flex; align-items: center; justify-content: center; padding: 24px; }
.api-none-card { display: flex; flex-direction: column; align-items: center; gap: 10px; text-align: center; color: var(--fg-muted); }
.api-none-card > .ui-icon { color: var(--fg-faint); }
.api-none-title { font-size: 15px; font-weight: 600; color: var(--fg); }
.api-side { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.api-side-bar { flex: none; display: flex; align-items: center; gap: 4px; padding: 8px 8px 6px; }
.api-side-title { font-size: 12px; color: var(--fg-muted); }
.api-side-btn { padding: 4px 6px; }
.api-search { flex: 1; min-width: 0; }
.api-list-box { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.api-list { flex: 1; min-height: 0; overflow: auto; padding: 0 6px 12px; }
.api-group { padding: 8px 8px 4px; font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
  color: var(--fg-faint); }
.api-row, .api-folder { display: flex; align-items: center; gap: 6px; height: 28px; padding-right: 8px;
  border-radius: var(--radius); cursor: pointer; white-space: nowrap; }
.api-row:hover, .api-folder:hover { background: var(--bg-hover); }
.api-row.on { background: var(--bg-active); }
.api-folder { color: var(--fg-muted); }
.api-folder:hover { color: var(--fg); }
.api-badge { flex: none; width: 40px; font-family: var(--font-mono); font-size: 10px; font-weight: 700; text-align: right; }
.api-rname { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.api-rname.untitled { font-style: italic; color: var(--fg-muted); }
.api-empty { margin: 24px 12px; display: flex; flex-direction: column; align-items: center; gap: 10px;
  color: var(--fg-faint); text-align: center; }
.api-hrow { padding: 6px 8px; border-radius: var(--radius); cursor: pointer; }
.api-hrow:hover { background: var(--bg-hover); }
.api-hline { display: flex; align-items: center; gap: 6px; min-width: 0; }
.api-hline .api-badge { width: auto; text-align: left; }
.api-hurl { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  font-family: var(--font-mono); font-size: 12px; }
.api-hmeta { display: flex; gap: 10px; margin-top: 2px; font-size: 11px; color: var(--fg-faint); }
.api-envs .api-code { margin: 0 8px; }
.api-env-msg { flex: none; padding: 8px 10px 10px; font-size: 12px; color: var(--fg-muted); white-space: pre-wrap; }
.api-env-msg.bad { color: var(--danger); }
.api-env.on { color: var(--accent); }
]]
