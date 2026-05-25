#!/bin/bash
# ============================================================
# c1s3upload_core.sh — Uppladdningslogik för C1S3Upload
# Anropas av C1S3Upload AppleScript-appen
#
# Argument: $1=titel $2=klient $3 $4 ... = filsökvägar
# ============================================================

set -euo pipefail

LOG="$HOME/Library/Logs/C1S3Upload.log"
CONFIG="$HOME/.c1s3upload.json"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# ── Läs argument ──────────────────────────────────────────
TITLE="${1:-}"
CLIENT="${2:-}"
PREFIX_ARG="${3:-}"
shift 3 2>/dev/null || true

# ── Kontrollera config ────────────────────────────────────
if [ ! -f "$CONFIG" ]; then
  log "FEL: Konfigurationsfilen $CONFIG saknas."
  exit 1
fi

# ── Läs config ────────────────────────────────────────────
_cfg() {
  /usr/bin/python3 -c "
import json, sys
try:
    d = json.load(open('$CONFIG'))
    v = d.get('$1', '$2')
    print(str(v).strip())
except:
    print('$2')
"
}

ACCESS_KEY=$(_cfg access_key "")
SECRET_KEY=$(_cfg secret_key "")
BUCKET=$(_cfg bucket "")
REGION=$(_cfg region "auto")
ENDPOINT=$(_cfg endpoint "")
# Prefix: använd det som skickades från dialogen, annars från config
if [ -n "$PREFIX_ARG" ]; then
  PREFIX="$PREFIX_ARG"
else
  PREFIX=$(_cfg prefix "")
fi
THUMB_SIZE=$(_cfg thumb_size "800")
THUMBS=$(_cfg thumbs "true")
YEAR=$(date +%Y)

ENDPOINT="${ENDPOINT%/}"

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ] || [ -z "$BUCKET" ] || [ -z "$ENDPOINT" ]; then
  log "FEL: access_key, secret_key, bucket och endpoint måste vara ifyllda i $CONFIG"
  exit 2
fi

TOTAL=$#
log "========================================"
log "Galleri: \"$TITLE\" | Klient: \"$CLIENT\" | År: $YEAR"
log "Startar uppladdning av $TOTAL fil(er)"
log "Bucket: $BUCKET | Prefix: $PREFIX"
log "========================================"

# ── Content-Type ──────────────────────────────────────────
content_type() {
  local ext="${1##*.}"
  ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    jpg|jpeg) echo "image/jpeg" ;;
    png)      echo "image/png" ;;
    tif|tiff) echo "image/tiff" ;;
    webp)     echo "image/webp" ;;
    gif)      echo "image/gif" ;;
    *)        echo "application/octet-stream" ;;
  esac
}

# ── Ladda upp fil ─────────────────────────────────────────
upload_file() {
  local path="$1" key="$2" ctype="$3"
  local url="${ENDPOINT}/${BUCKET}/${key}"
  local code
  code=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" \
    --aws-sigv4 "aws:amz:${REGION}:s3" \
    --user "${ACCESS_KEY}:${SECRET_KEY}" \
    -T "$path" \
    -H "Content-Type: ${ctype}" \
    "$url")
  if [[ "$code" =~ ^2 ]]; then
    log "  ✓ $key (HTTP $code)"
  else
    log "  ✗ $key (HTTP $code)"
    return 1
  fi
}

# ── Ladda upp sträng ──────────────────────────────────────
upload_string() {
  local content="$1" key="$2" ctype="$3"
  local url="${ENDPOINT}/${BUCKET}/${key}"
  local tmp
  tmp=$(mktemp /tmp/c1s3_XXXXXX)
  printf '%s' "$content" > "$tmp"
  local code
  code=$(/usr/bin/curl -sS -k -o /dev/null -w "%{http_code}" \
    --aws-sigv4 "aws:amz:${REGION}:s3" \
    --user "${ACCESS_KEY}:${SECRET_KEY}" \
    -T "$tmp" \
    -H "Content-Type: ${ctype}" \
    "$url")
  rm -f "$tmp"
  if [[ "$code" =~ ^2 ]]; then
    log "  ✓ $key (HTTP $code)"
  else
    log "  ✗ $key (HTTP $code)"
  fi
}

# ── Loopa filer ───────────────────────────────────────────
UPLOADED=0
FAILED=0

for FILE in "$@"; do
  [ -f "$FILE" ] || { log "VARNING: finns inte: $FILE"; ((FAILED++)) || true; continue; }
  FNAME=$(basename "$FILE")
  KEY="${PREFIX}${FNAME}"
  CTYPE=$(content_type "$FNAME")
  log "Fil: $FNAME"

  if upload_file "$FILE" "$KEY" "$CTYPE"; then
    ((UPLOADED++)) || true
  else
    ((FAILED++)) || true
    continue
  fi

  if [ "$THUMBS" = "true" ]; then
    THUMB=$(mktemp /tmp/c1s3_thumb_XXXXXX.jpg)
    if /usr/bin/sips -Z "$THUMB_SIZE" "$FILE" --out "$THUMB" >/dev/null 2>&1; then
      upload_file "$THUMB" "${PREFIX}thumbnails/${FNAME}" "image/jpeg" || true
    else
      log "  VARNING: sips misslyckades för $FNAME"
    fi
    rm -f "$THUMB"
  fi
done

# ── meta.json ─────────────────────────────────────────────
JSON=$(/usr/bin/python3 -c "
import json, sys
print(json.dumps({'title': sys.argv[1], 'client': sys.argv[2], 'year': sys.argv[3]}, ensure_ascii=False))
" "$TITLE" "$CLIENT" "$YEAR")
upload_string "$JSON" "${PREFIX}meta.json" "application/json"

log "========================================"
log "Klart! Uppladdade: $UPLOADED  Misslyckades: $FAILED"
log "========================================"

# Returnera antal misslyckade som exit-kod
exit $FAILED
