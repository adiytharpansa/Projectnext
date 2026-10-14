#!/usr/bin/env bash
# Once-per-worker prerequisites for Projectnext scripts.
# Dijalankan controller sekali per worker; bukan untuk build/capture.
set -euo pipefail

# Self-heal: pastikan Chromium milik playwright-cli tersedia (dibutuhkan
# capture.sh). Idempotent — playwright melewati unduhan bila sudah ada.
MARKER="$HOME/.local/share/omgithub-playwright/chromium-ready"
if [[ ! -f "$MARKER" ]]; then
  /usr/bin/time -p playwright-cli install-browser chromium
  /usr/bin/time -p mkdir -p "$(dirname "$MARKER")"
  /usr/bin/time -p touch "$MARKER"
fi
