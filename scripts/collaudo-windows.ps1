# Collaudo di installazione e aggiornamento su Windows (macchina pulita di GitHub).
#   A. installazione pulita della versione nuova: trova le chat delle AI, grafo, nessun errore
#   B. aggiornamento: installa la vecchia, la accende, salva due memorie, lancia l'installer nuovo SOPRA mentre e' accesa,
#      poi controlla trasloco dei dati, nessuna vecchia accesa, memorie intatte e conversazioni trovate.
# Uso: collaudo-windows.ps1 -Vecchio <exe> -Nuovo <exe> -Codice <cartella del codice> -Chiave <chiave privata di prova>
param([Parameter(Mandatory)][string]$Vecchio, [Parameter(Mandatory)][string]$Nuovo,
      [Parameter(Mandatory)][string]$Codice, [Parameter(Mandatory)][string]$Chiave, [switch]$ConPulita, [ValidateSet('installer','app','nessuno')][string]$Modo = 'installer')
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Local = $env:LOCALAPPDATA
$Programmi = "$Local\Programs"
$Fallimenti = New-Object System.Collections.Generic.List[string]

# Niente rete per la licenza: la chiave e' firmata con la chiave di prova e vale 3 giorni dal giorno in cui e' fatta.
$env:AI_BRAIN_LICENSE_CHECK_URL = 'http://127.0.0.1:9/controlla'
$env:AI_BRAIN_LICENSE_URL = 'http://127.0.0.1:9/attiva'

