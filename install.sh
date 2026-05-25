#!/bin/bash
# ============================================================
# install.sh — Installerar C1S3Upload på din Mac
# ============================================================
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DST="/Applications/C1S3Upload.app"
CONFIG="$HOME/.c1s3upload.json"
SCRIPT="$DIR/C1S3Upload.applescript"
CORE="$DIR/C1S3Upload.app/Contents/MacOS/c1s3upload_core.sh"
CONFIG_TEMPLATE="$DIR/config-template.json"

echo "╔══════════════════════════════════════╗"
echo "║   C1S3Upload — Installation          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Kompilera AppleScript-appen ───────────────────────────
echo "→ Kompilerar C1S3Upload.app..."
if [ -d "$APP_DST" ]; then
  rm -rf "$APP_DST"
fi
osacompile -o "$APP_DST" "$SCRIPT"
echo "  ✓ App kompilerad: $APP_DST"

# ── Kopiera in upload-core-skriptet ──────────────────────
echo "→ Kopierar uppladdningsskript..."
cp "$CORE" "$APP_DST/Contents/MacOS/c1s3upload_core.sh"
chmod +x "$APP_DST/Contents/MacOS/c1s3upload_core.sh"
echo "  ✓ c1s3upload_core.sh installerat"

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
  /usr/bin/python3 -c "
import json
with open('$CONFIG_TEMPLATE') as f:
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
echo "  1. Öppna $CONFIG och fyll i dina uppgifter"
echo "  2. Capture One → Process Recipe → Open With → välj /Applications/C1S3Upload.app"
echo ""
echo "Logg: ~/Library/Logs/C1S3Upload.log"
echo "════════════════════════════════════════"
