#!/bin/bash
# ============================================================
# install-tools.sh — Gör hjälpskripten körbara var du än står
#
#   ./install-tools.sh
#
# Lägger genvägar i /usr/local/bin så att du kan skriva
#   edit-order commissions
#   move-folder commissions/x architecture/x
# från vilken mapp som helst i terminalen.
# ============================================================

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="/usr/local/bin"
TOOLS=(edit-order move-folder)

echo "╔══════════════════════════════════════╗"
echo "║   C1S3Upload — Verktygsgenvägar      ║"
echo "╚══════════════════════════════════════╝"
echo
echo "Skript hämtas från:"
echo "  $DIR"
echo

# ── Se till att /usr/local/bin finns och går att skriva i ──
SUDO=""
if [ ! -d "$BIN" ]; then
  echo "→ Skapar $BIN (kräver ditt lösenord)"
  sudo mkdir -p "$BIN"
fi
if [ ! -w "$BIN" ]; then
  echo "→ $BIN kräver administratörsrättigheter, du får ange lösenord"
  SUDO="sudo"
fi

# ── Skapa genvägar ────────────────────────────────────────
for t in "${TOOLS[@]}"; do
  SRC="$DIR/$t.sh"
  if [ ! -f "$SRC" ]; then
    echo "  ! hoppar över $t — $SRC saknas"
    continue
  fi
  chmod +x "$SRC"
  $SUDO ln -sf "$SRC" "$BIN/$t"
  echo "  ✓ $t"
done

echo
echo "════════════════════════════════════════"
echo "Klart! Nu fungerar det här var du än står:"
echo
echo "  edit-order commissions"
echo "  edit-order architecture"
echo "  move-folder commissions/stangby architecture/stangby"
echo
echo "Genvägarna pekar på skripten i mappen ovan, så när jag"
echo "uppdaterar dem slår ändringarna igenom direkt — du"
echo "behöver inte köra det här igen."
echo "════════════════════════════════════════"