function Say($m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
# Un passo da cui dipende tutto il resto: se fallisce il collaudo si ferma qui.
function Salva-Dettagli {
    New-Item -ItemType Directory -Force "$env:RUNNER_TEMP\riservato" | Out-Null
    foreach ($d in "$Local\AI Brain", "$Local\Memdoria") { if (Test-Path "$d\logs\launcher.log") { "--- $d" | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log"; Get-Content "$d\logs\launcher.log" -Tail 80 -Encoding UTF8 | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log" } }
}

function Richiedi([bool]$ok, [string]$cosa) {
    Controlla $ok $cosa
    if (-not $ok) { Salva-Dettagli; throw "STOP: senza questo passo il resto non ha senso ($cosa)" }
}

function Controlla([bool]$ok, [string]$cosa) {
    if ($ok) { Write-Host "  OK   $cosa" -ForegroundColor Green } else { Write-Host "  MALE $cosa" -ForegroundColor Red; $Fallimenti.Add($cosa) }
}

function Prepara-Chat {
    $casa = $env:USERPROFILE
    $ag = "$casa\.gemini\antigravity\brain\8bd7e99a-26db\.system_generated\logs"
    New-Item -ItemType Directory -Force $ag | Out-Null
    @(
        (@{ step_index = 0; source = 'SYSTEM'; type = 'SYSTEM_MESSAGE'; content = 'avviso di sistema' } | ConvertTo-Json -Compress),
        (@{ step_index = 1; source = 'USER_EXPLICIT'; type = 'USER_INPUT'; created_at = '2026-10-06T16:46:33Z';
            content = "<USER_REQUEST>`nIl cliente Rossi Srl vuole il sito con prenotazioni online`n</USER_REQUEST>" } | ConvertTo-Json -Compress),
        (@{ step_index = 2; source = 'MODEL'; type = 'PLANNER_RESPONSE'; created_at = '2026-10-06T16:46:40Z';
            content = 'Preparo il progetto per Rossi Srl con le prenotazioni.' } | ConvertTo-Json -Compress)
    ) | Set-Content "$ag\transcript.jsonl" -Encoding UTF8
    $gm = "$casa\.gemini\tmp\h1\chats"
    New-Item -ItemType Directory -Force $gm | Out-Null
    (@{ sessionId = 'g1'; messages = @(
        @{ type = 'user'; timestamp = '2026-10-01T10:00:00Z'; content = 'Come imposto il dominio del sito di Verdi Srl?' },
        @{ type = 'gemini'; content = 'Punta il record A al server e attiva il certificato.' }) } | ConvertTo-Json -Depth 5) |
        Set-Content "$gm\session-1.json" -Encoding UTF8
    $cc = "$casa\.claude\projects\-lavoro-sito"
    New-Item -ItemType Directory -Force $cc | Out-Null
    @(
        (@{ type = 'user'; sessionId = 's1'; cwd = 'C:\lavoro\sito'; timestamp = '2026-10-02T09:00:00Z';
            message = @{ role = 'user'; content = 'Il cliente Bianchi Srl vuole il gestionale con Angular' } } | ConvertTo-Json -Depth 5 -Compress),
        (@{ type = 'assistant'; sessionId = 's1'; timestamp = '2026-10-02T09:00:05Z';
            message = @{ role = 'assistant'; content = @(@{ type = 'text'; text = 'Preparo il progetto Angular per Bianchi Srl.' }) } } | ConvertTo-Json -Depth 6 -Compress)
    ) | Set-Content "$cc\s1.jsonl" -Encoding UTF8
}

function Installa([string]$exe, [string]$log) {
    $p = Start-Process $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$log" -Wait -PassThru
    Controlla ($p.ExitCode -eq 0) "installer $(Split-Path $exe -Leaf) finito senza errori (uscita $($p.ExitCode))"
}

function Cartella-App([string]$nome) { "$Programmi\$nome" }

function Codice-Computer([string]$app) {
    (& "$app\runtime\python\python.exe" -E -s -S -c "import sys;sys.path.insert(0, r'$app\runtime\app');import licenza;print(licenza.machine_code())").Trim()
}

function Metti-Licenza([string]$app, [string]$dati) {
    $macchina = Codice-Computer $app
    New-Item -ItemType Directory -Force $dati | Out-Null
    $chiavi = "$env:USERPROFILE\.config\ai-brain-licenze"
    New-Item -ItemType Directory -Force $chiavi | Out-Null
    Copy-Item $Chiave "$chiavi\chiave-privata.pem" -Force
    $uscita = & python "$Codice\backend\app\licenza.py" nuova --nome 'Collaudo' --email 'collaudo@example.invalid' --computer $macchina --mesi 1 2>&1
    $licenza = ($uscita | Select-Object -Last 1).ToString().Trim()
    Controlla ($licenza -like 'AIB1.*') 'licenza di prova creata'
    if ($licenza -notlike 'AIB1.*') {
        New-Item -ItemType Directory -Force "$env:RUNNER_TEMP\riservato" | Out-Null
        "codice computer: [$macchina]`n$($uscita | Out-String)" | Set-Content "$env:RUNNER_TEMP\riservato\licenza.log"
        throw 'Senza licenza il collaudo non puo continuare'
    }
    [IO.File]::WriteAllText("$dati\licenza.txt", $licenza)
}

function Accendi([string]$app) {
    # Si accende come la persona: con il collegamento nel menu Start che l'installer di QUELLA versione ha creato (la 1.0.25 lo
    # lancia con il solo tray.py; da 1.0.28 con -E -s -S). Se il collegamento non c'e', si usano le opzioni di oggi.
    $argomenti = @('-E', '-s', '-S', "`"$app\runtime\app\tray.py`"")
    try {
        $shell = New-Object -ComObject WScript.Shell
        $menu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        foreach ($nome in 'Memdoria', 'AI Brain') {
            if (-not (Test-Path "$menu\$nome.lnk")) { continue }
            $collegamento = $shell.CreateShortcut("$menu\$nome.lnk")
            if ($collegamento.TargetPath -like "$app\*" -and $collegamento.Arguments) { $argomenti = @($collegamento.Arguments); break }
        }
    } catch { }
    Start-Process "$app\runtime\python\AI Brain.exe" -ArgumentList $argomenti -WorkingDirectory $app | Out-Null
}

. "$PSScriptRoot\lettura.ps1"   # Esito-Lettura: la regola «lettura finita», provata da tests\lettura.tests.ps1

function Aspetta-Lettura([string]$dati, [int]$minuti = 12) {
    # «finita» = done (conferma della finestra) oppure «Fatto» (versioni nuove) oppure, per le versioni vecchie che non lo
    # scrivono, 60 secondi dopo «Grafo»/«Pronto» (le entita' arrivano un attimo dopo).
    $fine = (Get-Date).AddMinutes($minuti); $visto = 0
    while ((Get-Date) -lt $fine) {
        Start-Sleep 10
        Remove-Item "$dati\lingua-da-scegliere" -Recurse -Force -ErrorAction SilentlyContinue
        try {
            $p = Get-Content "$dati\progress.json" -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            $ultimo = @($p.events | Select-Object -Last 1)[0]
            if ($ultimo) { $script:ultimoPasso = ([string]$ultimo.text -replace '[^\x20-\x7E]', '?'); if ($script:ultimoPasso.Length -gt 60) { $script:ultimoPasso = $script:ultimoPasso.Substring(0, 60) } }
            switch (Esito-Lettura $p) {
                0 { return $p }
                2 { return $p }
                3 { $visto++; if ($visto -ge 6) { return $p } }
            }
        } catch { }
    }
    return $null
}

function Statistiche([string]$dati) {
    $cfg = Get-Content "$dati\config.json" -Raw | ConvertFrom-Json
    Invoke-RestMethod -Headers @{ Authorization = "Bearer $($cfg.brain_token)" } "http://127.0.0.1:$($cfg.brain_port)/admin/stats"
}

function Salva-Memoria([string]$dati, [string]$testo) {
    $cfg = Get-Content "$dati\config.json" -Raw | ConvertFrom-Json
    $corpo = @{ text = $testo; kind = 'fact'; source = 'collaudo'; source_ai = 'collaudo'; entities = @(@{ name = 'Verdi Srl'; type = 'client' }) } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Post -Headers @{ Authorization = "Bearer $($cfg.brain_token)" } -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($corpo)) "http://127.0.0.1:$($cfg.brain_port)/admin/remember" | Out-Null
}

function Pagina-Nel-Browser([string]$dati, [string]$quando) {
    # La pagina vera servita dal brain, in un browser vero: si apre, non ha errori e disegna il grafo.
    if (-not (Test-Path "$PSScriptRoot\pagina.mjs") -or -not (Get-Command node -ErrorAction SilentlyContinue)) { return }
    $cfg = Get-Content "$dati\config.json" -Raw | ConvertFrom-Json
    $uscita = & node "$PSScriptRoot\pagina.mjs" "http://127.0.0.1:$($cfg.brain_port)/app/" "$env:RUNNER_TEMP\pagina-$($quando -replace ' ', '-')" 2>&1
    Controlla ($LASTEXITCODE -eq 0) "la pagina si apre nel browser e disegna il grafo ($quando): $($uscita | Select-Object -Last 1)"
}

function Seme-Connessione([string]$dati) {
    # La persona ha risposto «si» alla domanda «Le collego a Memdoria?» (si salva in config.json, prima del primo avvio).
    New-Item -ItemType Directory -Force $dati | Out-Null
    if (-not (Test-Path "$dati\config.json")) { [IO.File]::WriteAllText("$dati\config.json", '{"connect_answer": "yes"}') }
}

function Collega-Ai([string]$dati) {
    # L'app collega dopo la lettura: si aspetta la sua voce nei file di Claude Code (fino a 2 minuti).
    $fine = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $fine) {
        if ((Test-Path "$env:USERPROFILE\.claude.json") -and ((Get-Content "$env:USERPROFILE\.claude.json" -Raw) -match 'ai-brain')) { return $true }
        Start-Sleep 5
    }
    return $false
}

function Lingua-Si-Cambia([string]$dati) {
    $cfg = Get-Content "$dati\config.json" -Raw | ConvertFrom-Json
    $url = "http://127.0.0.1:$($cfg.brain_port)/api/lingua"
    Invoke-RestMethod -Method Put -Uri $url -ContentType 'application/json' -Body '{"lingua":"en"}' | Out-Null
    $e = (Invoke-RestMethod -Uri $url).lingua
    Invoke-RestMethod -Method Put -Uri $url -ContentType 'application/json' -Body '{"lingua":"it"}' | Out-Null
    $i = (Invoke-RestMethod -Uri $url).lingua
    return ($e -eq 'en' -and $i -eq 'it')
}

function Processi-Di([string]$cartella) {
    @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$cartella\*" })
}

function Spegni-Tutto {
    Get-Process | Where-Object { $_.Path -like "$Programmi\*" } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep 5
}

function Disinstalla-Tutto {
    Spegni-Tutto
    foreach ($u in (Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath } |
            Where-Object { $_.DisplayName -match 'Memdoria|AI Brain' })) {
        Start-Process ($u.UninstallString -replace '"', '') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
    }
    foreach ($n in 'AI Brain', 'Memdoria') {
        $p = "$Local\$n"
        if (Test-Path $p) { if ((Get-Item $p -Force).LinkType) { cmd /c rmdir "`"$p`"" } else { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue } }
        Remove-Item "$Programmi\$n" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Prepara-Chat

# ---------------------------------------------------------------------------------------------------------------------
if ($ConPulita) {
    Say 'A. Installazione pulita della versione nuova'
    Installa $Nuovo "$env:RUNNER_TEMP\installa-nuovo.log"
    $app = Cartella-App 'Memdoria'
    Controlla (Test-Path "$app\runtime\python\AI Brain.exe") 'l''app e'' in Programs\Memdoria'
    $dati = "$Local\Memdoria"
    Metti-Licenza $app $dati
    # Il modello di Memdoria AI (1,2 GB) arriva dalla cache della corsa, se c'e'; altrimenti lo scarica l'app e lo si tiene per la prossima.
    $cacheModello = "$env:RUNNER_TEMP\modello"
    if (Test-Path "$cacheModello\*.gguf") { New-Item -ItemType Directory -Force "$dati\modello-locale" | Out-Null; Copy-Item "$cacheModello\*" "$dati\modello-locale" -Force; Write-Host "       modello preso dalla cache" }
    Seme-Connessione $dati
    Accendi $app
    $p = Aspetta-Lettura $dati
    Richiedi ($null -ne $p -and -not $p.error) "la prima lettura finisce senza errori ($($p.error))"
    if ($p) { $p.events | ForEach-Object { Write-Host "       $($_.text)" } }
    # Una memoria con un cliente: il grafo deve mostrarlo (cio che l'AI ricava dalle chat finte puo' variare da giro a giro).
    Salva-Memoria $dati 'Il cliente Verdi Srl usa il gestionale Alfa dal 2024.'
    $s = Statistiche $dati
    for ($k = 0; $k -lt 9 -and $s.entities -lt 1; $k++) { Start-Sleep 10; $s = Statistiche $dati }
    Controlla ($s.conversations -ge 3) "conversazioni trovate: $($s.conversations) (attese almeno 3: Antigravity, Gemini CLI, Claude Code)"
    Controlla (-not (Test-Path "$Local\AI Brain")) 'nessuna cartella "AI Brain" in una installazione nuova'
    Controlla (($s.entities -ge 1) -and ($s.memories -ge 1)) "il grafo si riempie: $($s.entities) entita, $($s.memories) memorie, $($s.relations) relazioni"
    $menu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    Controlla (Test-Path "$menu\Memdoria.lnk") 'collegamento "Memdoria" nel menu Start'
    # Il nome segue la lingua dell'installazione: italiano o inglese.
    Controlla ((Test-Path "$menu\Ripara Memdoria.lnk") -or (Test-Path "$menu\Repair Memdoria.lnk")) 'collegamento "Ripara Memdoria" (o "Repair Memdoria") nel menu Start'
    $fineAvvio = (Get-Date).AddSeconds(90)
    while (-not ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) -match 'Programs\\Memdoria') -and (Get-Date) -lt $fineAvvio) { Start-Sleep 5 }
    Controlla ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) -match 'Programs\\Memdoria') 'avvio automatico verso la cartella nuova'
    # Memdoria AI: scarica il suo modello e lavora (fino a 20 minuti, la macchina e'' lenta)
    $fineModello = (Get-Date).AddMinutes(20); $modello = $false
    while ((Get-Date) -lt $fineModello -and -not $modello) {
        Start-Sleep 20
        $modello = @(Get-ChildItem "$dati\modello-locale" -Filter '*.gguf.ok' -ErrorAction SilentlyContinue).Count -gt 0
    }
    Controlla $modello 'Memdoria AI ha scaricato il suo modello'
    if ($modello) {
        $inizio = (Statistiche $dati).memories; $fineLavoro = (Get-Date).AddMinutes(10); $lavora = $false
        while ((Get-Date) -lt $fineLavoro -and -not $lavora) {
            Start-Sleep 20
            $lavora = ((Statistiche $dati).memories -gt $inizio) -or (Test-Path "$dati\modello-locale\stato.json")
        }
        Controlla $lavora 'Memdoria AI ha cominciato a lavorare sulle conversazioni'
    }
    $righe = & "$app\runtime\python\python.exe" -E -s "$PSScriptRoot\licenze-offline.py" "$app\runtime\app" $Chiave 2>&1
    $righe | ForEach-Object { Write-Host "       $_" }
    Controlla ($LASTEXITCODE -eq 0) 'gli stati della licenza (manca, giusta, scaduta, altro computer, firma rovinata) sull''app installata'
    Controlla (Collega-Ai $dati) 'collega le AI: la voce di Memdoria compare nei file di Claude Code'
    Controlla (Lingua-Si-Cambia $dati) 'il cambio lingua (inglese e di nuovo italiano) si salva'
    Pagina-Nel-Browser $dati 'installazione pulita'
    if ((Test-Path "$dati\modello-locale\*.gguf.ok") -and -not (Test-Path "$cacheModello\*.gguf")) {
        New-Item -ItemType Directory -Force $cacheModello | Out-Null
        Copy-Item "$dati\modello-locale\*.gguf*" $cacheModello -Force
        Write-Host "       modello salvato per la prossima volta"
    }
    Disinstalla-Tutto
    Controlla (-not (Test-Path "$Programmi\Memdoria")) 'dopo la disinstallazione la cartella del programma non c e piu'
    Controlla (@(Get-Process | Where-Object { $_.Path -like "$Programmi\*" }).Count -eq 0) 'dopo la disinstallazione nessun programma e acceso'
    Controlla (-not (Test-Path "$menu\Memdoria.lnk")) 'dopo la disinstallazione il collegamento nel menu Start e sparito'

}

