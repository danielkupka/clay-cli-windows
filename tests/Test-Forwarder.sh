#!/usr/bin/env bash
set -euo pipefail
scripts=$1
fixture=$2
bash -n "$scripts/bootstrap.sh"
bash -n "$scripts/migrate.sh"
sh -n "$scripts/forwarder.sh"
sh -n "$scripts/quoted-forwarder.sh"

# The caller supplies a temporary directory. Exercise an executable path that
# contains spaces and an apostrophe, and preserve each original argument.
mkdir -p "$(dirname "$fixture")"
cat > "$fixture" <<'FIXTURE'
#!/bin/sh
printf '%s\n' "$@"
exit 23
FIXTURE
chmod +x "$fixture"
set +e
actual=$(sh "$scripts/quoted-forwarder.sh" 'two words' '{"nested":{"name":"A B"}}' '' '*.txt')
result=$?
set -e
expected=$(printf '%s\n' 'two words' '{"nested":{"name":"A B"}}' '' '*.txt')
[[ "$result" == 23 ]] || { echo 'Exit code was not preserved' >&2; exit 1; }
[[ "$actual" == "$expected" ]] || { echo 'Arguments changed' >&2; exit 1; }
echo 'Bash syntax, quoted executable, arguments, and exit-code checks passed.'
