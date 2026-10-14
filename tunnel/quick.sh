#!/usr/bin/env bash
# Tunnel kilat anonim (tanpa login / tanpa domain) — untuk demo & pribadi.
# Memberi URL publik https://xxx.trycloudflare.com ke service lokal.
# Pemakaian: scripts/tunnel-quick.sh [PORT]   (default 3001 = web)
set -euo pipefail
PORT="${1:-3001}"
BIN="${CLOUDFLARED_BIN:-cloudflared}"
exec "$BIN" tunnel --url "http://localhost:${PORT}"