# ---------------------------------------------------------------------------------------------------------------------
function Scenario-Aggiornamento([string]$modo) {
    # Fino alla 1.0.30 programma e dati si chiamano «AI Brain» (al primo avvio nuovo i dati si traslocano in «Memdoria»);
    # dalla 1.0.31 sono gia' «Memdoria»: niente trasloco e niente cartella vecchia da controllare.
    $verVecchia = [regex]::Match((Split-Path $Vecchio -Leaf), 'AI-Brain-([0-9.]+)-').Groups[1].Value
    $separata = ([version]$verVecchia) -lt ([version]'1.0.31')
    $nomeVecchio = if ($separata) { 'AI Brain' } else { 'Memdoria' }
    Say "B. Aggiornamento dalla $verVecchia, accesa ($modo)"
    Disinstalla-Tutto
    Installa $Vecchio "$env:RUNNER_TEMP\installa-vecchio-$modo.log"
    $vecchia = Cartella-App $nomeVecchio
    Controlla (Test-Path "$vecchia\runtime\python\AI Brain.exe") "la versione $verVecchia e'' in Programs\$nomeVecchio"
    $datiVecchi = "$Local\$nomeVecchio"
    if ($modo -eq 'app') {
        # La versione di prima guarda l'elenco delle versioni in questo file, firmato con la chiave di prova.
        $cartellaFeed = "$env:RUNNER_TEMP\feed"; New-Item -ItemType Directory -Force $cartellaFeed | Out-Null
        Copy-Item $Nuovo $cartellaFeed -Force
        $exeFeed = "$cartellaFeed\$(Split-Path $Nuovo -Leaf)"
        $versioneNuova = (Get-Content "$Codice\VERSION" -TotalCount 1).Trim()
        & python "$PSScriptRoot\feed.py" $Codice $Chiave "$cartellaFeed\ultima-versione.json" $versioneNuova windows $exeFeed ("file:///" + ($exeFeed -replace '\\', '/'))
        $env:AI_BRAIN_UPDATES_URL = "file:///" + (("$cartellaFeed\ultima-versione.json") -replace '\\', '/')
    }
    Metti-Licenza $vecchia $datiVecchi
    Seme-Connessione $datiVecchi
    Accendi $vecchia
    $p = Aspetta-Lettura $datiVecchi
    $stato = "file nella cartella dei dati: $(((Get-ChildItem $datiVecchi -Force -ErrorAction SilentlyContinue | Select-Object -First 12).Name) -join ', '); programmi accesi: $((Processi-Di $vecchia).Count)"
    Richiedi ($null -ne $p -and -not $p.error) "la versione di prima finisce la lettura ($($p.error)) ultimo passo: $script:ultimoPasso; $stato"
    Salva-Memoria $datiVecchi 'Il cliente Verdi Srl usa il gestionale Alfa dal 2024.'
    Salva-Memoria $datiVecchi 'Il server di Verdi Srl e in Hetzner a Norimberga.'
    $prima = Statistiche $datiVecchi
    Controlla ($prima.memories -ge 2) "memorie salvate prima dell'aggiornamento: $($prima.memories)"
    $haVoci = Collega-Ai $datiVecchi
    if ($haVoci) { Controlla $true "la versione $verVecchia ha collegato le AI" } else { Write-Host "       la versione $verVecchia non ha collegato le AI da sola (probabile conferma a schermo): salto i controlli sulle voci dopo l'aggiornamento" }
    Controlla ((Processi-Di $vecchia).Count -gt 0) 'la versione di prima e'' accesa quando parte l''aggiornamento'
    Start-Sleep 5

    $nuova = Cartella-App 'Memdoria'
    if ($modo -eq 'installer') {
        Installa $Nuovo "$env:RUNNER_TEMP\installa-sopra.log"
    } else {
        Set-Content "$datiVecchi\aggiorna.request" 'aggiorna'
        $fine = (Get-Date).AddMinutes(15)
        $versioneNuova = (Get-Content "$Codice\VERSION" -TotalCount 1).Trim()
        function Versione-Installata { try { (Get-Content "$nuova\runtime\app\VERSION" -TotalCount 1 -ErrorAction Stop).Trim() } catch { '' } }
        while ((Get-Date) -lt $fine -and (Versione-Installata) -ne $versioneNuova) { Start-Sleep 10 }
        Controlla ((Versione-Installata) -eq $versioneNuova) 'l''app ha scaricato e installato la versione nuova da sola'
        Start-Sleep 30
        Remove-Item Env:\AI_BRAIN_UPDATES_URL -ErrorAction SilentlyContinue
    }
    Start-Sleep 10
    if ($separata) {
        Controlla ((Processi-Di $vecchia).Count -eq 0) 'nessun programma della versione di prima e'' rimasto acceso'
        $fineTolta = (Get-Date).AddSeconds(90)
        while ((Test-Path $vecchia) -and (Get-Date) -lt $fineTolta) { Start-Sleep 5 }
        $rimasto = if (Test-Path $vecchia) { ((Get-ChildItem $vecchia -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { $_.FullName.Substring($vecchia.Length) }) -join ' ; ') } else { '' }
        # Una cartella VUOTA puo' restare finche' un programma ha li' il suo «dove sono»: non e' un residuo. Vale se non ci sono file.
        Controlla ((-not (Test-Path $vecchia)) -or ($rimasto -eq '')) "la cartella Programs\AI Brain non ha piu' file (rimasto: $rimasto)"
    }
    Controlla (Test-Path "$nuova\runtime\python\AI Brain.exe") 'la versione nuova e'' in Programs\Memdoria'

    # Se l'aggiornamento non l'ha riaccesa (sessione senza schermo vero), la si accende come farebbe la persona.
    if ((Processi-Di $nuova).Count -eq 0) { Accendi $nuova }
    $datiNuovi = "$Local\Memdoria"
    $p = Aspetta-Lettura $datiNuovi
    Richiedi ($null -ne $p -and -not $p.error) "dopo l'aggiornamento la lettura finisce senza errori ($($p.error))"
    if ($separata) {
        $link = Get-Item "$Local\AI Brain" -Force -ErrorAction SilentlyContinue
        Controlla ($null -ne $link -and $link.LinkType -eq 'Junction') 'trasloco fatto: "AI Brain" e'' un collegamento verso "Memdoria"'
    } else { Write-Host "       la $verVecchia ha gia' i dati in Memdoria: niente trasloco da controllare" }
    Controlla (Test-Path "$datiNuovi\config.json") 'i dati stanno in Memdoria'
    $dopo = Statistiche $datiNuovi
    Controlla ($dopo.memories -ge $prima.memories) "memorie intatte: prima $($prima.memories), dopo $($dopo.memories)"
    Controlla ($dopo.conversations -ge 3) "conversazioni trovate dopo l'aggiornamento: $($dopo.conversations)"
    if ($separata) { Controlla ((Processi-Di $vecchia).Count -eq 0) 'ancora nessuna versione di prima accesa' }
    Controlla ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) -notmatch 'Programs\\AI Brain') 'l''avvio automatico non punta piu'' alla cartella vecchia'
    if ($haVoci) {
        $voci = Get-Content "$env:USERPROFILE\.claude.json" -Raw
        Controlla (($voci -match 'ai-brain') -and ($voci -notmatch 'Local[\\/]+AI Brain')) 'le voci delle AI sono rimaste e non puntano piu'' alla cartella vecchia'
    }
    Controlla (Lingua-Si-Cambia $datiNuovi) 'dopo l''aggiornamento il cambio lingua funziona'
    Pagina-Nel-Browser $datiNuovi "dopo l'aggiornamento ($modo)"
    $script:UltimiDati = @($datiVecchi, $datiNuovi)
    Disinstalla-Tutto
}

if ($Modo -ne 'nessuno') { Scenario-Aggiornamento $Modo }

Say 'Esito'
Spegni-Tutto
if ($Fallimenti.Count -gt 0) {
    Write-Host "`nCOLLAUDO FALLITO ($($Fallimenti.Count)):" -ForegroundColor Red
    $Fallimenti | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    New-Item -ItemType Directory -Force "$env:RUNNER_TEMP\riservato" | Out-Null
    foreach ($d in $script:UltimiDati + "$Local\Memdoria") { if (Test-Path "$d\logs\launcher.log") { "--- $d" | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log"; Get-Content "$d\logs\launcher.log" -Tail 80 -Encoding UTF8 | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log" } }
    exit 1
}
Write-Host "`nCOLLAUDO RIUSCITO" -ForegroundColor Green
