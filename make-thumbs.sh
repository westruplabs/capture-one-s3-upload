#!/bin/bash
# ============================================================
# make-thumbs.sh — Skapar thumbnails i efterhand
#
#   make-thumbs architecture
#   make-thumbs architecture/stangby
#   make-thumbs                     (alla sektioner)
#
# Letar upp bilder som saknar motsvarighet i thumbs/, hämtar
# originalet från R2, skalar med sips och laddar upp resultatet.
# Bilder som redan har en thumbnail hoppas över.
# ============================================================

set -euo pipefail

CONFIG="$HOME/.c1s3upload.json"
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
THUMB_SIZE=$(_cfg thumb_size "800")

[ -n "$ACCESS_KEY" ] && [ -n "$BUCKET" ] && [ -n "$ENDPOINT" ] \
  || { echo "FEL: kontrollera access_key, bucket och endpoint i $CONFIG"; exit 1; }

SIGV4=(--aws-sigv4 "aws:amz:${REGION}:s3" --user "${ACCESS_KEY}:${SECRET_KEY}")

urlenc() {
  /usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1],safe='/'))" "$1"
}

# ── Vilka prefix ska gås igenom ──────────────────────────
if [ $# -ge 1 ]; then
  PREFIXES=("${1%/}/")
else
  PREFIXES=("commissions/" "architecture/" "landscapes/" "observations/")
fi

TMPDIR_=$(mktemp -d)
trap 'rm -rf "$TMPDIR_"' EXIT

TOTAL_MADE=0
TOTAL_SKIP=0
TOTAL_FAIL=0

for PREFIX in "${PREFIXES[@]}"; do
  echo "──────────────────────────────────────────"
  echo "$PREFIX"

  # Hela listan under prefixet (S3 ger max 1000 per anrop)
  ALL=$(/usr/bin/curl -sS -k "${SIGV4[@]}" \
      "${ENDPOINT}/${BUCKET}?list-type=2&prefix=$(urlenc "$PREFIX")&max-keys=1000" \
    | /usr/bin/python3 -c "
import sys, re, html
for k in re.findall(r'<Key>(.*?)</Key>', sys.stdin.read(), re.S):
    print(html.unescape(k))
")

  [ -n "$ALL" ] || { echo "  (tom)"; continue; }

  # Befintliga thumbnails, för uppslag
  echo "$ALL" | grep '/thumbs/' > "$TMPDIR_/have" 2>/dev/null || : > "$TMPDIR_/have"

  # Originalbilder: hoppa över thumbs/ och icke-bilder
  ORIGINALS=$(echo "$ALL" \
    | grep -v '/thumbs/' \
    | grep -Ei '\.(jpg|jpeg|png|tif|tiff|webp)$' || true)

  [ -n "$ORIGINALS" ] || { echo "  inga bilder"; continue; }

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    dir=$(dirname "$key")
    name=$(basename "$key")
    thumb_key="${dir}/thumbs/${name}"

    if grep -Fxq "$thumb_key" "$TMPDIR_/have"; then
      TOTAL_SKIP=$((TOTAL_SKIP + 1))
      continue
    fi

    # Hämta originalet
    src="$TMPDIR_/src_$name"
    code=$(/usr/bin/curl -sS -k -o "$src" -w "%{http_code}" "${SIGV4[@]}" \
      "${ENDPOINT}/${BUCKET}/$(urlenc "$key")")
    if [[ ! "$code" =~ ^2 ]]; then
      echo "  ✗ kunde inte hämta $name (HTTP $code)"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      rm -f "$src"
      continue
    fi

    # Skala
    dst="$TMPDIR_/thumb_$name"
    if ! /usr/bin/sips -Z "$THUMB_SIZE" "$src" --out "$dst" >/dev/null 2>&1; then
      echo "  ✗ sips misslyckades för $name"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      rm -f "$src" "$dst"
      continue
    fi

    # Ladda upp
    code=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" "${SIGV4[@]}" \
      -T "$dst" -H "Content-Type: image/jpeg" \
      "${ENDPOINT}/${BUCKET}/$(urlenc "$thumb_key")")
    rm -f "$src" "$dst"

    if [[ "$code" =~ ^2 ]]; then
      echo "  ✓ $thumb_key"
      TOTAL_MADE=$((TOTAL_MADE + 1))
    else
      echo "  ✗ $thumb_key (HTTP $code)"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
  done <<< "$ORIGINALS"
done

echo "──────────────────────────────────────────"
echo "Klart!  skapade: $TOTAL_MADE   fanns redan: $TOTAL_SKIP   fel: $TOTAL_FAIL"
if [ "$TOTAL_MADE" -gt 0 ]; then
  echo
  echo "Kör 'python3 build.py' i new-site och pusha, så hänger sajten med."
fi
