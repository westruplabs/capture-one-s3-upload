#!/bin/bash
# ============================================================
# edit-order.sh — Redigera sorteringsordning i R2
#
#   ./edit-order.sh architecture                  ordning på MAPPARNA
#   ./edit-order.sh architecture/lundsstadshall   ordning på BILDERNA
#
# Du redigerar en vanlig textfil — ett namn per rad, inga
# citattecken eller kommatecken. Skriptet sköter JSON-biten.
#
# Utan snedstreck skrivs <sektion>/_order.json, som styr i vilken
# ordning mapparna visas. Med snedstreck skrivs mappens meta.json,
# där "order" styr bildernas ordning.
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

# Worker:n visar vilken ordning sajten använder just nu.
# Cloudflare avvisar curls standard-User-Agent, därav den här.
WORKER_URL="https://peterwestrup-images-api.super-limit-c89e.workers.dev"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

urlenc() {
  /usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1],safe='/'))" "$1"
}

# Hitta skriptets verkliga plats, även via symlänk
SELF="$0"
while [ -L "$SELF" ]; do
  LINK=$(readlink "$SELF")
  case "$LINK" in
    /*) SELF="$LINK" ;;
    *)  SELF="$(dirname "$SELF")/$LINK" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

WORKDIR="$SCRIPT_DIR/order"
mkdir -p "$WORKDIR"
SAFE=$(echo "$TARGET" | tr '/' '_')
JSON_IN="$WORKDIR/.${SAFE}_hamtad.json"
TXT="$WORKDIR/${SAFE}.txt"
TXT_ORIG="$WORKDIR/.${SAFE}_original.txt"
JSON_OUT="$WORKDIR/.${SAFE}_klar.json"

# ── Hämta befintlig fil ──────────────────────────────────
echo "Hämtar $KEY ..."
CODE=$(/usr/bin/curl -sS -k -o "$JSON_IN" -w "%{http_code}" "${SIGV4[@]}" \
  "${ENDPOINT}/${BUCKET}/$(urlenc "$KEY")")

if [[ "$CODE" =~ ^2 ]]; then
  echo "  ✓ hämtad"
else
  echo "  (finns inte än — skapas)"
  if [ "$MODE" = section ]; then printf '[]' > "$JSON_IN"; else printf '{}' > "$JSON_IN"; fi
fi

# ── Vad som faktiskt finns i R2 just nu ──────────────────
if [ "$MODE" = section ]; then
  CURRENT=$(/usr/bin/curl -sS -f -A "$UA" "${WORKER_URL}/${SECTION}" 2>/dev/null \
    | /usr/bin/python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for f in (d.get('$SECTION') or d.get('folders') or []):
        if f.get('id'):
            print(f['id'])
except Exception:
    pass
" || true)

  if [ -z "$CURRENT" ]; then
    CURRENT=$(/usr/bin/curl -sS -k "${SIGV4[@]}" \
        "${ENDPOINT}/${BUCKET}?list-type=2&prefix=$(urlenc "${SECTION}/")&delimiter=/&max-keys=1000" \
      | /usr/bin/python3 -c "
import sys, re, html
names = []
for p in re.findall(r'<Prefix>(.*?)</Prefix>', sys.stdin.read(), re.S):
    n = html.unescape(p).rstrip('/').split('/')[-1]
    if n and n not in ('$SECTION', 'thumbs'):
        names.append(n)
for n in sorted(set(names)):
    print(n)
")
  fi
else
  CURRENT=$(/usr/bin/curl -sS -k "${SIGV4[@]}" \
      "${ENDPOINT}/${BUCKET}?list-type=2&prefix=$(urlenc "${SECTION}/${FOLDER}/")&max-keys=1000" \
    | /usr/bin/python3 -c "
import sys, re, html
prefix = '${SECTION}/${FOLDER}/'
for k in re.findall(r'<Key>(.*?)</Key>', sys.stdin.read(), re.S):
    k = html.unescape(k)
    rest = k[len(prefix):] if k.startswith(prefix) else k
    if '/' in rest:
        continue
    if not re.search(r'\.(jpe?g|png|tiff?|webp)\$', rest, re.I):
        continue
    if rest.lower().startswith('cover.'):
        continue
    print(rest)
")
  if [ -z "$CURRENT" ]; then
    echo "FEL: hittade inga bilder under ${SECTION}/${FOLDER}/"
    exit 1
  fi
fi

# ── Bygg textfilen du redigerar ──────────────────────────
printf '%s\n' "$CURRENT" | /usr/bin/python3 -c "
import sys, json

mode   = '$MODE'
target = '$TARGET'
folder = '''$FOLDER'''
names  = [l.strip() for l in sys.stdin if l.strip()]

try:
    data = json.load(open('$JSON_IN'))
except Exception:
    data = [] if mode == 'section' else {}

if mode == 'section':
    saved = data if isinstance(data, list) else []
else:
    saved = data.get('order', []) if isinstance(data, dict) else []
    if not isinstance(saved, list):
        saved = []

# Behåll sparad ordning, lägg tillkomna namn sist
ordered  = [n for n in saved if n in names]
ordered += [n for n in names if n not in ordered]

lines = []
if mode == 'section':
    lines += [
        '# Ordningen på mapparna i ' + target + '.',
        '# Översta raden visas först. Flytta raderna som du vill.',
        '# Rader som börjar med # struntar skriptet i.',
        '',
    ]
else:
    meta = data if isinstance(data, dict) else {}
    lines += [
        '# Bildordning i ' + target + '.',
        '# Översta raden visas först. cover.jpg ligger alltid före dessa.',
        '# Raderna med kolon är projektets uppgifter — ändra fritt.',
        '',
        'titel: '  + (meta.get('title')  or folder),
        'klient: ' + (meta.get('client') or ''),
        'år: '     + (meta.get('year')   or ''),
        '',
    ]
lines += ordered
open('$TXT', 'w').write('\n'.join(lines) + '\n')
"

cp "$TXT" "$TXT_ORIG"

# ── Visa och öppna ───────────────────────────────────────
echo
echo "Nuvarande $LABEL:"
/usr/bin/python3 -c "
import re
n = 0
for line in open('$TXT'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    if re.match(r'^(titel|klient|år|ar|title|client|year)\s*:', line, re.I):
        continue
    n += 1
    print('  %d. %s' % (n, line))
"
echo
echo "Flytta raderna till den ordning du vill ha."
echo "Inga citattecken eller kommatecken behövs."
echo

if [ -n "${EDITOR:-}" ]; then
  "$EDITOR" "$TXT"
else
  open -e "$TXT"
  echo "Filen är öppnad i TextEdit."
  echo
  read -r -p "Spara (⌘S), kom tillbaka hit och tryck Enter... " _
fi

if cmp -s "$TXT" "$TXT_ORIG"; then
  echo
  echo "Inga ändringar hittades — inget laddas upp."
  echo "(Glömde du spara med ⌘S innan du tryckte Enter?)"
  exit 0
fi

# ── Textfil tillbaka till JSON ───────────────────────────
if ! /usr/bin/python3 -c "
import json, sys, re

mode  = '$MODE'
meta  = {}
order = []

for raw in open('$TXT'):
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    m = re.match(r'^(titel|klient|år|ar|title|client|year)\s*:(.*)\$', line, re.I)
    if mode == 'folder' and m:
        k = m.group(1).lower()
        v = m.group(2).strip()
        if   k in ('titel', 'title'):   meta['title']  = v
        elif k in ('klient', 'client'): meta['client'] = v
        else:                           meta['year']   = v
        continue
    order.append(line)

if not order:
    print('  Listan är tom — inget att spara.', file=sys.stderr)
    raise SystemExit(1)

dupes = sorted({n for n in order if order.count(n) > 1})
if dupes:
    print('  Samma namn förekommer flera gånger: ' + ', '.join(dupes), file=sys.stderr)
    raise SystemExit(1)

if mode == 'section':
    out = order
    print('  ✓ %d mappar' % len(order))
else:
    out = {
        'title':  meta.get('title', ''),
        'client': meta.get('client', ''),
        'year':   meta.get('year', ''),
        'order':  order,
    }
    print('  ✓ %d bilder' % len(order))

json.dump(out, open('$JSON_OUT', 'w'), indent=2, ensure_ascii=False)
"; then
  echo
  echo "FEL: inget laddas upp. Rätta filen och kör om."
  exit 1
fi

echo
echo "Ny ordning:"
/usr/bin/python3 -c "
import json
d = json.load(open('$JSON_OUT'))
items = d if isinstance(d, list) else d['order']
for i, name in enumerate(items, 1):
    print('  %d. %s' % (i, name))
"

# ── Ladda upp ────────────────────────────────────────────
echo
echo "Laddar upp $KEY ..."
CODE=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" -X PUT "${SIGV4[@]}" \
  -H "Content-Type: application/json" \
  -T "$JSON_OUT" \
  "${ENDPOINT}/${BUCKET}/$(urlenc "$KEY")")

if [[ "$CODE" =~ ^2 ]]; then
  echo "  ✓ uppladdad (HTTP $CODE)"
  echo
  echo "Ordningen slår igenom inom några minuter."
  echo "Ladda om sidan med ⌘⇧R för att se den direkt."
else
  echo "  ✗ misslyckades (HTTP $CODE)"
  exit 1
fi
