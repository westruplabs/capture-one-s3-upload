#!/bin/bash
# ============================================================
# edit-order.sh — Redigera sorteringsordningen för en sektion
#
#   ./edit-order.sh commissions
#   ./edit-order.sh architecture
#
# Hämtar <sektion>/_order.json från R2, öppnar den i din
# texteditor och laddar upp den igen när du sparat och stängt.
# Saknas filen skapas den med sektionens mappar förifyllda.
# ============================================================

set -euo pipefail

CONFIG="$HOME/.c1s3upload.json"

if [ $# -ne 1 ]; then
  echo "Användning: $0 <sektion>"
  echo "Exempel:    $0 commissions"
  exit 1
fi

SECTION="${1%/}"
KEY="${SECTION}/_order.json"

[ -f "$CONFIG" ] || { echo "FEL: $CONFIG saknas."; exit 1; }

_cfg() {
  /usr/bin/python3 -c "
import json
d = json.load(open('$CONFIG'))
print(str(d.get('$1', '$2')).strip())
"
}

ACCESS_KEY=$(_cfg access_key "")
SECRET_KEY=$(_cfg secret_key "")
BUCKET=$(_cfg bucket "")
REGION=$(_cfg region "auto")
ENDPOINT=$(_cfg endpoint "")
ENDPOINT="${ENDPOINT%/}"

[ -n "$ACCESS_KEY" ] && [ -n "$BUCKET" ] && [ -n "$ENDPOINT" ] \
  || { echo "FEL: kontrollera access_key, bucket och endpoint i $CONFIG"; exit 1; }

SIGV4=(--aws-sigv4 "aws:amz:${REGION}:s3" --user "${ACCESS_KEY}:${SECRET_KEY}")

# Hitta skriptets verkliga plats, även om det anropas via symlänk
SELF="$0"
while [ -L "$SELF" ]; do
  LINK=$(readlink "$SELF")
  case "$LINK" in
    /*) SELF="$LINK" ;;
    *)  SELF="$(dirname "$SELF")/$LINK" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

# Filerna sparas lokalt så att de överlever och fungerar som kopia
WORKDIR="$SCRIPT_DIR/order"
mkdir -p "$WORKDIR"
TMP="$WORKDIR/${SECTION}_order.json"
ORIG="$WORKDIR/.${SECTION}_original.json"

# ── Hämta befintlig fil ──────────────────────────────────
echo "Hämtar $KEY ..."
CODE=$(/usr/bin/curl -sS -k -o "$TMP" -w "%{http_code}" "${SIGV4[@]}" \
  "${ENDPOINT}/${BUCKET}/${KEY}")

if [[ "$CODE" =~ ^2 ]]; then
  echo "  ✓ hämtad"
else
  # Finns inte — bygg en startlista av sektionens mappar
  echo "  (finns inte än — skapar en med nuvarande mappar)"
  /usr/bin/curl -sS -k "${SIGV4[@]}" \
    "${ENDPOINT}/${BUCKET}?list-type=2&prefix=${SECTION}/&delimiter=/&max-keys=1000" \
  | /usr/bin/python3 -c "
import sys, re, json, html
xml = sys.stdin.read()
prefixes = re.findall(r'<Prefix>(.*?)</Prefix>', xml, re.S)
ids = []
for p in prefixes:
    p = html.unescape(p).rstrip('/')
    name = p.split('/')[-1]
    if name and name != '$SECTION' and name != 'thumbs':
        ids.append(name)
print(json.dumps(sorted(set(ids)), indent=2, ensure_ascii=False))
" > "$TMP"
fi

cp "$TMP" "$ORIG"

# ── Öppna i editor ───────────────────────────────────────
echo
echo "Nuvarande ordning:"
/usr/bin/python3 -c "
import json
try:
    for i, name in enumerate(json.load(open('$TMP')), 1):
        print(f'  {i}. {name}')
except Exception:
    print('  (kunde inte läsas som lista)')
"
echo
echo "Lägg mapparna i den ordning du vill ha dem på sidan."
echo

if [ -n "${EDITOR:-}" ]; then
  # En terminaleditor blockerar tills du stänger den
  "$EDITOR" "$TMP"
else
  open -e "$TMP"
  echo "Filen är öppnad i TextEdit."
  echo
  read -r -p "Spara (⌘S), kom tillbaka hit och tryck Enter... " _
fi

# ── Kontrollera att det är giltig JSON ───────────────────
if ! /usr/bin/python3 -c "
import json, sys
d = json.load(open('$TMP'))
assert isinstance(d, list), 'filen måste innehålla en lista'
print('  ✓ giltig JSON,', len(d), 'mappar')
"; then
  echo
  echo "FEL: filen är inte giltig JSON — inget laddas upp."
  echo "Den ska se ut så här:  [\"mapp-ett\", \"mapp-tva\"]"
  exit 1
fi

if cmp -s "$TMP" "$ORIG"; then
  echo
  echo "Inga ändringar hittades — inget laddas upp."
  echo "(Glömde du spara med ⌘S innan du tryckte Enter?)"
  exit 0
fi

echo
echo "Ny ordning:"
/usr/bin/python3 -c "
import json
for i, name in enumerate(json.load(open('$TMP')), 1):
    print(f'  {i}. {name}')
"

# ── Ladda upp ────────────────────────────────────────────
echo
echo "Laddar upp $KEY ..."
CODE=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" -X PUT "${SIGV4[@]}" \
  -H "Content-Type: application/json" \
  -T "$TMP" \
  "${ENDPOINT}/${BUCKET}/${KEY}")

if [[ "$CODE" =~ ^2 ]]; then
  echo "  ✓ uppladdad (HTTP $CODE)"
  echo
  echo "Ordningen slår igenom inom några minuter."
  echo "Ladda om sidan med ⌘+Shift+R för att se den direkt."
else
  echo "  ✗ misslyckades (HTTP $CODE)"
  exit 1
fi
