#!/usr/bin/env bash
set -euo pipefail

VENV_BIN="$1"
shift

expand() {
  for arg in "$@"; do
    if [ "$arg" = "-r" ]; then
      continue
    elif [ -f "$arg" ]; then
      grep -v '^#' "$arg" | grep -v '^[[:space:]]*$'
    else
      echo "$arg"
    fi
  done
}

mapfile -t PACKAGES < <(expand "$@")

installed=()
missing=()

for pkg in "${PACKAGES[@]}"; do
  name=$(echo "$pkg" | sed -E 's/[<>=~!].*//')
  if "$VENV_BIN/pip" show "$name" >/dev/null 2>&1; then
    installed+=("$name")
  else
    missing+=("$pkg")
  fi
done

if [ "${#installed[@]}" -gt 0 ]; then
  echo "[PIP] already satisfied, skipping: ${installed[*]}"
fi

if [ "${#missing[@]}" -gt 0 ]; then
  echo "[PIP] not found, installing now: ${missing[*]}"
  "$VENV_BIN/pip" install "${missing[@]}"
  echo "[PIP] install complete for: ${missing[*]}"
else
  echo "[PIP] every package already satisfied, nothing to install"
fi
