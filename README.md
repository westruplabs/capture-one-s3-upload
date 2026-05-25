# C1S3Upload — Capture One → S3 / Cloudflare R2

Laddar upp exporterade bilder från **Capture One** direkt till **Amazon S3** eller **Cloudflare R2**, skapar thumbnails automatiskt och skriver en `meta.json`-fil för varje galleri.

---

## Hur det fungerar

Capture One har en funktion i Process Recipe som heter **"Open With"** — efter export skickar C1 alla utmatade filer till ett externt program. Det här paketet är en macOS-app (`C1S3Upload.app`) som tar emot filerna, visar en dialog för att välja kategori och fylla i gallerinamn och klientnamn, laddar upp bilderna via `curl --aws-sigv4` och skapar thumbnails med inbyggda `sips`.

```
Capture One → Process Recipe (JPEG/TIFF) → C1S3Upload.app → S3 / R2
```

---

## Dialogflöde

När Capture One exporterar bilder visas tre dialogrutor:

1. **Kategori** — välj mellan `commissions`, `landscapes` eller `observations`
2. **Gallerinamn** — används som undermapp i bucketen, t.ex. `audi-2026`
3. **Klientnamn** — sparas i `meta.json`

Resultatet hamnar i bucketen under t.ex. `commissions/audi-2026/`.

---

## Installation

### 1. Kör installationsskriptet

```bash
cd C1S3Upload
chmod +x install.sh
./install.sh
```

Skriptet kompilerar `C1S3Upload.app` och kopierar den till `/Applications`, samt skapar en konfigurationsmall på `~/.c1s3upload.json`.

### 2. Fyll i konfigurationen

Öppna `~/.c1s3upload.json` i valfri texteditor:

```bash
open -e ~/.c1s3upload.json
```

```json
{
  "access_key":  "DIN_ACCESS_KEY",
  "secret_key":  "DIN_SECRET_KEY",
  "bucket":      "ditt-bucket-namn",
  "region":      "auto",
  "endpoint":    "https://DITT_ACCOUNT_ID.r2.cloudflarestorage.com",
  "prefix":      "",
  "thumbs":      true,
  "thumb_size":  800
}
```

| Fält | Beskrivning |
|------|-------------|
| `access_key` | AWS/R2 Access Key ID |
| `secret_key` | AWS/R2 Secret Access Key |
| `bucket` | Bucket-namnet |
| `region` | `auto` för R2, eller t.ex. `eu-north-1` för AWS |
| `endpoint` | Hela URL:en till S3-endpointen (utan trailing slash) |
| `thumbs` | `true` = skapa thumbnail, `false` = hoppa över |
| `thumb_size` | Maxbredd/höjd på thumbnail i pixlar |

> **Cloudflare R2:** Gå till Cloudflare Dashboard → R2 → din bucket → Settings → kopiera **S3 API**-endpointen.

---

## Inställningar i Capture One

### Konfigurera Process Recipe

1. Öppna **Output → Process Recipes** (⌘+K)
2. Skapa ett nytt recept eller öppna ett befintligt
3. Välj **JPEG** som format (85–95 %)
4. Under fliken **Open With**:
   - Aktivera **"Open With"**
   - Klicka **"..."** och välj `/Applications/C1S3Upload.app`
5. Spara receptet

> **Viktigt:** Se till att Process Recipe pekar på `/Applications/C1S3Upload.app` och inte på en kopia i en annan mapp.

### Exportera

Markera bilder → **Process** (⌘+D).

Tre dialogrutor visas — välj kategori, fyll i gallerinamn och klientnamn. Bilderna laddas upp och du får en macOS-notis när det är klart.

---

## Mappstruktur i bucketen

```
commissions/audi-2026/
├── IMG_1234.jpg
├── IMG_1235.jpg
├── …
├── meta.json
└── thumbnails/
    ├── IMG_1234.jpg
    └── …
```

### meta.json-format

```json
{
  "title": "audi-2026",
  "client": "Klintberg Nilehn",
  "year": "2026"
}
```

---

## Logfil

Alla händelser loggas till:

```
~/Library/Logs/C1S3Upload.log
```

Visa i terminalen:

```bash
tail -f ~/Library/Logs/C1S3Upload.log
```

---

## Felsökning

| Problem | Lösning |
|---------|---------|
| Inga dialoger visas | Kontrollera att C1:s Process Recipe pekar på `/Applications/C1S3Upload.app` |
| Ingen uppladdning sker | Kontrollera loggen — config saknas eller är felaktig |
| HTTP 403 / SignatureDoesNotMatch | Kontrollera `access_key`, `secret_key` och `region` |
| HTTP 400 / BadRequest | Kontrollera att `endpoint` inte har trailing slash |
| "App är skadad" / Gatekeeper | Kör: `xattr -cr /Applications/C1S3Upload.app` i terminalen |

---

## Krav

- macOS 12 (Monterey) eller senare
- Capture One 23 eller senare
- `curl` med `--aws-sigv4`-stöd (inbyggt från macOS 12.3+)
- Python 3 (inbyggt i macOS)

---

## Licens

MIT — samma som [lightroom-s3-upload](https://github.com/westruplabs/lightroom-s3-upload)

© Peter Westrup / [westruplabs](https://github.com/westruplabs)
