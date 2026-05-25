# C1S3Upload — Capture One → S3 / Cloudflare R2

Laddar upp exporterade bilder från **Capture One** direkt till **Amazon S3** eller **Cloudflare R2**, skapar thumbnails automatiskt och skriver en `meta.json`-fil för varje galleri.

---

## Hur det fungerar

Capture One har en funktion i Process Recipe som heter **"Open With"** — efter export skickar C1 alla utmatade filer till ett externt program. Det här paketet är en macOS-app (`C1S3Upload.app`) som tar emot filerna, laddar upp dem via `curl --aws-sigv4` och skapar thumbnails med inbyggda `sips`.

```
Capture One → Process Recipe (JPEG/TIFF) → C1S3Upload.app → S3 / R2
```

---

## Installation

### 1. Kör installationsskriptet

```bash
cd C1S3Upload
chmod +x install.sh
./install.sh
```

Skriptet kopierar `C1S3Upload.app` till `/Applications` och skapar en konfigurationsmall på `~/.c1s3upload.json`.

### 2. Fyll i konfigurationen

Öppna `~/.c1s3upload.json` i valfri texteditor:

```json
{
  "access_key":  "DIN_ACCESS_KEY",
  "secret_key":  "DIN_SECRET_KEY",
  "bucket":      "ditt-bucket-namn",
  "region":      "auto",
  "endpoint":    "https://DITT_ACCOUNT_ID.r2.cloudflarestorage.com",
  "prefix":      "galleri/projekt-namn/",
  "thumbs":      true,
  "thumb_size":  800,
  "title":       "Projektets titel",
  "client":      "Klientens namn",
  "year":        ""
}
```

| Fält | Beskrivning |
|------|-------------|
| `access_key` | AWS/R2 Access Key ID |
| `secret_key` | AWS/R2 Secret Access Key |
| `bucket` | Bucket-namnet |
| `region` | `auto` för R2, eller t.ex. `eu-north-1` för AWS |
| `endpoint` | Hela URL:en till S3-endpointen (utan trailing slash) |
| `prefix` | Sökväg i bucketen, t.ex. `galleri/brollop-2025/` (med trailing slash) |
| `thumbs` | `true` = skapa thumbnail, `false` = hoppa över |
| `thumb_size` | Maxbredd/höjd på thumbnail i pixlar |
| `title` | Galleriets titel — används i `meta.json` (lämna tomt för att hoppa) |
| `client` | Klientnamn till `meta.json` |
| `year` | År till `meta.json` — lämna tomt för innevarande år |

#### Cloudflare R2 — hitta din endpoint
1. Cloudflare Dashboard → R2 → din bucket → Settings
2. Kopiera **S3 API** endpoint, t.ex. `https://abc123.r2.cloudflarestorage.com`
3. Klistra in som `endpoint` (utan bucket-namn)

---

## Inställningar i Capture One

### Skapa/öppna en Process Recipe

1. **Output → Process Recipes** (eller ⌘+K)
2. Skapa en ny recipe eller välj en befintlig
3. Välj önskat filformat (JPEG rekommenderas, 85–95 %)
4. Under fliken **Open With**:
   - Aktivera **"Open With"**
   - Klicka **"..."** och välj `/Applications/C1S3Upload.app`
5. Spara receptet

### Exportera

Markera bilder → **Process** (⌘+D) — C1S3Upload laddar upp bilderna i bakgrunden.  
Du får en macOS-notis när uppladdningen är klar.

---

## Mappstruktur i bucketen

```
galleri/projekt-namn/
├── IMG_1234.jpg
├── IMG_1235.jpg
├── …
├── meta.json
└── thumbnails/
    ├── IMG_1234.jpg
    ├── IMG_1235.jpg
    └── …
```

### meta.json-format

```json
{
  "title": "Projektets titel",
  "client": "Klientens namn",
  "year": "2025"
}
```

---

## Logfil

Alla händelser loggas till:

```
~/Library/Logs/C1S3Upload.log
```

Öppna i **Console.app** eller terminalen:

```bash
tail -f ~/Library/Logs/C1S3Upload.log
```

---

## Byta projekt

Uppdatera bara `~/.c1s3upload.json` inför varje nytt galleri — ändra `prefix`, `title`, `client` och eventuellt `year`.

Om du vill ha flera configs kan du skapa ett litet hjälpskript som byter ut filen, t.ex.:

```bash
cp ~/.c1s3upload_brollop.json ~/.c1s3upload.json
```

---

## Felsökning

| Problem | Lösning |
|---------|---------|
| Ingen notis, inget händer | Kontrollera loggen — config saknas eller är felaktig |
| HTTP 403 / SignatureDoesNotMatch | Kontrollera att `access_key` och `secret_key` stämmer, att `region` matchar din bucket |
| HTTP 400 / BadRequest | Kontrollera att `endpoint` inte har trailing slash och inte innehåller bucket-namnet |
| Thumbnail skapas inte | `sips` är inbyggt i macOS — kontrollera att filen är JPEG/TIFF/PNG |
| "app är skadad" / Gatekeeper | Kör: `xattr -cr /Applications/C1S3Upload.app` i terminalen |

---

## Krav

- macOS 12 (Monterey) eller senare
- Capture One 23 eller senare
- `curl` med `--aws-sigv4`-stöd (inbyggt från macOS 12.3+, annars via Homebrew: `brew install curl`)
- Python 3 (inbyggt i macOS, används för JSON-parsning)

---

## Licens

MIT — samma som [lightroom-s3-upload](https://github.com/westruplabs/lightroom-s3-upload)

© Peter Westrup / [westruplabs](https://github.com/westruplabs)
