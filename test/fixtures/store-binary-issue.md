## Tone 1.0.0

Plays a tone from WebAssembly.

Plugin id: `wam.tone`. Files: `init.lua`, `vendor.json`, `wam/tone.wasm`.

Proteus opened this issue with **Plugins > Publish Plugin**. A workflow turns it into a PR, and a maintainer reviews the code there.

<details><summary>Manifest</summary>

<!-- proteus-manifest -->
```json
{"format":2,"revision":"r2","id":"wam.tone","name":"Tone","description":"Plays a tone from WebAssembly.","version":"1.0.0","files":["init.lua","vendor.json","wam/tone.wasm"]}
```

</details>

<details><summary><code>init.lua</code></summary>

<!-- proteus-file path="init.lua" part="1" of="1" rev="r2" -->
```lua
return { name = 'Tone' }

```

</details>

<details><summary><code>vendor.json</code></summary>

<!-- proteus-file path="vendor.json" part="1" of="1" rev="r2" -->
```json
{
  "files": {
    "wam/tone.wasm": {
      "source": "npm:@proteus-samples/tone@1.0.0/dist/tone.wasm",
      "license": "MIT",
      "sha256": "6886e86f25f5e4989756cf530dbcd5425503ee57345bb579f72746d3150ff0d2"
    }
  }
}

```

</details>

<details><summary><code>wam/tone.wasm</code> (binary, as base64)</summary>

<!-- proteus-file path="wam/tone.wasm" part="1" of="1" rev="r2" encoding="base64" -->
```text
AGFzbQEAAAAAhQIEZGF0YQABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJico
KSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9AQUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVpbXF1eX2Bh
YmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4SFhoeIiYqLjI2Oj5CRkpOUlZaXmJma
m5ydnp+goaKjpKWmp6ipqqusra6vsLGys7S1tre4ubq7vL2+v8DBwsPExcbHyMnKy8zNzs/Q0dLT
1NXW19jZ2tvc3d7f4OHi4+Tl5ufo6err7O3u7/Dx8vP09fb3+Pn6+/z9/v8=
```

</details>