-- C1S3Upload — Capture One → S3 / Cloudflare R2
-- Tar emot filer från Capture One via "Open With" i Process Recipe

on open theFiles
    set logPath to (POSIX path of (path to home folder)) & "Library/Logs/C1S3Upload.log"
    set coreScript to "/Applications/C1S3Upload.app/Contents/MacOS/c1s3upload_core.sh"
    set fileCount to count of theFiles

    -- Debug: logga antal filer
    do shell script "echo '[" & (do shell script "date '+%Y-%m-%d %H:%M:%S'") & "] on open fick " & fileCount & " fil(er)' >> " & quoted form of logPath

    if fileCount is 0 then
        display notification "Inga filer mottogs från Capture One." with title "C1S3Upload" subtitle "Fel"
        return
    end if

    -- Dialog 1: Välj kategori
    set kategoriVal to choose from list {"commissions", "landscapes", "observations"} with title "C1S3Upload" with prompt "Välj kategori:" default items {"commissions"} without multiple selections allowed and empty selection allowed
    if kategoriVal is false then return
    set kategori to item 1 of kategoriVal

    -- Dialog 2: Gallerinamn (undermapp + titel i meta.json)
    try
        set dlg to display dialog "Gallerinamn (används som undermapp):" default answer "" with title "C1S3Upload" buttons {"Avbryt", "Nästa"} default button "Nästa"
    on error number -128
        return
    end try
    set galleriNamn to text returned of dlg
    if galleriNamn is "" then set galleriNamn to "okant"

    -- Dialog 3: Klientens namn
    try
        set dlg2 to display dialog "Klientens namn:" default answer "" with title "C1S3Upload" buttons {"Avbryt", "Ladda upp"} default button "Ladda upp"
    on error number -128
        return
    end try
    set klientNamn to text returned of dlg2

    -- Bygg prefix: t.ex. "commissions/anna-erik/"
    set prefix to kategori & "/" & galleriNamn & "/"

    -- Bygg kommando
    set cmd to quoted form of coreScript & " " & quoted form of galleriNamn & " " & quoted form of klientNamn & " " & quoted form of prefix
    repeat with f in theFiles
        set cmd to cmd & " " & quoted form of POSIX path of f
    end repeat

    -- Logga kommandot (utan credentials)
    do shell script "echo '[" & (do shell script "date '+%Y-%m-%d %H:%M:%S'") & "] Kör: " & coreScript & " med " & fileCount & " fil(er) till " & prefix & "' >> " & quoted form of logPath

    -- Kör uppladdning
    try
        do shell script cmd & " 2>>" & quoted form of logPath
        display notification "Uppladdade " & fileCount & " fil(er) till " & prefix with title "C1S3Upload" subtitle "Klart ✓"
    on error errMsg number errNum
        do shell script "echo '[ERROR] " & errMsg & "' >> " & quoted form of logPath
        display notification errMsg with title "C1S3Upload" subtitle "Fel"
    end try
end open
