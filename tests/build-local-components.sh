#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
builder="$project_root/scripts/build-local-components.sh"

if [[ ! -x "$builder" ]]; then
  echo "local component builder is missing or not executable: $builder" >&2
  exit 1
fi

if "$builder" >/dev/null 2>&1; then
  echo "local component builder accepted missing arguments" >&2
  exit 1
fi

if "$builder" unsupported /tmp registry namespace tag >/dev/null 2>&1; then
  echo "local component builder accepted an unsupported version" >&2
  exit 1
fi

echo "local component build argument tests passed"
