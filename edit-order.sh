#!/bin/bash
# ============================================================
# edit-order.sh — Redigera sorteringsordning i R2
#
#   ./edit-order.sh architecture                  ordning på MAPPARNA
#   ./edit-order.sh architecture/lundsstadshall   ordning på BILDERNA
#
# Utan snedstreck redigeras <sektion>/_order.json, som styr i
# vilken ordning mapparna visas i sektionen.
#
# Med snedstreck redigeras mappens meta.json, där fältet "order"
# styr bildernas ordning. Fältet fylls i åt dig med mappens
# faktiska filnamn, så du bara behöver flytta rader.
#
# Filen öppnas i din texteditor och laddas upp när du sparat.
# ============================================================

set -euo pipefail

CONFIG="$HOME/.c1s3upload.json"

if [ $# -ne 1 ]; then
  echo "Användning: $0 <sektion>[/<mapp>]"
  echo
  echo "  $0 architecture                 ordning på mapparna"
  echo "  $0 architecture/lundsstadshall  ordning på bilderna"
  exit 1
fi

TARGET="${1%/}"
if [[ "$TARGET" == */* ]]; then
  MODE=folder
  SECTION="${TARGET%%/*}"
  FOLDER="${TARGET#*/}"
  KEY="${SECTION}/${FOLDER}/meta.json"
  LABEL="bildordningen i $FOLDER"
else
  MODE=section
  SECTION="$TARGET"
  FOLDER=""
  KEY="${SECTION}/_order.json"
  LABEL="mappordningen i $SECTION"
fi

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
SAFE=$(echo "$TARGET" | tr '/' '_')
TMP="$WORKDIR/${SAFE}.json"
ORIG="$WORKDIR/.${SAFE}_original.json"

urlenc() {
  /usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1],safe='/'))" "$1"
}

# ── Hämta befintlig fil ──────────────────────────────────
echo "Hämtar $KEY ..."
CODE=$(/usr/bin/curl -sS -k -o "$TMP" -w "%{http_code}" "${SIGV4[@]}" \
  "${ENDPOINT}/${BUCKET}/$(urlenc "$KEY")")

if [[ "$CODE" =~ ^2 ]]; then
  echo "  ✓ hämtad"
elif [ "$MODE" = section ]; then
  # Ingen _order.json än — bygg en av sektionens mappar
  echo "  (finns inte än — skapar en med nuvarande mappar)"
  /usr/bin/curl -sS -k "${SIGV4[@]}" \
    "${ENDPOINT}/${BUCKET}?list-type=2&prefix=$(urlenc "${SECTION}/")&delimiter=/&max-keys=1000" \
  | /usr/bin/python3 -c "
import sys, re, json, html
prefixes = re.findall(r'<Prefix>(.*?)</Prefix>', sys.stdin.read(), re.S)
ids = []
for p in prefixes:
    name = html.unescape(p).rstrip('/').split('/')[-1]
    if name and name != '$SECTION' and name != 'thumbs':
        ids.append(name)
print(json.dumps(sorted(set(ids)), indent=2, ensure_ascii=False))
" > "$TMP"
else
  # Ingen meta.json än — skapa en tom som fylls på nedan
  echo "  (finns inte än — skapar en)"
  printf '{}' > "$TMP"
fi

# I mappläge: fyll "order" med mappens faktiska filnamn
if [ "$MODE" = folder ]; then
  FILES=$(/usr/bin/curl -sS -k "${SIGV4[@]}" \
      "${ENDPOINT}/${BUCKET}?list-type=2&prefix=$(urlenc "${SECTION}/${FOLDER}/")&max-keys=1000" \
    | /usr/bin/python3 -c "
import sys, re, html
for k in re.findall(r'<Key>(.*?)</Key>', sys.stdin.read(), re.S):
    print(html.unescape(k))
")
  if [ -z "$FILES" ]; then
    echo "FEL: hittade inga filer under ${SECTION}/${FOLDER}/"
    exit 1
  fi

  printf '%s' "$FILES" | /usr/bin/python3 -c "
import sys, json, re, os

meta_path = '$TMP'
prefix = '${SECTION}/${FOLDER}/'

keys = [l.strip() for l in sys.stdin if l.strip()]
names = []
for k in keys:
    rest = k[len(prefix):] if k.startswith(prefix) else k
    if '/' in rest:                       # thumbs/ och liknande
        continue
    if not re.search(r'\.(jpe?g|png|tiff?|webp)\$', rest, re.I):
        continue
    if rest.lower().startswith('cover.'):  # cover ligger alltid först
        continue
    names.append(rest)

try:
    meta = json.load(open(meta_path))
    if not isinstance(meta, dict):
        meta = {}
except Exception:
    meta = {}

meta.setdefault('title', '${FOLDER}')
meta.setdefault('client', '')
meta.setdefault('year', '')

# Behåll den ordning som redan står, lägg nya filer sist
old = [n for n in meta.get('order', []) if n in names]
meta['order'] = old + [n for n in sorted(names) if n not in old]

order = meta.pop('order')
out = dict(meta)
out['order'] = order
json.dump(out, open(meta_path, 'w'), indent=2, ensure_ascii=False)
"
fi

cp "$TMP" "$ORIG"

# ── Öppna i editor ───────────────────────────────────────
echo
echo "Nuvarande $LABEL:"
/usr/bin/python3 -c "
import json
try:
    d = json.load(open('$TMP'))
    items = d['order'] if isinstance(d, dict) else d
    for i, name in enumerate(items, 1):
        print(f'  {i}. {name}')
except Exception as e:
    print('  (kunde inte läsas:', e, ')')
"
echo
if [ "$MODE" = section ]; then
  echo "Lägg mapparna i den ordning du vill ha dem på sidan."
else
  echo "Flytta raderna i \"order\" till den ordning du vill ha bilderna."
  echo "Titel, klient och år kan du också ändra här."
fi
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
import json
d = json.load(open('$TMP'))
if '$MODE' == 'section':
    assert isinstance(d, list), 'filen ska innehålla en lista'
    print('  ✓ giltig JSON,', len(d), 'mappar')
else:
    assert isinstance(d, dict), 'filen ska innehålla ett objekt'
    o = d.get('order', [])
    assert isinstance(o, list), '\"order\" ska vara en lista'
    print('  ✓ giltig JSON,', len(o), 'bilder')
"; then
  echo
  echo "FEL: filen är inte giltig JSON — inget laddas upp."
  if [ "$MODE" = section ]; then
    echo 'Den ska se ut så här:  ["mapp-ett", "mapp-tva"]'
  else
    echo 'Den ska se ut så här:  { "title": "...", "order": ["bild1.jpg"] }'
  fi
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
try:
    d = json.load(open('$TMP'))
    items = d['order'] if isinstance(d, dict) else d
    for i, name in enumerate(items, 1):
        print(f'  {i}. {name}')
except Exception as e:
    print('  (kunde inte läsas:', e, ')')
"

# ── Ladda upp ────────────────────────────────────────────
echo
echo "Laddar upp $KEY ..."
CODE=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" -X PUT "${SIGV4[@]}" \
  -H "Content-Type: application/json" \
  -T "$TMP" \
  "${ENDPOINT}/${BUCKET}/$(urlenc "$KEY")")

if [[ "$CODE" =~ ^2 ]]; then
  echo "  ✓ uppladdad (HTTP $CODE)"
  echo
  echo "Ordningen slår igenom inom några minuter."
  echo "Ladda om sidan med ⌘+Shift+R för att se den direkt."
else
  echo "  ✗ misslyckades (HTTP $CODE)"
  exit 1
fi
