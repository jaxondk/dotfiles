#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# Find all stow packages (directories that aren't .git or .github)
mapfile -t packages < <(find . -maxdepth 1 -mindepth 1 -type d \
  ! -name '.git' \
  ! -name '.github' \
  -exec basename {} \; | sort)

if [ ${#packages[@]} -eq 0 ]; then
  echo "No stow packages found." >&2
  exit 0
fi

# Default to restow (-R) if no args provided
if [ "$#" -eq 0 ]; then
  set -- -R
fi

echo "Running stow with args: $*"
echo "Packages: ${packages[*]}"
stow "$@" "${packages[@]}"
