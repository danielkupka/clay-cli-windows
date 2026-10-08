#!/usr/bin/env bash
set -euo pipefail
shim_bin=$(cygpath -u "$1")
native_bin=$(cygpath -u "$2")
export PATH="$shim_bin:$native_bin:$PATH"
unset MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL
hash -r
[[ "$(command -v clay)" == "$shim_bin/clay" ]] || { echo 'Extensionless shim not found' >&2; exit 1; }
set +e
actual=$(clay 'two words' '{"nested":{"name":"A B"}}' '' '*.txt' '/tmp/input.json' '/usr/local/bin/clay-windows' 'https://example.com/a?b=c&d=e')
status=$?
set -e
actual=$(printf '%s' "$actual" | tr -d '\r')
expected=$(printf '%s\n' 'MSYS=1' 'argc=13' 'arg=-d' 'arg=Ubuntu-24.04' 'arg=-u' 'arg=test-user$' 'arg=--exec' 'arg=/usr/local/bin/clay-windows' 'arg=two words' 'arg={"nested":{"name":"A B"}}' 'arg=' 'arg=*.txt' 'arg=/tmp/input.json' 'arg=/usr/local/bin/clay-windows' 'arg=https://example.com/a?b=c&d=e')
[[ "$status" == 23 ]] || { echo "Wrong exit status: $status" >&2; exit 1; }
[[ "$actual" == "$expected" ]] || { printf 'Argument/environment mismatch:\n%s\n' "$actual" >&2; exit 1; }
echo 'Git Bash command discovery, native MSYS boundary, argument quoting, and exit code passed.'
