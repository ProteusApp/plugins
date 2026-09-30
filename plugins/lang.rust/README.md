# Rust

Rust support for the Proteus code editor, built on rust-analyzer, rustfmt and Cargo.

## What it does

- **Completion, hover help and go to definition.** rust-analyzer answers while code is typed. F12 or Ctrl+click jumps to where a name is defined, in the crate or in the standard library.
- **Problems.** Mistakes show as underlines and in the Problems panel (Ctrl+Shift+M). After each save, rust-analyzer checks the crate with `cargo check`, or with clippy when `rust.check_command` is `clippy`.
- **Formatting.** Format Document (Shift+Alt+F) runs rustfmt with the edition from the nearest `Cargo.toml`, and with the crate's `rustfmt.toml` when it has one. A `-- lang=rust` block inside a Lua string formats the same way.
- **The Cargo panel.** A panel in the bottom dock runs Check, Build, Run, Test and Clippy in a real terminal, in colour, in the crate of the file in front. The same jobs are in the palette under **Cargo**, and in the **Run** menu.
- **Rust's TOML files.** `Cargo.toml`, `.cargo/config.toml`, `rustfmt.toml` and `rust-toolchain.toml` get their JSON schemas as file associations. With `lang.toml` running, they get completion, hover help and checks.

The language server starts when the first Rust file opens. A folder with a crate at its top or one level down starts it at once, such as a Tauri app with its crate in `src-tauri`.

## What it needs

Cargo and rustfmt come with Rust from [rustup.rs](https://rustup.rs). rust-analyzer does not need installing. When no working copy is on the PATH, the plugin offers to download the official release, checked against its pinned checksum. rustup's own `rust-analyzer` on the PATH only works after `rustup component add rust-analyzer`, and the plugin tells the two apart.

The **Tools** panel shows each program's state, version and log, with buttons to start, stop, download and look again.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `rust.analyzer_enabled` | `true` | Runs rust-analyzer. |
| `rust.analyzer_path` | empty | A rust-analyzer to use. Empty takes the PATH, then a download. |
| `rust.check_command` | `check` | What runs after each save: `check` or `clippy`. |
| `rust.rustfmt_enabled` | `true` | Formats Rust files with rustfmt. |

A project can set any of them for itself in `.proteus/settings.json`.

## How it is built

Each file in `lib/` does one job and stays short. `server.lua` puts rust-analyzer behind the editor with the app's shared `lsp.client`. `program.lua` finds a working rust-analyzer, and `release.lua` pins the download for each platform. `crates.lua` reads `Cargo.toml` files, `rustfmt.lua` formats, and `cargo.lua` with `cargo_style.lua` draws the Cargo panel.
