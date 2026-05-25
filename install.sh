#!/bin/bash
# ============================================================
# install.sh — Installerar C1S3Upload på din Mac
# ============================================================
set -e

APP_SRC="$(cd "$(dirname "$0")" && pwd)/C1S3Upload.app"
APP_DST="/Applications/C1S3Upload.app"
CONFIG="$HOME/.c1s3upload.json"
CONFIG_TEMPLATE="$(cd "$(dirname "$0")" && pwd)/config-template.json"

echo "╔══════════════════════════════════════╗"
echo "║   C1S3Upload — Installation          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Installera appen ──────────────────────────────────────
echo "→ Kopierar C1S3Upload.app till /Applications..."
if [ -d "$APP_DST" ]; then
  echo "  (ersätter befintlig installation)"
  rm -rf "$APP_DST"
fi
cp -R "$APP_SRC" "$APP_DST"
echo "  ✓ App installerad: $APP_DST"

# ── Gör körbar ────────────────────────────────────────────
chmod +x "$APP_DST/Contents/MacOS/C1S3Upload"

# ── Registrera appen med Launch Services ─────────────────
echo "→ Registrerar appen med macOS..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_DST" 2>/dev/null || true
echo "  ✓ Registrerad"

# ── Skapa konfigurationsfil om den inte finns ─────────────
if [ -f "$CONFIG" ]; then
  echo "→ Konfigurationsfilen $CONFIG finns redan, hoppar över."
else
  echo "→ Skapar konfigurationsmall: $CONFIG"
  cp "$CONFIG_TEMPLATE" "$CONFIG"
  # Ta bort kommentarfältet (inte giltig JSON i alla parsers)
  python3 -c "
import json
with open('$CONFIG') as f:
    d = json.load(f)
d.pop('_comment', None)
with open('$CONFIG', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print('  ✓ Skapad')
"
fi

echo ""
echo "════════════════════════════════════════"
echo "Installation klar!"
echo ""
echo "Nästa steg:"
echo "  1. Öppna $CONFIG i en texteditor"
echo "  2. Fyll i access_key, secret_key, bucket, endpoint och prefix"
echo "  3. Öppna Capture One → Process Recipe → Open With → välj /Applications/C1S3Upload.app"
echo ""
echo "Logg: ~/Library/Logs/C1S3Upload.log"
echo "════════════════════════════════════════"
