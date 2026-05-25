-- C1S3Upload — Capture One → S3 / Cloudflare R2
-- Capture One skickar filer en i taget via "Open With".
-- Första filen visar dialogen, resten av filerna i samma
-- session (inom 30 min) laddas upp tyst med samma inställningar.

on open theFiles
    set logPath to (POSIX path of (path to home folder)) & "Library/Logs/C1S3Upload.log"
    set sessionFile to (POSIX path of (path to home folder)) & ".c1s3upload_session.json"
    set coreScript to "/Applications/C1S3Upload.app/Contents/MacOS/c1s3upload_core.sh"
    set fileCount to count of theFiles

    -- Debug: logga antal filer
    do shell script "echo '[" & (do shell script "date '+%Y-%m-%d %H:%M:%S'") & "] on open fick " & fileCount & " fil(er)' >> " & quoted form of logPath

    -- Kolla om det finns en aktiv session (skapad inom 30 min)
    set useSession to false
    try
        set sessionAge to do shell script "echo $(( $(date +%s) - $(date -r " & quoted form of sessionFile & " +%s) ))"
        if (sessionAge as integer) < 1800 then
            set useSession to true
        end if
    end try

    if useSession then
        -- Läs inställningar från session-fil (en rad per värde)
        set sessionLines to paragraphs of (do shell script "cat " & quoted form of sessionFile)
        set kategori to item 1 of sessionLines
        set galleriNamn to item 2 of sessionLines
        set klientNamn to item 3 of sessionLines
    else
        -- Visa dialoger för ny session

        -- Dialog 1: Välj kategori
        set kategoriVal to choose from list {"commissions", "landscapes", "observations"} with title "C1S3Upload" with prompt "Välj kategori:" default items {"commissions"} without multiple selections allowed and empty selection allowed
        if kategoriVal is false then return
        set kategori to item 1 of kategoriVal

        -- Dialog 2: Gallerinamn
        try
            set dlg to display dialog "Gallerinamn (används som undermapp):" default answer "" with title "C1S3Upload" buttons {"Avbryt", "Nästa"} default button "Nästa"
        on error number -128
            return
        end try
        set galleriNamn to text returned of dlg
        if galleriNamn is "" then set galleriNamn to "okant"

        -- Dialog 3: Klientnamn
        try
            set dlg2 to display dialog "Klientens namn:" default answer "" with title "C1S3Upload" buttons {"Avbryt", "Ladda upp"} default button "Ladda upp"
        on error number -128
            return
        end try
        set klientNamn to text returned of dlg2

        -- Spara session (en rad per värde, undviker citatproblem)
        do shell script "printf '%s\\n' " & quoted form of kategori & " " & quoted form of galleriNamn & " " & quoted form of klientNamn & " > " & quoted form of sessionFile
    end if

    -- Bygg prefix och kommando
    set prefix to kategori & "/" & galleriNamn & "/"
    set cmd to quoted form of coreScript & " " & quoted form of galleriNamn & " " & quoted form of klientNamn & " " & quoted form of prefix
    repeat with f in theFiles
        set cmd to cmd & " " & quoted form of POSIX path of f
    end repeat

    -- Logga
    do shell script "echo '[" & (do shell script "date '+%Y-%m-%d %H:%M:%S'") & "] Kör: " & coreScript & " med " & fileCount & " fil(er) till " & prefix & "' >> " & quoted form of logPath

    -- Kör uppladdning
    try
        do shell script cmd & " 2>>" & quoted form of logPath
        if not useSession then
            display notification "Laddar upp till " & prefix & "..." with title "C1S3Upload"
        end if
    on error errMsg number errNum
        do shell script "echo '[ERROR] " & errMsg & "' >> " & quoted form of logPath
        display notification errMsg with title "C1S3Upload" subtitle "Fel"
    end try
end open
