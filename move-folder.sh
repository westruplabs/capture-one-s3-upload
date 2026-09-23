#!/bin/bash
# ============================================================
# move-folder.sh — Flytta en mapp mellan sektioner i R2/S3
#
#   ./move-folder.sh commissions/stangby architecture/stangby
#
# Kopierar alla filer (inklusive thumbs/ och meta.json) till den
# nya platsen och raderar originalen först när allt kopierats.
# Läser uppgifter från ~/.c1s3upload.json.
# ============================================================

set -euo pipefail

CONFIG="$HOME/.c1s3upload.json"

if [ $# -ne 2 ]; then
  echo "Användning: $0 <från-mapp> <till-mapp>"
  echo "Exempel:    $0 commissions/stangby architecture/stangby"
  exit 1
fi

SRC="${1%/}/"
DST="${2%/}/"

if [ ! -f "$CONFIG" ]; then
  echo "FEL: $CONFIG saknas."
  exit 1
fi

# ── Läs config ────────────────────────────────────────────
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

if [ -z "$ACCESS_KEY" ] || [ -z "$BUCKET" ] || [ -z "$ENDPOINT" ]; then
  echo "FEL: kontrollera access_key, bucket och endpoint i $CONFIG"
  exit 1
fi

SIGV4=(--aws-sigv4 "aws:amz:${REGION}:s3" --user "${ACCESS_KEY}:${SECRET_KEY}")

urlenc() {
  /usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1],safe='/'))" "$1"
}

# ── Lista alla nycklar under källprefixet ────────────────
echo "Läser $SRC ..."
KEYS=$(
  /usr/bin/curl -sS -k "${SIGV4[@]}" \
    "${ENDPOINT}/${BUCKET}?list-type=2&prefix=$(urlenc "$SRC")&max-keys=1000" \
  | /usr/bin/python3 -c "
import sys, re, html
xml = sys.stdin.read()
for k in re.findall(r'<Key>(.*?)</Key>', xml, re.S):
    print(html.unescape(k))
"
)

if [ -z "$KEYS" ]; then
  echo "Inga filer hittades under $SRC — kontrollera stavningen."
  exit 1
fi

COUNT=$(echo "$KEYS" | wc -l | tr -d ' ')

echo
echo "Hittade $COUNT fil(er):"
echo "$KEYS" | sed 's|^|  |' | head -8
[ "$COUNT" -gt 8 ] && echo "  ... och $((COUNT - 8)) till"
echo
echo "Flyttas till: $DST"
echo
read -r -p "Fortsätt? (j/n) " SVAR
[ "$SVAR" = "j" ] || { echo "Avbrutet."; exit 0; }

# ── Kopiera ───────────────────────────────────────────────
echo
echo "Kopierar..."
FAILED=0
while IFS= read -r key; do
  [ -n "$key" ] || continue
  newkey="${DST}${key#"$SRC"}"
  code=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" -X PUT "${SIGV4[@]}" \
    -H "x-amz-copy-source: /${BUCKET}/$(urlenc "$key")" \
    "${ENDPOINT}/${BUCKET}/$(urlenc "$newkey")")
  if [[ "$code" =~ ^2 ]]; then
    echo "  ✓ $newkey"
  else
    echo "  ✗ $newkey (HTTP $code)"
    FAILED=$((FAILED + 1))
  fi
done <<< "$KEYS"

if [ "$FAILED" -gt 0 ]; then
  echo
  echo "$FAILED fil(er) kunde inte kopieras — inget raderas."
  echo "Originalen ligger kvar under $SRC"
  exit 1
fi

# ── Radera originalen ────────────────────────────────────
echo
echo "Alla filer kopierade. Raderar originalen under $SRC ..."
while IFS= read -r key; do
  [ -n "$key" ] || continue
  code=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" -X DELETE "${SIGV4[@]}" \
    "${ENDPOINT}/${BUCKET}/$(urlenc "$key")")
  [[ "$code" =~ ^2 ]] && echo "  ✓ raderad: $key" || echo "  ✗ kunde inte radera: $key (HTTP $code)"
done <<< "$KEYS"

echo
echo "════════════════════════════════════════"
echo "Klart! $COUNT fil(er) flyttade till $DST"
echo
echo "Kom ihåg:"
echo "  • Ta bort mappen ur ${SRC%%/*}/_order.json"
echo "  • Lägg till den i ${DST%%/*}/_order.json"
echo "  • Lägg en redirect om den gamla adressen varit publik"
echo "════════════════════════════════════════"
