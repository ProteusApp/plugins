-- release: the ShellCheck and shfmt releases the Tools panel downloads when a program is not
-- on the PATH. Each file is pinned by its SHA-256 checksum, so a changed file is refused.
--
-- ShellCheck publishes a `.zip` for Windows, and a `.tar.xz` or `.tar.gz` for Linux and
-- macOS. The registry cannot unpack a tar file, so only Windows on Intel or AMD downloads
-- ShellCheck. shfmt publishes the program itself for each platform, with none for Windows on
-- ARM.

local SHELLCHECK_VERSION = 'v0.11.0'
local SHELLCHECK_BASE = 'https://github.com/koalaman/shellcheck/releases/download/'
  .. SHELLCHECK_VERSION
  .. '/'

local SHFMT_VERSION = 'v3.14.1'
local SHFMT_BASE = 'https://github.com/mvdan/sh/releases/download/'
  .. SHFMT_VERSION
  .. '/shfmt_'
  .. SHFMT_VERSION
  .. '_'

---@class LangShell.Releases
---@field shellcheck Proteus.ToolRelease
---@field shfmt Proteus.ToolRelease

---@type LangShell.Releases
return {
  shellcheck = {
    version = SHELLCHECK_VERSION,
    from = 'github.com/koalaman/shellcheck',
    assets = {
      ['windows-x86_64'] = {
        url = SHELLCHECK_BASE .. 'shellcheck-' .. SHELLCHECK_VERSION .. '.zip',
        sha256 = '8a4e35ab0b331c85d73567b12f2a444df187f483e5079ceffa6bda1faa2e740e',
        file = 'shellcheck.exe',
      },
    },
  },
  shfmt = {
    version = SHFMT_VERSION,
    from = 'github.com/mvdan/sh',
    assets = {
      ['windows-x86_64'] = {
        url = SHFMT_BASE .. 'windows_amd64.exe',
        sha256 = '13629ce28442ca80b6b5a819f7574ab39e1c28c6e26734ca816c9714e04851df',
      },
      ['linux-x86_64'] = {
        url = SHFMT_BASE .. 'linux_amd64',
        sha256 = '76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf',
      },
      ['linux-aarch64'] = {
        url = SHFMT_BASE .. 'linux_arm64',
        sha256 = '5f2db09dae91fca848f7adbdd014632e921a383863a2ad7e0450ad3aba0c6489',
      },
      ['macos-x86_64'] = {
        url = SHFMT_BASE .. 'darwin_amd64',
        sha256 = 'd33eee0da0f92835b3562e9767a05cee7e4eaeef47daa03bfd09da17b4b590a6',
      },
      ['macos-aarch64'] = {
        url = SHFMT_BASE .. 'darwin_arm64',
        sha256 = 'b7c872db63553ccffc7253aba3ed7d4885a27d83f1ba567b1138c6315a5847e5',
      },
    },
  },
}
