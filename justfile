set positional-arguments

default:
    @just --list

install *args:
    yarn install "$@"

test *args:
    yarn test "$@"

check *args:
    yarn check "$@"

test-lua *args:
    node scripts/lua-test.mjs "$@"

lint: lint-style lint-selene lint-luals

lint-style *args:
    stylua --check plugins profiles contracts "$@"

lint-selene *args:
    selene plugins profiles "$@"
    selene --config tests.selene.toml plugins/*/tests contracts "$@"

lint-luals *args:
    node scripts/luals.mjs "$@"
