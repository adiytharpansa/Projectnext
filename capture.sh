#!/usr/bin/env bash
# Projectnext capture.sh — buka CAPTURE_URL di browser milik sendiri, tunggu
# konten ter-render, simpan final-desktop.png + final-mobile.png di CAPTURE_DIR.
# Keluar 75 untuk kegagalan infra sementara (navigasi/browser), 1 untuk cacat
# skrip/rendering. Tidak menyentuh server aplikasi.
set -euo pipefail
cd "$(dirname "$0")"

URL="${CAPTURE_URL:?Set CAPTURE_URL to the preview URL}"
OUT="${CAPTURE_DIR:?Set CAPTURE_DIR to the evidence directory}"
SESSION="projectnext-capture-$$"

is_transient() {
  grep -qiE 'timeout|timed out|refused|reset by peer|econn|enotfound|eai_again|ehost|enet|socket hang|net::|target closed|browser.*(closed|disconnect|crashed|not installed)|playwright.*(launch|executable)|executable.*missing|install-browser|xvfb|display|cannot open display' <<<"$1"
}

close_browser() {
  /usr/bin/time -p playwright-cli -s="$SESSION" close >/dev/null 2>&1 || true
}
trap close_browser EXIT

/usr/bin/time -p mkdir -p "$OUT"

# 1) Klasifikasi status HTTP dulu (browser tetap dipakai untuk capture).
set +e
/usr/bin/time -p curl --silent --show-error --location --max-time 25 --output /dev/null --write-out '%{http_code}' "$URL" >"$OUT/.http-code" 2>"$OUT/.curl-err"
curl_rc=$?
set -e
http_code="$(cat "$OUT/.http-code" 2>/dev/null || echo 000)"
if [[ "$curl_rc" -ne 0 || "$http_code" == 000 ]]; then
  echo "capture: URL tidak terjangkau (curl rc=$curl_rc): $(cat "$OUT/.curl-err")" >&2
  exit 75
fi
if [[ "$http_code" == 408 || "$http_code" == 429 || "$http_code" == 5* ]]; then
  echo "capture: HTTP sementara $http_code" >&2
  exit 75
fi
if [[ "$http_code" == 4* ]]; then
  echo "capture: HTTP $http_code (cacat aplikasi/preview)" >&2
  exit 1
fi
echo "capture: HTTP $http_code, membuka browser…"

# 2) Buka URL di browser sesi sendiri.
set +e
open_log="$(/usr/bin/time -p timeout 120 playwright-cli -s="$SESSION" open "$URL" 2>&1)"
open_rc=$?
set -e
if [[ $open_rc -ne 0 ]]; then
  echo "capture: browser open gagal (rc=$open_rc): $open_log" >&2
  if [[ $open_rc -eq 124 ]] || is_transient "$open_log"; then exit 75; fi
  exit 1
fi

# 3) Tunggu konten ter-render, maks ~30 dtk.
#    playwright-cli mencetak markdown ("### Result" + baris hasil ber-quote),
#    jadi ambil baris SETELAH "### Result" — bukan baris terakhir output.
#    Format probe: contentType|innerTextLen|outerHTMLLen (cth: application/json|946|1161).
probe_page() {
  timeout 30 playwright-cli -s="$SESSION" eval \
    "() => document.contentType + '|' + (document.body ? document.body.innerText.length : -1) + '|' + document.documentElement.outerHTML.length" 2>/dev/null \
    | awk '/^### Result$/{getline; print}' | tr -d ' "'
}

rendered=0
probe=""
for _ in $(seq 1 15); do
  set +e
  probe="$(probe_page)"
  probe_rc=$?
  set -e
  echo "$probe" >"$OUT/.probe"
  if [[ $probe_rc -ne 0 || -z "$probe" ]]; then
    echo "capture: eval browser gagal (rc=$probe_rc)" >&2
    exit 75
  fi
  ct="${probe%%|*}"
  rest="${probe#*|}"
  inner="${rest%%|*}"
  hlen="${rest##*|}"
  if [[ "$inner" =~ ^[0-9]+$ && "$inner" -gt 0 ]]; then
    rendered=1
    break
  fi
  # Non-HTML (mis. JSON API) yang dirender viewer browser kadang
  # menyembunyikan teks di shadow DOM — outerHTML substansial = rendered.
  if [[ "$ct" != "text/html" && "$hlen" =~ ^[0-9]+$ && "$hlen" -ge 200 ]]; then
    rendered=1
    break
  fi
  /usr/bin/time -p sleep 2
done
if [[ "$rendered" -eq 0 ]]; then
  echo "capture: halaman kosong setelah menunggu (probe=$probe) (cacat rendering)" >&2
  exit 1
fi
echo "capture: rendered, probe=$probe"

check_png() {
  local f="$1"
  [[ -f "$f" ]] || { echo "capture: $f tidak ada" >&2; return 1; }
  local size
  size="$(wc -c <"$f")"
  [[ "$size" -ge 24 ]] || { echo "capture: $f terlalu kecil ($size b)" >&2; return 1; }
  [[ "$(head -c 8 "$f" | od -An -tx1 | tr -d ' \n')" == "89504e470d0a1a0a" ]] || { echo "capture: $f bukan PNG" >&2; return 1; }
}

# 4) Desktop 1440x900.
/usr/bin/time -p timeout 60 playwright-cli -s="$SESSION" resize 1440 900
/usr/bin/time -p sleep 1
/usr/bin/time -p timeout 120 playwright-cli -s="$SESSION" screenshot --filename "$OUT/final-desktop.png"
check_png "$OUT/final-desktop.png" || exit 1

# 5) Mobile 390x844.
/usr/bin/time -p timeout 60 playwright-cli -s="$SESSION" resize 390 844
/usr/bin/time -p sleep 1
/usr/bin/time -p timeout 120 playwright-cli -s="$SESSION" screenshot --filename "$OUT/final-mobile.png"
check_png "$OUT/final-mobile.png" || exit 1

echo "capture: OK desktop+mobile di $OUT"
