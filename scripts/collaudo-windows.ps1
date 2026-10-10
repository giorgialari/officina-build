# Collaudo di installazione e aggiornamento su Windows (macchina pulita di GitHub).
#   A. installazione pulita della versione nuova: trova le chat delle AI, grafo, nessun errore
#   B. aggiornamento: installa la vecchia, la accende, salva due memorie, lancia l'installer nuovo SOPRA mentre e' accesa,
#      poi controlla trasloco dei dati, nessuna vecchia accesa, memorie intatte e conversazioni trovate.
# Uso: collaudo-windows.ps1 -Vecchio <exe> -Nuovo <exe> -Codice <cartella del codice> -Chiave <chiave privata di prova>
param([Parameter(Mandatory)][string]$Vecchio, [Parameter(Mandatory)][string]$Nuovo,
      [Parameter(Mandatory)][string]$Codice, [Parameter(Mandatory)][string]$Chiave)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Local = $env:LOCALAPPDATA
$Programmi = "$Local\Programs"
$Fallimenti = New-Object System.Collections.Generic.List[string]

# Niente rete per la licenza: la chiave e' firmata con la chiave di prova e vale 3 giorni dal giorno in cui e' fatta.
$env:AI_BRAIN_LICENSE_CHECK_URL = 'http://127.0.0.1:9/controlla'
$env:AI_BRAIN_LICENSE_URL = 'http://127.0.0.1:9/attiva'

function Say($m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
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
    $codice = Codice-Computer $app
    New-Item -ItemType Directory -Force $dati | Out-Null
    $chiavi = "$env:USERPROFILE\.config\ai-brain-licenze"
    New-Item -ItemType Directory -Force $chiavi | Out-Null
    Copy-Item $Chiave "$chiavi\chiave-privata.pem" -Force
    $licenza = (& python "$Codice\backend\app\licenza.py" nuova --nome 'Collaudo' --email 'collaudo@example.invalid' --computer $codice --mesi 1 | Select-Object -Last 1).Trim()
    Controlla ($licenza -like 'AIB1.*') 'licenza di prova creata'
    [IO.File]::WriteAllText("$dati\licenza.txt", $licenza)
}

