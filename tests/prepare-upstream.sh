#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
preparer="$project_root/scripts/prepare-upstream.sh"

if [[ ! -x "$preparer" ]]; then
  echo "upstream preparer is missing or not executable: $preparer" >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/talos-bluetooth-prepare.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

if "$preparer" unsupported "$test_root/unsupported" >/dev/null 2>&1; then
  echo "upstream preparer accepted an unsupported version" >&2
  exit 1
fi

mkdir "$test_root/existing"

if "$preparer" v1.13.8 "$test_root/existing" >/dev/null 2>&1; then
  echo "upstream preparer accepted an existing destination" >&2
  exit 1
fi

if "$preparer" v1.13.8 / >/dev/null 2>&1; then
  echo "upstream preparer accepted the filesystem root" >&2
  exit 1
fi

fixture="$test_root/fixture"
mock_bin="$test_root/bin"
fake_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p \
  "$fixture/scripts" \
  "$fixture/versions" \
  "$fixture/patches/upstream/pkgs" \
  "$fixture/patches/upstream/extensions" \
  "$fixture/patches/upstream/talos" \
  "$mock_bin"
cp "$preparer" "$fixture/scripts/prepare-upstream.sh"

cat > "$fixture/scripts/validate-source.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
chmod +x "$fixture/scripts/validate-source.sh"

cat > "$fixture/versions/upstream.env" <<EOF
TALOS_COMMIT=$fake_commit
PKGS_COMMIT=$fake_commit
EXTENSIONS_COMMIT=$fake_commit
EOF

printf 'patch\n' > "$fixture/patches/upstream/pkgs/0001.patch"
printf 'patch\n' > "$fixture/patches/upstream/extensions/0001.patch"
printf 'patch\n' > "$fixture/patches/upstream/extensions/0002.patch"
printf 'patch\n' > "$fixture/patches/upstream/talos/0001.patch"

cat > "$mock_bin/git" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == init ]]; then
  mkdir -p "${@: -1}/.git"
  exit 0
fi

[[ "$1" == -C ]] || exit 0
command=$3
shift 3

case "$command" in
  rev-parse)
    printf '%s\n' "$FAKE_COMMIT"
    ;;
  apply)
    [[ "${1:-}" != --check ]] || shift
    (($# == 1))
    ;;
esac
SCRIPT
chmod +x "$mock_bin/git"

if ! PATH="$mock_bin:$PATH" FAKE_COMMIT="$fake_commit" \
  "$fixture/scripts/prepare-upstream.sh" upstream "$test_root/prepared" >/dev/null 2>&1; then
  echo "upstream preparer did not apply dependent patches sequentially" >&2
  exit 1
fi

echo "upstream preparation argument tests passed"
