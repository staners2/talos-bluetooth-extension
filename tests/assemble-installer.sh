#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
assembler="$project_root/scripts/assemble-installer.sh"

if [[ ! -x "$assembler" ]]; then
  echo "installer assembler is missing or not executable: $assembler" >&2
  exit 1
fi

if "$assembler" >/dev/null 2>&1; then
  echo "installer assembler accepted missing arguments" >&2
  exit 1
fi

if "$assembler" unsupported /tmp registry namespace tag /tmp/out >/dev/null 2>&1; then
  echo "installer assembler accepted an unsupported version" >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/talos-bluetooth-assembler-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

prepared_root="$test_root/prepared"
fake_bin="$test_root/bin"
output_dir="$test_root/output"
mkdir -p "$prepared_root/extensions/_out" "$prepared_root/talos/.git" "$fake_bin"
mkdir -p "$prepared_root/extensions/.git"

while IFS=$'\t' read -r name source; do
  package_dir="$prepared_root/extensions/packages/$name"
  mkdir -p "$package_dir"
  printf 'metadata:\n  name: %s\n' "$name" > "$package_dir/manifest.yaml.tmpl"

  case "$source" in
    custom-kernel)
      printf 'dependencies:\n  - image: example/kernel:test\n' > "$package_dir/pkg.yaml"
      ;;
    custom-firmware)
      printf 'dependencies:\n  - image: example/linux-firmware:test\nsteps:\n  - install:\n      - install BT_RAM_CODE_MT7922_1_1_hdr.bin\n' > "$package_dir/pkg.yaml"
      ;;
    official)
      printf 'name: %s\n' "$name" > "$package_dir/pkg.yaml"
      ;;
  esac
done < <(yq -r '.extensions[] | [.name, .source] | @tsv' "$project_root/compatibility/target-node.yaml")

cat > "$prepared_root/extensions/_out/bldr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
expected_root=$(cd "$(dirname "$0")/.." && pwd)
[[ "$PWD" == "$expected_root" ]] || exit 1
target=
tag=
while (($# > 0)); do
  case "$1" in
    --target) target=$2; shift 2 ;;
    --build-arg) tag=${2#TAG=}; shift 2 ;;
    *) shift ;;
  esac
done
case "$target" in
  amdgpu) printf '20260810-%s\n' "$tag" ;;
  drbd) printf '9.3.3-%s\n' "$tag" ;;
  *) printf '%s\n' "$tag" ;;
esac
EOF
chmod +x "$prepared_root/extensions/_out/bldr"

cat > "$fake_bin/crane" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$ASSEMBLER_CRANE_LOG"
case "$1" in
  digest)
    ref=${!#}
    case "$ref" in
      */amdgpu:v1.14.0-bluetooth.2|*/drbd:v1.14.0-bluetooth.2) exit 1 ;;
    esac
    printf 'sha256:%064d\n' 1
    ;;
  pull)
    output=${!#}
    : > "$output"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/crane"

cat > "$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$ASSEMBLER_DOCKER_LOG"
case "$1" in
  load)
    echo 'Loaded image: fake-loaded:latest'
    ;;
  tag) exit 0 ;;
  pull) exit 1 ;;
  run)
    if [[ " $* " == *' --output-kind '* ]]; then
      exit 2
    fi
    volume=
    while (($# > 0)); do
      if [[ "$1" == --volume ]]; then
        volume=$2
        break
      fi
      shift
    done
    [[ -n "$volume" ]] || exit 1
    printf 'test installer\n' > "${volume%:/out}/installer-amd64.tar"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/docker"

export ASSEMBLER_CRANE_LOG="$test_root/crane.log"
export ASSEMBLER_DOCKER_LOG="$test_root/docker.log"

if ! PATH="$fake_bin:$PATH" \
  REGISTRY_CLIENT_ADDRESS=127.0.0.1:5000 \
  DOCKER_NETWORK=test-network \
  "$assembler" \
    v1.14.0 \
    "$prepared_root" \
    registry:5000 \
    namespace \
    v1.14.0-bluetooth.2 \
    "$output_dir" >/dev/null; then
  echo "installer assembler did not complete controlled assembly" >&2
  exit 1
fi

grep -Fq 'namespace/amdgpu:20260810-v1.14.0-bluetooth.2' "$ASSEMBLER_CRANE_LOG"
grep -Fq 'namespace/drbd:9.3.3-v1.14.0-bluetooth.2' "$ASSEMBLER_CRANE_LOG"
grep -Fq 'pull --insecure' "$ASSEMBLER_CRANE_LOG"
grep -Fq 'load --input' "$ASSEMBLER_DOCKER_LOG"
if grep -Eq '^pull([[:space:]]|$)' "$ASSEMBLER_DOCKER_LOG"; then
  echo "installer assembler asked Docker to pull from the HTTP registry" >&2
  exit 1
fi
[[ -s "$output_dir/installer-amd64.tar" ]]
[[ $(grep -c '^registry:5000/namespace/' "$output_dir/provenance.txt") -eq 8 ]]
grep -Fq 'registry:5000/namespace/mediatek-bluetooth-firmware@sha256:' \
  "$output_dir/provenance.txt"

echo "installer assembler argument tests passed"