function Accendi([string]$app) {
    Start-Process "$app\runtime\python\AI Brain.exe" -ArgumentList '-E', '-s', '-S', "`"$app\runtime\app\tray.py`"" -WorkingDirectory $app | Out-Null
}

function Aspetta-Lettura([string]$dati, [int]$minuti = 12) {
    $fine = (Get-Date).AddMinutes($minuti)
    while ((Get-Date) -lt $fine) {
        Start-Sleep 10
        Remove-Item "$dati\lingua-da-scegliere" -Recurse -Force -ErrorAction SilentlyContinue   # come scegliere la lingua
        try { $p = Get-Content "$dati\progress.json" -Raw -Encoding UTF8 | ConvertFrom-Json; if ($p.done -or $p.error) { return $p } } catch { }
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

function Processi-Di([string]$cartella) {
    @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$cartella\*" })
}

function Spegni-Tutto {
    Get-Process | Where-Object { $_.Path -like "$Programmi\*" } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep 5
}

function Disinstalla-Tutto {
    Spegni-Tutto
    foreach ($u in (Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object { Get-ItemProperty $_.PSPath } |
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
Say 'A. Installazione pulita della versione nuova'
Installa $Nuovo "$env:RUNNER_TEMP\installa-nuovo.log"
$app = Cartella-App 'Memdoria'
Controlla (Test-Path "$app\runtime\python\AI Brain.exe") 'l''app e'' in Programs\Memdoria'
$dati = "$Local\Memdoria"
Metti-Licenza $app $dati
Accendi $app
$p = Aspetta-Lettura $dati
Controlla ($null -ne $p -and -not $p.error) "la prima lettura finisce senza errori ($($p.error))"
if ($p) { $p.events | ForEach-Object { Write-Host "       $($_.text)" } }
$s = Statistiche $dati
Controlla ($s.conversations -ge 3) "conversazioni trovate: $($s.conversations) (attese almeno 3: Antigravity, Gemini CLI, Claude Code)"
Controlla (-not (Test-Path "$Local\AI Brain")) 'nessuna cartella "AI Brain" in una installazione nuova'
Disinstalla-Tutto

# ---------------------------------------------------------------------------------------------------------------------
Say 'B. Aggiornamento: installer nuovo lanciato SOPRA la versione di prima accesa'
Installa $Vecchio "$env:RUNNER_TEMP\installa-vecchio.log"
$vecchia = Cartella-App 'AI Brain'
Controlla (Test-Path "$vecchia\runtime\python\AI Brain.exe") 'la versione di prima e'' in Programs\AI Brain'
$datiVecchi = "$Local\AI Brain"
Metti-Licenza $vecchia $datiVecchi
Accendi $vecchia
$p = Aspetta-Lettura $datiVecchi
Controlla ($null -ne $p -and -not $p.error) "la versione di prima finisce la lettura ($($p.error))"
Salva-Memoria $datiVecchi 'Il cliente Verdi Srl usa il gestionale Alfa dal 2024.'
Salva-Memoria $datiVecchi 'Il server di Verdi Srl e in Hetzner a Norimberga.'
$prima = Statistiche $datiVecchi
Controlla ($prima.memories -ge 2) "memorie salvate prima dell'aggiornamento: $($prima.memories)"
Controlla ((Processi-Di $vecchia).Count -gt 0) 'la versione di prima e'' accesa quando parte l''installer'

Installa $Nuovo "$env:RUNNER_TEMP\installa-sopra.log"
Start-Sleep 10
Controlla ((Processi-Di $vecchia).Count -eq 0) 'nessun programma della versione di prima e'' rimasto acceso'
Controlla (-not (Test-Path $vecchia)) 'la cartella Programs\AI Brain e'' stata tolta'
$nuova = Cartella-App 'Memdoria'
Controlla (Test-Path "$nuova\runtime\python\AI Brain.exe") 'la versione nuova e'' in Programs\Memdoria'

Accendi $nuova
$datiNuovi = "$Local\Memdoria"
$p = Aspetta-Lettura $datiNuovi
Controlla ($null -ne $p -and -not $p.error) "dopo l'aggiornamento la lettura finisce senza errori ($($p.error))"
$link = Get-Item "$Local\AI Brain" -Force -ErrorAction SilentlyContinue
Controlla ($null -ne $link -and $link.LinkType -eq 'Junction') 'trasloco fatto: "AI Brain" e'' un collegamento verso "Memdoria"'
Controlla (Test-Path "$datiNuovi\config.json") 'i dati stanno in Memdoria'
$dopo = Statistiche $datiNuovi
Controlla ($dopo.memories -ge $prima.memories) "memorie intatte: prima $($prima.memories), dopo $($dopo.memories)"
Controlla ($dopo.conversations -ge 3) "conversazioni trovate dopo l'aggiornamento: $($dopo.conversations)"
Controlla ((Processi-Di $vecchia).Count -eq 0) 'ancora nessuna versione di prima accesa'
Controlla ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String) -notmatch 'Programs\\AI Brain') 'l''avvio automatico non punta piu'' alla cartella vecchia'

Say 'Esito'
Spegni-Tutto
if ($Fallimenti.Count -gt 0) {
    Write-Host "`nCOLLAUDO FALLITO ($($Fallimenti.Count)):" -ForegroundColor Red
    $Fallimenti | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    foreach ($d in $datiVecchi, $datiNuovi, "$Local\Memdoria") { if (Test-Path "$d\logs\launcher.log") { Write-Host "--- $d\logs\launcher.log"; Get-Content "$d\logs\launcher.log" -Tail 40 -Encoding UTF8 } }
    exit 1
}
Write-Host "`nCOLLAUDO RIUSCITO" -ForegroundColor Green
