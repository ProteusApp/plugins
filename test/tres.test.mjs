import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
const context = {};
runInNewContext(
  readFileSync(
    new URL("../plugins/view.tres/page/tres.js", import.meta.url),
    "utf8",
  ),
  context,
);
const { parse, replace, describe } = context.Tres;
const sample =
  '[gd_resource type="Resource" format=3]\r\n\r\n; note\r\n[sub_resource type="Resource" id="Resource_a"]\r\nx = Vector2(1, 2)\r\n\r\n[resource]\r\nname = "a; [b] \\"quoted\\"" ; keep\r\nitems = [\r\nSubResource("Resource_a"),\r\n{ "key": [1, 2] }\r\n]\r\nflag = true\r\n';
test("changes only the selected value and keeps CRLF and comments", () => {
  const doc = parse(sample);
  const property = doc.sections.at(-1).properties[0];
  assert.equal(
    replace(doc, property, '"changed"').text,
    sample.replace('"a; [b] \\"quoted\\""', '"changed"'),
  );
  assert.equal(parse(sample).text, sample);
});
test("reads multiline nested values and subresources", () => {
  const doc = parse(sample);
  assert.equal(doc.sections[1].properties[0].value, "Vector2(1, 2)");
  assert.match(doc.sections.at(-1).properties[1].value, /"key": \[1, 2\]/);
  assert.equal(doc.sections.at(-1).properties[2].value, "true");
});
test("rejects incomplete files and values that add properties or sections", () => {
  for (const text of [
    "[gd_scene format=3]",
    "[gd_resource format=3]\n[resource]\nx = [1",
    "[gd_resource format=3]\n[resource]\nx = ([)]",
  ])
    assert.throws(() => parse(text));
  const doc = parse(sample),
    p = doc.sections.at(-1).properties[2];
  for (const value of [
    "",
    "true\nother = false",
    "false ; comment",
    '"unterminated',
  ])
    assert.throws(() => replace(doc, p, value));
});
test("classifies Godot values without evaluating code", () => {
  for (const [value, type] of [
    ["true", "boolean"],
    ["-2e-3", "number"],
    ['"hi"', "string"],
    ["Vector3(1, 2, 3)", "vector"],
    ["Color(1, 0, 0, 0.5)", "vector"],
    ['ExtResource("1_script")', "reference"],
    ['Array[Resource]([SubResource("a")])', "raw"],
    ["null", "raw"],
    ["Vector2(1, 2, 3)", "raw"],
  ])
    assert.equal(describe(value).type, type);
});
test("keeps comments inside multiline containers", () => {
  const source =
    "[gd_resource format=3]\n[resource]\nitems = [1, ; first\n2]\n";
  const doc = parse(source),
    p = doc.sections[1].properties[0];
  assert.equal(p.value, "[1, ; first\n2]");
  assert.equal(
    replace(doc, p, "[3, 4]").text,
    "[gd_resource format=3]\n[resource]\nitems = [3, 4]\n",
  );
});
