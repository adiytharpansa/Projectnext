#!/usr/bin/env bash
# Siapkan proyek Flutter: buat folder platform (android/ios) yang sengaja
# tidak di-commit, lalu patch izin internet & orientasi.
#
#   cd mobile && ./setup.sh
#
# Aman dijalankan berulang (idempoten).
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "✗ Flutter SDK tidak ditemukan di PATH. Pasang dari https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

PLATFORMS="${PLATFORMS:-android,ios}"   # mis. PLATFORMS=web ./setup.sh

echo "▶ flutter create --platforms $PLATFORMS (hanya menambah file yang belum ada)…"
flutter create . \
  --project-name anilab \
  --org com.projectnext \
  --platforms "$PLATFORMS" \
  >/dev/null

# ── Android ──────────────────────────────────────────────────────────────
M=android/app/src/main/AndroidManifest.xml
if [ -f "$M" ]; then
  # Izin internet (template Flutter hanya menambahkannya di debug/profile).
  if ! grep -q 'android.permission.INTERNET' "$M"; then
    perl -0pi -e 's#(\s*)<application#$1<uses-permission android:name="android.permission.INTERNET"/>$1<application#' "$M"
  fi
  # Izinkan http:// (server lokal / IP LAN) — hapus bila backend sudah HTTPS.
  if ! grep -q 'usesCleartextTraffic' "$M"; then
    perl -0pi -e 's#<application#<application\n        android:usesCleartextTraffic="true"#' "$M"
  fi
  # Nama aplikasi
  perl -0pi -e 's#android:label="anilab"#android:label="Anilab"#' "$M"
  echo "✓ AndroidManifest dipatch (INTERNET, cleartext, label)"
fi

# ── iOS ──────────────────────────────────────────────────────────────────
P=ios/Runner/Info.plist
if [ -f "$P" ]; then
  if ! grep -q 'NSAppTransportSecurity' "$P"; then
    perl -0pi -e 's#</dict>\s*</plist>\s*$#\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n</dict>\n</plist>\n#' "$P"
  fi
  perl -0pi -e 's#<string>anilab</string>#<string>Anilab</string>#g' "$P"
  echo "✓ Info.plist dipatch (ATS untuk http://, nama)"
fi

echo "▶ flutter pub get…"
flutter pub get

cat <<'EOF'

Selesai. Jalankan:
  flutter run                       # perangkat/emulator yang aktif
  flutter run -d chrome             # (opsional) web — video_player web hanya mendukung HLS di Safari
  flutter build apk --release       # APK Android

Atur alamat backend saat onboarding atau di tab Profil → Server API.
EOF
