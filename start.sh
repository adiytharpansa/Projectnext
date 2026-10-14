#!/usr/bin/env bash
# Projectnext start.sh — install deps, build bila perlu, tulis deployment
# output, lalu serve API di foreground pada PORT (default 3000).
set -euo pipefail
cd "$(dirname "$0")"

PORT="${PORT:-3000}"
export PORT
WEB_DIR="${OPENCODE_WEB_DIR:-/home/runner/work/_temp/omgithub-web}"
PROJECT_ROOT="$PWD"

/usr/bin/time -p test -f package.json
if [[ -f package-lock.json ]]; then
  /usr/bin/time -p npm ci --no-audit --no-fund
else
  /usr/bin/time -p npm install --no-audit --no-fund
fi

needs_build=false
if [[ ! -f dist/index.js ]]; then
  needs_build=true
elif [[ -n "$(find src api -name '*.ts' -newer dist/index.js 2>/dev/null)" ]]; then
  needs_build=true
fi
if [[ "$needs_build" == true ]]; then
  /usr/bin/time -p npm run build
fi

# Artefak statis untuk deployment-output (validator butuh directory/index.html
# di dalam PROJECT_DIR). API tetap diserve Express dari dist/.
/usr/bin/time -p cp public/index.html dist/index.html
/usr/bin/time -p mkdir -p "$WEB_DIR"
/usr/bin/time -p env PROJECT_ROOT="$PROJECT_ROOT" WEB_DIR="$WEB_DIR" node -e \
  "require('fs').writeFileSync(process.env.WEB_DIR + '/deployment-output.json', JSON.stringify({ project: process.env.PROJECT_ROOT, directory: process.env.PROJECT_ROOT + '/dist' }))"

/usr/bin/time -p echo "serving projectnext from $PROJECT_ROOT/dist on port $PORT"
exec node dist/index.js
