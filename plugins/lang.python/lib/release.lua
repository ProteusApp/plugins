-- release: the Ruff release the Tools panel downloads when no Ruff is on the PATH. Each file
-- is pinned by its SHA-256 checksum. Ruff ships Linux and macOS only as `.tar.gz` files, which
-- the download cannot open, so only Windows has a download. Elsewhere `pip install ruff`,
-- `uv tool install ruff` or `brew install ruff` puts it on the PATH.

local VERSION = '0.16.10'
local BASE = 'https://github.com/astral-sh/ruff/releases/download/'
  .. VERSION
  .. '/'

---@type Proteus.ToolRelease
return {
  version = VERSION,
  from = 'github.com/astral-sh/ruff',
  assets = {
    ['windows-x86_64'] = {
      url = BASE .. 'ruff-x86_64-pc-windows-msvc.zip',
      sha256 = '6b90457fbd249923db196044d5f3c26e4f7cefacc769c26fd52520fa033f736e',
      file = 'ruff.exe',
    },
    ['windows-aarch64'] = {
      url = BASE .. 'ruff-aarch64-pc-windows-msvc.zip',
      sha256 = 'cde60dbdf2697144474e6d87b8b51b73bb1fd218f4c180acb40abbd3b659d56f',
      file = 'ruff.exe',
    },
  },
}
