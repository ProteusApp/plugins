## Hello World 1.0.0

Says hello in the status bar.

Plugin id: `hello.world`. Files: `init.lua`, `README.md`, `lib/util.lua`.

Proteus opened this issue with **Plugins > Publish Plugin**. A workflow turns it into a PR, and a maintainer reviews the code there.

<details><summary>Manifest</summary>

<!-- proteus-manifest -->
```json
{"format":2,"revision":"r1","id":"hello.world","name":"Hello World","description":"Says hello in the status bar.","version":"1.0.0","files":["init.lua","README.md","lib/util.lua"]}
```

</details>

<details><summary><code>init.lua</code></summary>

<!-- proteus-file path="init.lua" part="1" of="1" rev="r1" -->
```lua
return {
  name = 'Hello',
  description = 'Says “hello”.',
}

```

</details>

<details><summary><code>README.md</code></summary>

<!-- proteus-file path="README.md" part="1" of="1" rev="r1" -->
````markdown
# Hello

```lua
print('hi')
```

````

</details>

<details><summary><code>lib/util.lua</code></summary>

<!-- proteus-file path="lib/util.lua" part="1" of="1" rev="r1" -->
```lua
return 1
```

</details>