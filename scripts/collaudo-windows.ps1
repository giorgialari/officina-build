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
    foreach ($d in "$Local\AI Brain", "$Local\Memdoria", "$Local\Memdoria-AI-Brain") { if (Test-Path "$d\logs\launcher.log") { "--- $d" | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log"; Get-Content "$d\logs\launcher.log" -Tail 80 -Encoding UTF8 | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log" } }
}

function Richiedi([bool]$ok, [string]$cosa) {
    Controlla $ok $cosa
    if (-not $ok) { Salva-Dettagli; throw "STOP: senza questo passo il resto non ha senso ($cosa)" }
}

function Controlla([bool]$ok, [string]$cosa) {
    if ($ok) { Write-Host "  OK   $cosa" -ForegroundColor Green } else { Write-Host "  MALE $cosa" -ForegroundColor Red; $Fallimenti.Add($cosa) }
}

function Installer-InCorso {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -like '*AI-Brain-*windows-x64*' -or $_.Path -like '*\is-*.tmp\*'
    }).Count -gt 0
}

function Prepara-Chat {
    $casa = $env:USERPROFILE
    New-Item -ItemType Directory -Force "$casa\.codex" | Out-Null
    # Le chat da sole non indicano che Claude Code sia installato. Simuliamo anche il client per collaudare il collegamento.
    $binClaude = "$casa\AppData\Roaming\npm"
    New-Item -ItemType Directory -Force $binClaude | Out-Null
    Set-Content "$binClaude\claude.cmd" '@echo off' -Encoding ASCII
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
    # Si accende come la persona: con il collegamento nel menu Start che l'installer di QUELLA versione ha creato.
    # Se il collegamento non c'e', si usano le opzioni di oggi.
    $argomenti = @('-E', '-s', '-S', "`"$app\runtime\app\tray.py`"")
    try {
        $shell = New-Object -ComObject WScript.Shell
        $menu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        foreach ($nome in 'Memdoria AI Brain', 'Memdoria', 'AI Brain') {
            if (-not (Test-Path "$menu\$nome.lnk")) { continue }
            $collegamento = $shell.CreateShortcut("$menu\$nome.lnk")
            if ($collegamento.TargetPath -like "$app\*" -and $collegamento.Arguments) { $argomenti = @($collegamento.Arguments); break }
        }
    } catch { }
    $exe = if (Test-Path "$app\runtime\python\Memdoria AI Brain.exe") { 'Memdoria AI Brain.exe' } else { 'AI Brain.exe' }
    Start-Process "$app\runtime\python\$exe" -ArgumentList $argomenti -WorkingDirectory $app | Out-Null
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

function Pagina-Primo-Avvio([string]$dati, [string]$versione, [string]$modo) {
    $fine = (Get-Date).AddSeconds(60)
    while (-not (Test-Path "$dati\config.json") -and (Get-Date) -lt $fine) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-Path "$dati\config.json")) { Controlla $false "prima riapertura dopo $versione ($modo): configurazione non pronta"; return }
    $cfg = Get-Content "$dati\config.json" -Raw | ConvertFrom-Json
    $uscita = & node "$PSScriptRoot\pagina.mjs" "http://127.0.0.1:$($cfg.brain_port)/app/" `
        "$env:RUNNER_TEMP\primo-avvio-windows-$versione-$modo" --server-in-riavvio 2>&1
    Controlla ($LASTEXITCODE -eq 0) "prima riapertura dopo $versione ($modo): attesa pulita e ritorno del grafo senza riavviare: $($uscita | Select-Object -Last 1)"
}

function Avvia-Controllo-Motore([string]$app, [string]$dati, [object[]]$pidVecchi, [string]$versioneNuova) {
    # Il lavoro in parallelo parte PRIMA dell'installer. Cerca il primo tray nuovo (non quello della vecchia versione),
    # aspetta che /api/setup-info dica la versione nuova e osserva subito l'Engine ogni 250 ms per 40 secondi.
    # Così il tempo impiegato dal collaudo per attendere i file o il processo non può nascondere un errore temporaneo.
    $pidPrima = $pidVecchi -join ','
    Start-Job -ArgumentList $app, $dati, $pidPrima, $versioneNuova -ScriptBlock {
        param($app, $dati, $pidPrima, $versioneNuova)
        $precedenti = @($pidPrima.Split(',') | Where-Object { $_ } | ForEach-Object { [int]$_ })
        $fine = (Get-Date).AddMinutes(12)
        $porta = $null
        while ((Get-Date) -lt $fine) {
            $trayNuovo = @(Get-CimInstance Win32_Process -Filter "Name = 'Memdoria AI Brain.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.ExecutablePath -like "$app\*" -and $_.CommandLine -match 'tray\.py' -and $_.ProcessId -notin $precedenti })
            if ($trayNuovo.Count -gt 0) {
                try {
                    $cfg = Get-Content "$dati\config.json" -Raw -ErrorAction Stop | ConvertFrom-Json
                    $porta = $cfg.brain_port
                    $info = Invoke-RestMethod -Uri "http://127.0.0.1:$porta/api/setup-info" -TimeoutSec 1 -ErrorAction Stop
                    if ($info.version -eq $versioneNuova) { break }
                } catch { }
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $porta -or (Get-Date) -ge $fine) { return [pscustomobject]@{ visto = $false; errore = $false; motivo = 'nuova versione non osservata' } }
        $visto = $false
        for ($i = 0; $i -lt 160; $i++) {
            try {
                $stato = Invoke-RestMethod -Uri "http://127.0.0.1:$porta/api/modello-locale/stato" -TimeoutSec 1 -ErrorAction Stop
                if ($stato.stato -eq 'errore') { return [pscustomobject]@{ visto = $true; errore = $true; motivo = 'Engine in errore alla prima riapertura' } }
                if ($stato.stato) { $visto = $true }
            } catch { }
            Start-Sleep -Milliseconds 250
        }
        return [pscustomobject]@{ visto = $visto; errore = $false; motivo = 'osservazione terminata' }
    }
}

function Prepara-Feed-Pulsante {
    $versione = (Get-Content "$Codice\VERSION" -TotalCount 1).Trim()
    $pezzi = $versione.Split('.')
    $pezzi[-1] = [string]([int]$pezzi[-1] + 1)
    $futura = $pezzi -join '.'
    $cartella = "$env:RUNNER_TEMP\feed-pulsante"
    New-Item -ItemType Directory -Force $cartella | Out-Null
    $script:FeedAttivo = "$cartella\ultima-versione.json"
    $script:FeedNuovo = "$cartella\versione-nuova.json"
    $indirizzo = 'file:///' + ($Nuovo -replace '\\', '/')
    & python "$PSScriptRoot\feed.py" $Codice $Chiave $script:FeedAttivo $versione windows $Nuovo $indirizzo | Out-Null
    Richiedi ($LASTEXITCODE -eq 0) 'elenco iniziale di prova preparato'
    & python "$PSScriptRoot\feed.py" $Codice $Chiave $script:FeedNuovo $futura windows $Nuovo $indirizzo | Out-Null
    Richiedi ($LASTEXITCODE -eq 0) 'elenco con la versione futura preparato'
    $env:AI_BRAIN_UPDATES_URL = 'file:///' + ($script:FeedAttivo -replace '\\', '/')
    $env:AI_BRAIN_AGGIORNA_OGNI = '5'
}

function Controlla-Pulsante-Aggiornamento([string]$dati) {
    $cfg = Get-Content "$dati\config.json" -Raw | ConvertFrom-Json
    $uscita = & node "$PSScriptRoot\pagina.mjs" "http://127.0.0.1:$($cfg.brain_port)/app/" "$env:RUNNER_TEMP\pulsante-windows" `
        --pulsante-aggiornamento $script:FeedNuovo $script:FeedAttivo 2>&1
    Controlla ($LASTEXITCODE -eq 0) "il pulsante in alto a destra si attiva senza riavvio dopo il cambio del feed: $($uscita | Select-Object -Last 1)"
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
        $nome = if ($dati -like '*Memdoria-AI-Brain') { 'memdoria-ai-brain' } else { 'ai-brain' }
        if ((Test-Path "$env:USERPROFILE\.claude.json") -and ((Get-Content "$env:USERPROFILE\.claude.json" -Raw) -match ('"' + $nome + '"'))) { return $true }
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
    foreach ($n in 'AI Brain', 'Memdoria', 'Memdoria-AI-Brain') {
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
    $app = Cartella-App 'Memdoria-AI-Brain'
    Controlla (Test-Path "$app\runtime\python\Memdoria AI Brain.exe") 'l''app e'' in Programs\Memdoria-AI-Brain'
    $dati = "$Local\Memdoria-AI-Brain"
    Metti-Licenza $app $dati
    # Il modello di Memdoria AI (1,2 GB) arriva dalla cache della corsa, se c'e'; altrimenti lo scarica l'app e lo si tiene per la prossima.
    $cacheModello = "$env:RUNNER_TEMP\modello"
    if (Test-Path "$cacheModello\*.gguf") { New-Item -ItemType Directory -Force "$dati\modello-locale" | Out-Null; Copy-Item "$cacheModello\*" "$dati\modello-locale" -Force; Write-Host "       modello preso dalla cache" }
    Seme-Connessione $dati
    Prepara-Feed-Pulsante
    Accendi $app
    $p = Aspetta-Lettura $dati
    Richiedi ($null -ne $p -and -not $p.error) "la prima lettura finisce senza errori ($($p.error))"
    if ($p) { $p.events | ForEach-Object { Write-Host "       $($_.text)" } }
    # Una memoria con un cliente: il grafo deve mostrarlo (cio che l'AI ricava dalle chat finte puo' variare da giro a giro).
    Salva-Memoria $dati 'Il cliente Verdi Srl usa il gestionale Alfa dal 2024.'
    $s = Statistiche $dati
    for ($k = 0; $k -lt 9 -and $s.entities -lt 1; $k++) { Start-Sleep 10; $s = Statistiche $dati }
    Controlla ($s.conversations -ge 3) "conversazioni trovate: $($s.conversations) (attese almeno 3: Antigravity, Gemini CLI, Claude Code)"
    Controlla (-not (Test-Path "$Local\AI Brain") -and -not (Test-Path "$Local\Memdoria")) 'nessuna cartella dati col nome di prima in una installazione nuova'
    Controlla (($s.entities -ge 1) -and ($s.memories -ge 1)) "il grafo si riempie: $($s.entities) entita, $($s.memories) memorie, $($s.relations) relazioni"
    $menu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    Controlla (Test-Path "$menu\Memdoria AI Brain.lnk") 'collegamento "Memdoria AI Brain" nel menu Start'
    # Il nome segue la lingua dell'installazione: italiano o inglese.
    Controlla ((Test-Path "$menu\Ripara Memdoria.lnk") -or (Test-Path "$menu\Repair Memdoria.lnk")) 'collegamento "Ripara Memdoria" (o "Repair Memdoria") nel menu Start'
    $fineAvvio = (Get-Date).AddSeconds(90)
    while (-not ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) -match 'Programs\\Memdoria') -and (Get-Date) -lt $fineAvvio) { Start-Sleep 5 }
    Controlla ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) -match 'Programs\\Memdoria-AI-Brain') 'avvio automatico verso la cartella nuova'
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
    Controlla-Pulsante-Aggiornamento $dati
    if ((Test-Path "$dati\modello-locale\*.gguf.ok") -and -not (Test-Path "$cacheModello\*.gguf")) {
        New-Item -ItemType Directory -Force $cacheModello | Out-Null
        Copy-Item "$dati\modello-locale\*.gguf*" $cacheModello -Force
        Write-Host "       modello salvato per la prossima volta"
    }
    Disinstalla-Tutto
    Controlla (-not (Test-Path "$Programmi\Memdoria-AI-Brain")) 'dopo la disinstallazione la cartella del programma non c e piu'
    Controlla (@(Get-Process | Where-Object { $_.Path -like "$Programmi\*" }).Count -eq 0) 'dopo la disinstallazione nessun programma e acceso'
    Controlla (-not (Test-Path "$menu\Memdoria AI Brain.lnk")) 'dopo la disinstallazione il collegamento nel menu Start e sparito'
    Remove-Item Env:\AI_BRAIN_UPDATES_URL, Env:\AI_BRAIN_AGGIORNA_OGNI -ErrorAction SilentlyContinue

}

# ---------------------------------------------------------------------------------------------------------------------
function Scenario-Aggiornamento([string]$modo) {
    # La 1.0.32 usa il vecchio percorso; dalla 1.0.33 la cartella installata è Memdoria-AI-Brain.
    $verVecchia = [regex]::Match((Split-Path $Vecchio -Leaf), 'AI-Brain-([0-9.]+)-').Groups[1].Value
    Richiedi ($verVecchia -in @('1.0.32', '1.0.33', '1.0.34')) "la versione di partenza e' la 1.0.32, 1.0.33 o 1.0.34 (trovata $verVecchia)"
    $separata = $verVecchia -eq '1.0.32'
    $nomeVecchio = if ($separata) { 'Memdoria' } else { 'Memdoria-AI-Brain' }
    Say "B. Aggiornamento dalla $verVecchia, accesa ($modo)"
    Disinstalla-Tutto
    Installa $Vecchio "$env:RUNNER_TEMP\installa-vecchio-$modo.log"
    $vecchia = Cartella-App $nomeVecchio
    $exeVecchio = if ($separata) { 'AI Brain.exe' } else { 'Memdoria AI Brain.exe' }
    Controlla (Test-Path "$vecchia\runtime\python\$exeVecchio") "la versione $verVecchia e'' in Programs\$nomeVecchio"
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
    $pidVecchi = @((Processi-Di $vecchia | Where-Object { $_.CommandLine -match 'tray\.py' }).ProcessId)
    Start-Sleep 5

    $nuova = Cartella-App 'Memdoria-AI-Brain'
    $versioneNuova = (Get-Content "$Codice\VERSION" -TotalCount 1).Trim()
    $osservaMotore = Avvia-Controllo-Motore $nuova "$Local\Memdoria-AI-Brain" $pidVecchi $versioneNuova
    if ($modo -eq 'installer') {
        Installa $Nuovo "$env:RUNNER_TEMP\installa-sopra.log"
    } else {
        Set-Content "$datiVecchi\aggiorna.request" 'aggiorna'
        $fine = (Get-Date).AddMinutes(9)  # di solito l'aggiornamento finisce in 2-3 minuti; piu' di 9 vuol dire che non e' partito
        function Versione-Installata { try { (Get-Content "$nuova\runtime\app\VERSION" -TotalCount 1 -ErrorAction Stop).Trim() } catch { '' } }
        $ultimaRichiesta = Get-Date; $ultimoRiavvio = Get-Date; $riavvii = 0
        while ((Get-Date) -lt $fine -and (Versione-Installata) -ne $versioneNuova) {
            Start-Sleep 10
            # Se dopo 3 minuti non si e' mosso niente (nessun file scaricato), come farebbe la persona si chiude e si riapre la
            # versione di prima: al riavvio ricontrolla gli aggiornamenti. Al massimo due volte.
            if ($riavvii -lt 2 -and (Get-Date) -gt $ultimoRiavvio.AddMinutes(3) -and -not (Test-Path "$datiVecchi\aggiornamenti")) {
                Write-Host "       NOTA: nessun aggiornamento dopo 3 minuti: riavvio la versione di prima (come farebbe la persona)"
                (Processi-Di $vecchia) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                Start-Sleep 8
                Accendi $vecchia
                Remove-Item "$datiVecchi\aggiorna.request" -Force -ErrorAction SilentlyContinue
                Set-Content "$datiVecchi\aggiorna.request" 'aggiorna'
                $riavvii++; $ultimoRiavvio = Get-Date; $ultimaRichiesta = Get-Date
            }
            # La versione di prima legge la richiesta solo a certi momenti: se e' ancora li dopo 2 minuti la si rifa, come chi preme di nuovo «Aggiorna».
            if ((Test-Path "$datiVecchi\aggiorna.request") -and ((Get-Date) -gt $ultimaRichiesta.AddMinutes(2))) {
                Remove-Item "$datiVecchi\aggiorna.request" -Force -ErrorAction SilentlyContinue
                Set-Content "$datiVecchi\aggiorna.request" 'aggiorna'
                $ultimaRichiesta = Get-Date
            }
        }
        if ((Versione-Installata) -ne $versioneNuova) {
            # Per capire dove si ferma: cosa ha scaricato, quali installer sono accesi, quali file ha la cartella dei dati.
            $scaricati = (Get-ChildItem "$datiVecchi\aggiornamenti" -Force -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name) $([math]::Round($_.Length / 1MB)) MB" }) -join ' ; '
            $installer = (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*AI-Brain-*windows-x64*' -or $_.Path -like '*\is-*.tmp\*' } | ForEach-Object { $_.Name }) -join ', '
            $accesi = (Processi-Di $vecchia).Count
            $dati = ((Get-ChildItem $datiVecchi -Force -ErrorAction SilentlyContinue | Select-Object -First 15).Name) -join ', '
            # Cosa dice la versione di prima nei suoi registri sugli aggiornamenti (solo le righe che ne parlano, le ultime).
            try {
                $righeLog = Get-ChildItem "$datiVecchi\logs" -File -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Tail 400 -ErrorAction SilentlyContinue } |
                    Where-Object { $_ -match 'aggiorn|update|feed|firma|signature|versione|version' } | Select-Object -Last 12
                foreach ($riga in $righeLog) { Write-Host "       NOTA log: $((([string]$riga) -replace '[^\x20-\x7E]', '?').Trim().Substring(0, [Math]::Min(200, ([string]$riga).Trim().Length)))" }
                if (-not $righeLog) { Write-Host "       NOTA log: nessuna riga sugli aggiornamenti nei registri della versione di prima" }
            } catch { }
            Write-Host "       NOTA: aggiornamento dall'app fermo. scaricati: [$scaricati]; installer accesi: [$installer]; programmi della versione di prima accesi: $accesi; file dei dati: [$dati]"
        }
        Controlla ((Versione-Installata) -eq $versioneNuova) 'l''app ha scaricato e installato la versione nuova da sola'
        Remove-Item Env:\AI_BRAIN_UPDATES_URL -ErrorAction SilentlyContinue
    }
    Start-Sleep 3
    if ($separata) {
        Controlla ((Processi-Di $vecchia).Count -eq 0) 'nessun programma della versione di prima e'' rimasto acceso'
    }
    # VERSION viene copiato prima dell'eseguibile: il nuovo numero può comparire mentre l'installer sta ancora
    # copiando il runtime. Il monitor dell'Engine è già acceso, quindi questa attesa non nasconde il primo avvio.
    $exeNuovo = "$nuova\runtime\python\Memdoria AI Brain.exe"
    $fineExe = (Get-Date).AddMinutes(3)
    while (-not (Test-Path $exeNuovo) -and (Get-Date) -lt $fineExe) { Start-Sleep -Seconds 2 }
    Controlla (Test-Path $exeNuovo) 'la versione nuova e'' in Programs\Memdoria-AI-Brain'
    $verInstallata = [string](Get-Content "$nuova\runtime\app\VERSION" -TotalCount 1 -ErrorAction SilentlyContinue)
    Richiedi ($verInstallata.Trim() -eq $versioneNuova) "i file installati sono davvero della $versioneNuova"

    # L'installer può ancora copiare file e preparare la riapertura quando VERSION ed eseguibile sono già presenti.
    # Il monitor dell'Engine è partito prima dell'aggiornamento: questa attesa non nasconde uno stato Errore.
    $fineInstaller = (Get-Date).AddMinutes(6)
    while ((Get-Date) -lt $fineInstaller -and (Installer-InCorso)) { Start-Sleep -Seconds 5 }
    Richiedi (-not (Installer-InCorso)) "l'installer della $versioneNuova ha finito prima di controllare la riapertura ($modo)"

    # La versione nuova deve avere un processo tray diverso da quello della versione precedente.
    # Nel percorso dall'app la riapertura automatica e' parte del collaudo; l'installer silenzioso puo' richiedere un avvio manuale.
    $fineTray = (Get-Date).AddSeconds($(if ($modo -eq 'app') { 90 } else { 15 })); $nuovoTray = @()
    while ((Get-Date) -lt $fineTray) {
        $nuovoTray = @(Processi-Di $nuova | Where-Object { $_.CommandLine -match 'tray\.py' -and $_.ProcessId -notin $pidVecchi })
        if ($nuovoTray.Count -gt 0) { break }
        Start-Sleep -Seconds 2
    }
    if ($nuovoTray.Count -eq 0 -and $modo -eq 'installer') {
        Accendi $nuova
        Start-Sleep -Seconds 3
        $nuovoTray = @(Processi-Di $nuova | Where-Object { $_.CommandLine -match 'tray\.py' -and $_.ProcessId -notin $pidVecchi })
    }
    Richiedi ($nuovoTray.Count -gt 0) "prima riapertura della $versioneNuova con un nuovo processo ($modo)"
    $datiNuovi = "$Local\Memdoria-AI-Brain"
    # Il primo avvio può impiegare oltre un minuto per accendere grafo e ricerca. Il job osserva già l'Engine
    # dall'inizio dell'installazione: attendere il suo esito non perde un eventuale stato Errore temporaneo.
    $finitoMotore = Wait-Job -Job $osservaMotore -Timeout 180
    $esitoMotore = if ($finitoMotore) { Receive-Job -Job $osservaMotore -ErrorAction SilentlyContinue | Select-Object -Last 1 } `
        else { [pscustomobject]@{ visto = $false; errore = $false; motivo = 'monitor non terminato entro 180 secondi' } }
    if (-not $finitoMotore) { Stop-Job -Job $osservaMotore -ErrorAction SilentlyContinue }
    Remove-Job -Job $osservaMotore -Force -ErrorAction SilentlyContinue
    Controlla ($null -ne $esitoMotore -and $esitoMotore.visto -and -not $esitoMotore.errore) `
        "Engine senza stato Errore durante la prima riapertura dopo $verVecchia ($modo): $($esitoMotore.motivo)"
    Pagina-Primo-Avvio $datiNuovi $verVecchia $modo
    $p = Aspetta-Lettura $datiNuovi
    Richiedi ($null -ne $p -and -not $p.error) "dopo l'aggiornamento la lettura finisce senza errori ($($p.error))"
    if ($separata) {
        # La cartella di prima la toglie l'installer, o al piu' l'app nuova alla sua apertura: qui l'app nuova e' accesa e ha letto.
        # L'installer toglie la cartella di prima DOPO aver copiato la nuova (1,8 GB di file): si aspetta che abbia finito, e si dice quanto.
        $inizioInstaller = Get-Date
        while ((Get-Date) -lt $inizioInstaller.AddMinutes(6) -and @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*AI-Brain-*windows-x64*' -or $_.Path -like '*\is-*.tmp\*' }).Count -gt 0) { Start-Sleep 5 }
        Write-Host "       NOTA: l'installer e' ancora acceso? $(@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*AI-Brain-*windows-x64*' -or $_.Path -like '*\is-*.tmp\*' }).Count -gt 0); attesa $([int]((Get-Date) - $inizioInstaller).TotalSeconds) s"
        $fineTolta = (Get-Date).AddSeconds(60)
        while ((Test-Path $vecchia) -and (Get-Date) -lt $fineTolta) { Start-Sleep 5 }
        $rimasto = if (Test-Path $vecchia) { ((Get-ChildItem $vecchia -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { $_.FullName.Substring($vecchia.Length) }) -join ' ; ') } else { '' }
        # Il programma della versione di prima non deve esserci piu': i dati della persona stanno altrove (AppData\Local\Memdoria).
        # Si ricorda se c'era PRIMA di provare a toglierla a mano (per capire chi la teneva), e il controllo e' su quello.
        $esiste = Test-Path $vecchia
        if ($esiste) {
            try { Remove-Item $vecchia -Recurse -Force -ErrorAction Stop; Write-Host '       NOTA: la cartella si e'' lasciata togliere a mano: nessun programma la teneva occupata' }
            catch {
                $chi = (Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$vecchia\*" -or $_.CommandLine -like "*$vecchia*" } | ForEach-Object { "$($_.Name)($($_.ProcessId))" }) -join ', '
                # Chi la tiene occupata: lo strumento «handle» di Microsoft (solo qui, su una macchina usa e getta, solo per capire).
                try {
                    $strumento = "$env:RUNNER_TEMP\handle64.exe"
                    if (-not (Test-Path $strumento)) { Invoke-WebRequest 'https://live.sysinternals.com/handle64.exe' -OutFile $strumento -UseBasicParsing -TimeoutSec 60 }
                    $righe = & $strumento -accepteula -nobanner "Programs\Memdoria" 2>&1 | Where-Object { $_ -match '\S' } | Select-Object -First 12
                    foreach ($riga in $righe) {
                        Write-Host "       NOTA handle: $(([string]$riga).Trim())"
                        if (([string]$riga) -match 'pid:\s*(\d+)') {
                            $chi = Get-CimInstance Win32_Process -Filter "ProcessId=$($Matches[1])" -ErrorAction SilentlyContinue
                            $padre = if ($chi) { Get-CimInstance Win32_Process -Filter "ProcessId=$($chi.ParentProcessId)" -ErrorAction SilentlyContinue } else { $null }
                            $comando = if ($chi) { ([string]$chi.CommandLine); } else { '?' }
                            Write-Host "       NOTA   comando: $($comando.Substring(0, [Math]::Min(200, $comando.Length))); lanciato da: $(if ($padre) { "$($padre.Name) ($($padre.ProcessId))" } else { '?' }); questo collaudo e' il processo $PID"
                        }
                    }
                } catch { Write-Host "       NOTA handle: non disponibile ($($_.Exception.Message))" }
                Write-Host "       NOTA: la cartella e' occupata ($(([string]$_.Exception.Message).Substring(0, [Math]::Min(230, ([string]$_.Exception.Message).Length)))); programmi della cartella vecchia: $chi"
            }
        }
        Controlla (-not $esiste) "la cartella Programs\Memdoria e' stata tolta (rimasto: $rimasto)"
    }
    if ($separata) {
        $link = Get-Item "$Local\Memdoria" -Force -ErrorAction SilentlyContinue
        Controlla ($null -ne $link -and $link.LinkType -eq 'Junction') 'trasloco fatto: "Memdoria" e'' un collegamento verso "Memdoria-AI-Brain"'
    } else { Write-Host "       la $verVecchia ha gia' i dati in Memdoria: niente trasloco da controllare" }
    Controlla (Test-Path "$datiNuovi\config.json") 'i dati stanno in Memdoria-AI-Brain'
    $cartellaTecnica = Get-Item "$env:USERPROFILE\.config\ai-brain" -Force -ErrorAction SilentlyContinue
    Controlla ($null -ne $cartellaTecnica -and $cartellaTecnica.LinkType -eq 'Junction' -and (Test-Path "$env:USERPROFILE\.config\memdoria-ai-brain\token")) 'la cartella tecnica e'' stata spostata con un collegamento per la versione di prima'
    $dopo = Statistiche $datiNuovi
    Controlla ($dopo.memories -ge $prima.memories) "memorie intatte: prima $($prima.memories), dopo $($dopo.memories)"
    Controlla ($dopo.conversations -ge 3) "conversazioni trovate dopo l'aggiornamento: $($dopo.conversations)"
    if ($separata) { Controlla ((Processi-Di $vecchia).Count -eq 0) 'ancora nessuna versione di prima accesa' }
    Controlla ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) -match 'Programs\\Memdoria-AI-Brain') 'l''avvio automatico punta alla cartella nuova'
    if ($haVoci) {
        $voci = Get-Content "$env:USERPROFILE\.claude.json" -Raw
        Controlla (($voci -match '"memdoria-ai-brain"') -and ($voci -notmatch '"ai-brain"') -and ($voci -notmatch 'Local[\\/]+Memdoria"')) 'le voci delle AI usano il nome nuovo e non puntano piu'' alla cartella vecchia'
        if (Test-Path "$env:USERPROFILE\.codex\config.toml") {
            $codex = Get-Content "$env:USERPROFILE\.codex\config.toml" -Raw
            Controlla (($codex -match 'mcp_servers\.memdoria-ai-brain') -and ($codex -notmatch 'mcp_servers\.ai-brain')) 'anche Codex usa la voce nuova'
        }
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
    foreach ($d in $script:UltimiDati + "$Local\Memdoria-AI-Brain") { if (Test-Path "$d\logs\launcher.log") { "--- $d" | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log"; Get-Content "$d\logs\launcher.log" -Tail 80 -Encoding UTF8 | Add-Content "$env:RUNNER_TEMP\riservato\dettagli.log" } }
    exit 1
}
Write-Host "`nCOLLAUDO RIUSCITO" -ForegroundColor Green
