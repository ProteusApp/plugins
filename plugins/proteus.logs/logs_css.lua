-- logs_css: the log viewer's styles: the bar with the filter and the level chips, the list
-- of lines with their colours and columns, the detail panel, and the Sources view.

-- lang=css
return [[
.logs {
  flex: 1;
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--fg);
}
.logs-bar {
  flex: none;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
}
.logs-filter {
  flex: 1 1 220px;
  min-width: 160px;
  max-width: 460px;
  font-family: var(--font-mono);
}
.logs-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}
.logs-chip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 2px 9px;
  border: 1px solid var(--border);
  border-radius: 99px;
  background: var(--bg-elev);
  color: var(--fg);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}
.logs-chip::before {
  content: "";
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--fg-faint);
}
.logs-chip:hover {
  background: var(--bg-hover);
}
.logs-chip.off {
  opacity: 0.45;
  text-decoration: line-through;
}
.logs-chip-error::before {
  background: var(--danger);
}
.logs-chip-warn::before {
  background: var(--warning);
}
.logs-chip-info::before {
  background: var(--accent);
}
.logs-chip-debug::before {
  background: var(--fg-muted);
}
.logs-chip-n {
  color: var(--fg-muted);
  font-variant-numeric: tabular-nums;
}
.logs-bar .ui-button {
  padding: 3px 9px;
  font-size: 12px;
}
.logs-bar .logs-toggle.on {
  color: var(--accent);
  border-color: var(--accent);
}
.logs-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}
.logs-list {
  flex: 1;
  min-height: 0;
  overflow: auto;
  position: relative;
  outline: none;
  padding: 4px 0;
  font: 12px/18px var(--font-mono);
}
.logs-row {
  display: flex;
  width: max-content;
  min-width: 100%;
  white-space: pre;
  border-left: 2px solid transparent;
}
.logs-row:hover {
  background: var(--bg-hover);
}
.logs-wrap .logs-row {
  width: auto;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.logs-n {
  flex: none;
  min-width: 5.5em;
  padding: 0 12px 0 6px;
  text-align: right;
  color: var(--fg-faint);
  user-select: none;
}
.logs-t {
  flex: 1;
  min-width: 0;
  padding-right: 12px;
}
.logs-lv-error {
  color: var(--danger);
}
.logs-lv-warn {
  color: var(--warning);
}
.logs-lv-debug {
  color: var(--fg-muted);
}
.logs-stderr {
  border-left-color: var(--danger);
}
.logs-list mark {
  background: var(--accent);
  color: var(--accent-fg);
  border-radius: 2px;
}
.logs-more {
  color: var(--fg-faint);
}
.logs-b {
  font-weight: 700;
}
.logs-c0,
.logs-c8 {
  color: var(--fg-faint);
}
.logs-c1,
.logs-c9 {
  color: var(--danger);
}
.logs-c2 {
  color: var(--success);
}
.logs-c3 {
  color: var(--warning);
}
.logs-c4,
.logs-c12 {
  color: var(--syn-function);
}
.logs-c5,
.logs-c13 {
  color: var(--syn-keyword);
}
.logs-c6 {
  color: var(--syn-operator);
}
.logs-c7 {
  color: var(--fg-muted);
}
.logs-c10 {
  color: var(--syn-string);
}
.logs-c11 {
  color: var(--syn-property);
}
.logs-c14 {
  color: var(--syn-builtin);
}
.logs-c15 {
  color: var(--fg);
}
.logs-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 24px;
  text-align: center;
  color: var(--fg-muted);
}
.logs-empty-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--fg);
}
.logs-empty-text {
  max-width: 420px;
}
.logs-empty-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 8px;
  margin-top: 8px;
}
.logs-detail {
  flex: none;
  height: 38%;
  min-height: 140px;
  display: flex;
  flex-direction: column;
  border-top: 1px solid var(--border);
  background: var(--bg-alt);
}
.logs-detail-head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 3px 6px 3px 12px;
  border-bottom: 1px solid var(--border);
  font-size: 12px;
}
.logs-detail-head .ui-button {
  padding: 3px 8px;
  font-size: 12px;
}
.logs-detail-title {
  color: var(--fg-muted);
}
.logs-detail-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}
.logs-detail-text {
  flex: 1;
  min-height: 0;
  margin: 0;
  padding: 8px 12px;
  overflow: auto;
  font: 12px/1.5 var(--font-mono);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  user-select: text;
}
.logs-has-json .logs-detail-text {
  flex: none;
  max-height: 5.5em;
  border-bottom: 1px solid var(--border);
}
.logs-json {
  flex: 1;
  min-height: 0;
}
.logs-side {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}
.logs-side-actions {
  flex: none;
  display: flex;
  gap: 4px;
  padding: 8px;
}
.logs-side-actions .ui-button {
  flex: 1;
  justify-content: center;
  padding: 4px 6px;
  font-size: 12px;
}
.logs-sources {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 0 6px 8px;
}
.logs-src {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 6px 6px 8px;
  border-radius: var(--radius);
  cursor: pointer;
}
.logs-src:hover {
  background: var(--bg-hover);
}
.logs-src.active {
  background: var(--bg-active);
}
.logs-src-icon {
  display: inline-flex;
  color: var(--fg-muted);
}
.logs-src-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.logs-src-count {
  font-size: 11px;
  color: var(--fg-faint);
  font-variant-numeric: tabular-nums;
}
.logs-dot {
  flex: none;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--fg-faint);
}
.logs-dot-running {
  background: var(--success);
}
.logs-dot-done {
  background: var(--fg-muted);
}
.logs-dot-exit {
  background: var(--warning);
}
.logs-dot-failed {
  background: var(--danger);
}
.logs-dot-pasted {
  background: var(--accent);
}
.logs-batch {
  display: contents;
}
.logs-tag {
  flex: none;
  max-width: 12em;
  margin-right: 8px;
  padding: 0 6px;
  border-radius: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  background: var(--bg-active);
  color: var(--fg-muted);
}
.logs-tag-1 {
  color: var(--accent);
}
.logs-tag-2 {
  color: var(--success);
}
.logs-tag-3 {
  color: var(--warning);
}
.logs-tag-4 {
  color: var(--syn-keyword);
}
.logs-tag-5 {
  color: var(--syn-function);
}
.logs-page {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px;
  color: var(--fg-muted);
  font-family: var(--font-ui);
}
.logs-filter.bad {
  border-color: var(--danger);
}
.logs-problem {
  flex: 1 1 100%;
  color: var(--danger);
  font-size: 12px;
}
.logs-src.merged .logs-src-name {
  font-style: italic;
}
.logs-src-close {
  display: inline-flex;
  padding: 2px;
  border: none;
  border-radius: 4px;
  background: none;
  color: var(--fg-faint);
  cursor: pointer;
  opacity: 0;
}
.logs-src:hover .logs-src-close,
.logs-src.active .logs-src-close {
  opacity: 1;
}
.logs-src-close:hover {
  color: var(--fg);
  background: var(--bg-hover);
}
.logs-head {
  position: sticky;
  top: 0;
  z-index: 1;
  display: flex;
  width: max-content;
  min-width: 100%;
  white-space: pre;
  border-left: 2px solid transparent;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
  color: var(--fg-muted);
  font-weight: 600;
}
.logs-hcol,
.logs-f {
  flex: none;
  box-sizing: content-box;
  padding-right: 1ch;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: pre;
}
.logs-hcol {
  cursor: pointer;
}
.logs-hcol:hover {
  color: var(--fg);
}
.logs-hcol.on {
  color: var(--accent);
}
.logs-f {
  color: var(--syn-property);
}
.logs-src-none {
  padding: 16px 8px;
  text-align: center;
  color: var(--fg-faint);
}
]]
