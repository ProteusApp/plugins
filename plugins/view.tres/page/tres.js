(function (root) {
  "use strict";
  function statements(text) {
    const out = [];
    let start = 0,
      quote = false,
      escape = false,
      comment = false,
      stack = [];
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (comment) {
        if (c !== "\n") continue;
        comment = false;
      } else if (quote) {
        if (escape) escape = false;
        else if (c === "\\") escape = true;
        else if (c === '"') quote = false;
        continue;
      } else if (c === '"') {
        quote = true;
        continue;
      } else if (c === ";") {
        comment = true;
        continue;
      } else if ("([{".includes(c)) stack.push(c);
      else if (")]}".includes(c)) {
        if (stack.pop() !== { ")": "(", "]": "[", "}": "{" }[c])
          throw Error("Unbalanced brackets.");
      }
      if (c === "\n" && !stack.length) {
        out.push({ start, text: text.slice(start, i) });
        start = i + 1;
      }
    }
    if (quote || stack.length) throw Error("Unfinished string or value.");
    if (start < text.length) out.push({ start, text: text.slice(start) });
    return out;
  }
  function valueEnd(text) {
    let quote = false,
      escape = false,
      comment = false,
      depth = 0;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (comment) {
        if (c === "\n") comment = false;
        continue;
      }
      if (quote) {
        if (escape) escape = false;
        else if (c === "\\") escape = true;
        else if (c === '"') quote = false;
      } else if (c === '"') quote = true;
      else if (c === ";") {
        if (!depth) return i;
        comment = true;
      } else if ("([{".includes(c)) depth++;
      else if (")]}".includes(c)) depth--;
    }
    return text.length;
  }
  function parse(text) {
    const sections = [];
    let section;
    for (const line of statements(text)) {
      const clean = line.text.trim();
      if (!clean || clean.startsWith(";")) continue;
      const header = clean.match(
        /^\[(gd_resource|ext_resource|sub_resource|resource)\b([^\]]*)\]\s*(?:;.*)?$/,
      );
      if (header) {
        const attrs = {};
        for (const m of header[2].matchAll(
          /(\w+)\s*=\s*("(?:\\.|[^"\\])*"|[^\s]+)/g,
        ))
          attrs[m[1]] = m[2].replace(/^"|"$/g, "");
        section = { kind: header[1], attrs, properties: [] };
        sections.push(section);
      } else {
        const match = line.text.match(/^(\s*([^\s=]+)\s*=\s*)([\s\S]*)$/);
        if (
          !match ||
          !section ||
          !["resource", "sub_resource"].includes(section.kind)
        )
          throw Error("Unrecognized resource syntax. Open this file as text.");
        const raw = match[3];
        const end = valueEnd(raw);
        const value = raw.slice(0, end).trimEnd();
        if (!value) throw Error("A property has no value.");
        section.properties.push({
          name: match[2],
          value,
          start: line.start + match[1].length,
          end: line.start + match[1].length + value.length,
        });
      }
    }
    if (
      sections[0]?.kind !== "gd_resource" ||
      sections.filter((s) => s.kind === "resource").length !== 1
    )
      throw Error("Expected a Godot .tres resource.");
    return { text, sections };
  }
  function replace(doc, property, value) {
    if (!value.trim()) throw Error("A value is required.");
    const lines = statements(value);
    if (lines.length !== 1 || valueEnd(value) !== value.length)
      throw Error("Enter one value without comments.");
    return parse(
      doc.text.slice(0, property.start) + value + doc.text.slice(property.end),
    );
  }
  const numeric = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i;
  function describe(value) {
    if (value === "true" || value === "false") return { type: "boolean" };
    if (numeric.test(value)) return { type: "number" };
    if (/^"(?:\\.|[^"\\])*"$/.test(value)) {
      try {
        return { type: "string", text: JSON.parse(value) };
      } catch (_) {
        return { type: "raw" };
      }
    }
    const vector = value.match(
      /^(Vector[234]i?|Color|Quaternion|Rect2i?)\((.*)\)$/s,
    );
    if (vector) {
      const parts = vector[2].split(",").map((p) => p.trim());
      const count = /Vector2|Rect2/.test(vector[1])
        ? vector[1].startsWith("Rect")
          ? 4
          : 2
        : vector[1].startsWith("Vector3")
          ? 3
          : 4;
      if (parts.length === count && parts.every((p) => numeric.test(p)))
        return { type: "vector", name: vector[1], parts };
    }
    const ref = value.match(
      /^(SubResource|ExtResource)\(\s*("(?:\\.|[^"\\])*"|\d+)\s*\)$/,
    );
    if (ref)
      return {
        type: "reference",
        name: ref[1],
        id: ref[2].replace(/^"|"$/g, ""),
      };
    return { type: "raw" };
  }
  root.Tres = { parse, replace, describe };
})(globalThis);
