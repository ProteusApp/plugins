-- release: the rust-analyzer release the Tools panel downloads when no working rust-analyzer
-- is on the PATH. Each platform's file is pinned by the SHA-256 checksum GitHub lists for it.

local VERSION = '2026-09-28'
local BASE = 'https://github.com/rust-lang/rust-analyzer/releases/download/'
  .. VERSION
  .. '/'

---@type Proteus.ToolRelease
return {
  version = VERSION,
  from = 'github.com/rust-lang/rust-analyzer',
  assets = {
    ['windows-x86_64'] = {
      url = BASE .. 'rust-analyzer-x86_64-pc-windows-msvc.zip',
      sha256 = 'ad78fb368525404c6ac09c4bba33e90797902ce1f5a17db0925c695cae096ccc',
      file = 'rust-analyzer.exe',
    },
    ['windows-aarch64'] = {
      url = BASE .. 'rust-analyzer-aarch64-pc-windows-msvc.zip',
      sha256 = 'f63c7fc9a00a7e863b21b5e0b77cda7ff61aaa9f6f83b0affa5bbb525be7c43c',
      file = 'rust-analyzer.exe',
    },
    ['linux-x86_64'] = {
      url = BASE .. 'rust-analyzer-x86_64-unknown-linux-gnu.gz',
      sha256 = '23f711d86b5f826e22886f01d7355dc01e0f4c1357dafa29710a95b903b48c85',
    },
    ['linux-aarch64'] = {
      url = BASE .. 'rust-analyzer-aarch64-unknown-linux-gnu.gz',
      sha256 = '03bad9c3dabb0f07a2678d5f9f8f1575a3742ea141506e14b3a26b42a1f896f3',
    },
    ['macos-x86_64'] = {
      url = BASE .. 'rust-analyzer-x86_64-apple-darwin.gz',
      sha256 = 'd032c0eb75e4597cc8ffc35ea4cdbd9eecc8341936b6edac6749e679fc3f0682',
    },
    ['macos-aarch64'] = {
      url = BASE .. 'rust-analyzer-aarch64-apple-darwin.gz',
      sha256 = '54ec873d8996e2c127d758bf45d4eacb6d3371dae4f6f6d5d3f05cedbae5fd59',
    },
  },
}
