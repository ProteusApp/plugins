(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  let doc,
    selected = 0,
    history = [],
    future = [];
  const post = (message) => proteus.post(message);
  const status = (text) => {
    $("status").textContent = text;
  };
  function element(tag, text) {
    const el = document.createElement(tag);
    if (text !== undefined) el.textContent = text;
    return el;
  }
  function change(property, value) {
    try {
      const next = Tres.replace(doc, property, value);
      if (next.text === doc.text) return;
      history.push(doc.text);
      future = [];
      doc = next;
      post({ type: "change", text: doc.text });
      status("Unsaved changes");
      render();
    } catch (error) {
      status(error.message);
    }
  }
  function render() {
    $("undo").disabled = !history.length;
    $("redo").disabled = !future.length;
    const sections = doc.sections.filter((s) =>
      ["resource", "sub_resource"].includes(s.kind),
    );
    $("resources").replaceChildren();
    sections.forEach((section, index) => {
      const button = element(
        "button",
        section.kind === "resource" ? "Main resource" : section.attrs.id,
      );
      button.classList.toggle("selected", selected === index);
      button.onclick = () => {
        selected = index;
        render();
      };
      $("resources").append(button);
    });
    const section = sections[selected] || sections[0];
    $("title").textContent =
      section.attrs.type ||
      doc.sections[0].attrs.script_class ||
      doc.sections[0].attrs.type ||
      "Resource";
    $("properties").replaceChildren();
    const filter = $("filter").value.toLowerCase();
    for (const [index, property] of section.properties.entries()) {
      if (!property.name.toLowerCase().includes(filter)) continue;
      const row = element("div");
      row.className = "property";
      const label = element("label", property.name.replaceAll("_", " "));
      label.htmlFor = `value-${index}`;
      label.title = property.name;
      row.append(label);
      const kind = Tres.describe(property.value);
      let input;
      if (kind.type === "boolean") {
        input = element("input");
        input.type = "checkbox";
        input.checked = property.value === "true";
        input.onchange = () => change(property, String(input.checked));
      } else if (kind.type === "number" || kind.type === "string") {
        input = element("input");
        input.type = kind.type === "number" ? "number" : "text";
        input.step = "any";
        input.value = kind.text ?? property.value;
        input.onchange = () => {
          if (input.checkValidity())
            change(
              property,
              kind.type === "string"
                ? JSON.stringify(input.value)
                : input.value,
            );
        };
      } else if (kind.type === "vector") {
        input = element("div");
        input.className = "fields";
        const parts = [...kind.parts];
        parts.forEach((part, axis) => {
          const field = element("input");
          field.type = "number";
          field.step = kind.name.endsWith("i") ? "1" : "any";
          field.value = part;
          field.setAttribute(
            "aria-label",
            `${property.name} ${kind.name === "Color" ? "RGBA"[axis] : "XYZW"[axis]}`,
          );
          field.title = field.getAttribute("aria-label");
          field.onchange = () => {
            if (field.value && field.checkValidity()) {
              parts[axis] = field.value;
              change(property, `${kind.name}(${parts.join(", ")})`);
            }
          };
          input.append(field);
        });
        if (
          kind.name === "Color" &&
          parts.slice(0, 3).every((p) => +p >= 0 && +p <= 1)
        ) {
          const picker = element("input");
          picker.type = "color";
          picker.setAttribute("aria-label", `${property.name} color`);
          picker.value =
            "#" +
            parts
              .slice(0, 3)
              .map((p) =>
                Math.round(+p * 255)
                  .toString(16)
                  .padStart(2, "0"),
              )
              .join("");
          picker.onchange = () =>
            change(
              property,
              `Color(${[1, 3, 5].map((i) => parseInt(picker.value.slice(i, i + 2), 16) / 255).join(", ")}, ${parts[3]})`,
            );
          input.append(picker);
        }
      } else if (kind.type === "reference") {
        input = element("select");
        for (const resource of doc.sections.filter(
          (s) =>
            s.kind ===
            (kind.name === "SubResource" ? "sub_resource" : "ext_resource"),
        )) {
          const option = element(
            "option",
            `${resource.attrs.type || "Resource"} · ${resource.attrs.path || resource.attrs.id}`,
          );
          option.value = resource.attrs.id;
          input.append(option);
        }
        if (![...input.options].some((o) => o.value === kind.id)) {
          const option = element("option", `Missing resource: ${kind.id}`);
          option.value = kind.id;
          input.append(option);
        }
        input.value = kind.id;
        input.onchange = () =>
          change(
            property,
            `${kind.name}(${/^\d+$/.test(input.value) && doc.sections[0].attrs.format === "2" ? input.value : JSON.stringify(input.value)})`,
          );
      } else {
        input = element("textarea");
        input.value = property.value;
        input.spellcheck = false;
        input.onchange = () => change(property, input.value);
      }
      input.id = `value-${index}`;
      row.append(input);
      $("properties").append(row);
    }
    if (!section.properties.length)
      $("properties").append(
        element("p", "This resource has no saved properties."),
      );
  }
  function travel(from, to) {
    if (!from.length) return;
    to.push(doc.text);
    doc = Tres.parse(from.pop());
    post({ type: "change", text: doc.text });
    render();
  }
  $("undo").onclick = () => travel(history, future);
  $("redo").onclick = () => travel(future, history);
  $("save").onclick = () => post({ type: "save" });
  $("reload").onclick = () => post({ type: "reload" });
  $("text").onclick = () => post({ type: "text" });
  $("filter").oninput = () => {
    if (doc) render();
  };
  document.addEventListener("keydown", (event) => {
    if (!(event.ctrlKey || event.metaKey)) return;
    if (event.key.toLowerCase() === "s") {
      event.preventDefault();
      document.activeElement?.blur();
      post({ type: "save" });
    }
  });
  proteus.on((message) => {
    if (message.type === "load") {
      try {
        doc = Tres.parse(message.text);
        history = [];
        future = [];
        selected = 0;
        render();
        status("Only properties saved in this file appear here.");
      } catch (error) {
        doc = null;
        history = [];
        future = [];
        $("undo").disabled = true;
        $("redo").disabled = true;
        $("title").textContent = "";
        $("resources").replaceChildren();
        $("properties").replaceChildren();
        status(error.message);
      }
    } else if (message.type === "status") status(message.text);
  });
  post({ type: "ready" });
})();
