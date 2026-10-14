#!/usr/bin/env bash
# Smoke test lokal: boot server, cek endpoint statis (tanpa scraping upstream).
set -euo pipefail
PORT="${PORT:-3000}"
BASE="http://localhost:${PORT}"
node dist/index.js & SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
sleep 3
echo "== / =="; curl -fsS "$BASE/" | head -c 400; echo
echo "== /api/health =="; curl -fsS "$BASE/api/health"; echo
echo "== /api/providers =="; curl -fsS "$BASE/api/providers"; echo
echo "== validation (400 expected) =="; curl -s -o /dev/null -w "%{http_code}\n" "$BASE/api/anime/gogo/search"; echo
echo "== unknown provider (404 expected) =="; curl -s -o /dev/null -w "%{http_code}\n" "$BASE/api/anime/xxx/search?query=a"; echo
echo "== proxy validation (400 expected) =="; curl -s -o /dev/null -w "%{http_code}\n" "$BASE/api/proxy"; echo
echo SMOKE_OK
