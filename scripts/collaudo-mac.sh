#!/usr/bin/env bash
# Collaudo su Mac (macchina pulita di GitHub): installazione pulita della versione nuova e AGGIORNAMENTO DALL'APP dalla
# versione di prima, come lo fa la persona (l'app scarica, installa e si riapre da sola). Chiavi di prova, mai quelle vere.
# Uso: collaudo-mac.sh <dmg vecchio> <dmg nuovo> <codice> <chiave di prova>
set -u
VECCHIO=$1; NUOVO=$2; CODICE=$3; CHIAVE=$4
KO=0
ok()   { echo "  OK   $1"; }
male() { echo "  MALE $1"; KO=$((KO+1)); }
controlla() { if [ "$1" = 0 ]; then ok "$2"; else male "$2"; fi; }
# Un passo da cui dipende tutto il resto: se fallisce il collaudo si ferma qui, con i dettagli cifrabili.
richiedi() {
  if [ "$1" = 0 ]; then ok "$2"; return 0; fi
  male "$2"
  echo "  STOP il collaudo si ferma qui: senza questo passo il resto non ha senso"
  mkdir -p "$RUNNER_TEMP/riservato"
  for l in "$RUNNER_TEMP"/app-*.log; do [ -f "$l" ] && { echo "--- $l"; tail -80 "$l"; } >> "$RUNNER_TEMP/riservato/dettagli.log"; done
  for d in "$HOME/Library/Application Support/AI Brain" "$HOME/Library/Application Support/Memdoria" "$HOME/Library/Application Support/Memdoria-AI-Brain"; do
    [ -f "$d/logs/launcher.log" ] && { echo "--- $d"; tail -80 "$d/logs/launcher.log"; } >> "$RUNNER_TEMP/riservato/dettagli.log"
  done
  echo "COLLAUDO FALLITO ($KO controlli)"
  exit 1
}
say() { printf '\n=== %s\n' "$1"; }

export AI_BRAIN_LICENSE_CHECK_URL=http://127.0.0.1:9/controlla AI_BRAIN_LICENSE_URL=http://127.0.0.1:9/attiva
SUPPORTO="$HOME/Library/Application Support"
python3 -m pip install --quiet --break-system-packages cryptography 2>/dev/null || python3 -m pip install --quiet cryptography

chat_finte() {
  mkdir -p "$HOME/.gemini/antigravity/brain/8bd7e99a/.system_generated/logs" "$HOME/.gemini/tmp/h1/chats" "$HOME/.claude/projects/-lavoro-sito" "$HOME/.codex"
  # Le chat importate non installano Claude Code: nel collaudo lo rappresenta un eseguibile di prova,
  # così il collegamento viene verificato solo per un client davvero presente sul computer usa e getta.
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/claude"
  chmod 755 "$HOME/.local/bin/claude"
  python3 - <<'PY'
import json, os
h = os.path.expanduser("~")
with open(f"{h}/.gemini/antigravity/brain/8bd7e99a/.system_generated/logs/transcript.jsonl", "w") as f:
    for r in [{"source": "SYSTEM", "type": "SYSTEM_MESSAGE", "content": "avviso"},
              {"source": "USER_EXPLICIT", "type": "USER_INPUT", "created_at": "2026-10-06T16:46:33Z", "content": "<USER_REQUEST>\nIl cliente Rossi Srl vuole il sito con prenotazioni online\n</USER_REQUEST>"},
              {"source": "MODEL", "type": "PLANNER_RESPONSE", "created_at": "2026-10-06T16:46:40Z", "content": "Preparo il progetto per Rossi Srl."}]:
        f.write(json.dumps(r) + "\n")
json.dump({"sessionId": "g1", "messages": [{"type": "user", "timestamp": "2026-10-01T10:00:00Z", "content": "Come imposto il dominio del sito di Verdi Srl?"},
                                           {"type": "gemini", "content": "Punta il record A al server e attiva il certificato."}]},
          open(f"{h}/.gemini/tmp/h1/chats/session-1.json", "w"))
with open(f"{h}/.claude/projects/-lavoro-sito/s1.jsonl", "w") as f:
    f.write(json.dumps({"type": "user", "sessionId": "s1", "cwd": "/lavoro/sito", "timestamp": "2026-10-02T09:00:00Z", "message": {"role": "user", "content": "Il cliente Bianchi Srl vuole il gestionale con Angular"}}) + "\n")
    f.write(json.dumps({"type": "assistant", "sessionId": "s1", "timestamp": "2026-10-02T09:00:05Z", "message": {"role": "assistant", "content": [{"type": "text", "text": "Preparo il progetto Angular per Bianchi Srl."}]}}) + "\n")
PY
}

monta_e_copia() {  # <dmg> <nome dell'app nel dmg> -> /Applications
  local punto; punto=$(mktemp -d)
  hdiutil attach "$1" -nobrowse -readonly -mountpoint "$punto" > /dev/null || return 1
  rm -rf "/Applications/$2"; cp -R "$punto/$2" /Applications/ ; local r=$?
  hdiutil detach "$punto" -quiet || true
  return $r
}

licenza() {  # <app> <cartella dati>
  local app=$1 dati=$2 codice
  codice=$("$app/Contents/Resources/runtime/python/bin/python3.12" -E -s -S -c "import sys;sys.path.insert(0,'$app/Contents/Resources/runtime/app');import licenza;print(licenza.machine_code())")
  mkdir -p "$HOME/.config/ai-brain-licenze" "$dati"
  cp "$CHIAVE" "$HOME/.config/ai-brain-licenze/chiave-privata.pem"
  python3 "$CODICE/backend/app/licenza.py" nuova --nome Collaudo --email collaudo@example.invalid --computer "$codice" --mesi 1 | tail -1 | tr -d '\n' > "$dati/licenza.txt"
  head -c 5 "$dati/licenza.txt" | grep -q 'AIB1\.' ; richiedi $? "licenza di prova creata"
}

accendi() { nohup "$1" > "$RUNNER_TEMP/app-$2.log" 2>&1 & }

aspetta_lettura() {  # <dati> -> 0 se finita senza errori
  # «finita» = done (conferma della finestra) oppure «Fatto» (versioni nuove) oppure, per le versioni vecchie che non lo
  # scrivono, 60 secondi dopo «Grafo»/«Pronto» (le entita' arrivano un attimo dopo).
  local dati=$1 i visto=0
  for i in $(seq 1 90); do
    sleep 10; rm -rf "$dati/lingua-da-scegliere"
    if [ -f "$dati/progress.json" ]; then
      python3 "$(dirname "$0")/lettura_finita.py" "$dati/progress.json"
      case $? in
        0) return 0 ;;
        2) return 2 ;;
        3) visto=$((visto+1)); [ "$visto" -ge 6 ] && return 0 ;;
      esac
    fi
  done
  return 1
}

api() {  # <dati> <metodo> <percorso> [corpo]
  local dati=$1 cfg token porta
  token=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['brain_token'])" "$dati/config.json")
  porta=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['brain_port'])" "$dati/config.json")
  if [ -n "${4:-}" ]; then curl -fsS -X "$2" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d "$4" "http://127.0.0.1:$porta$3"
  else curl -fsS -X "$2" -H "Authorization: Bearer $token" "http://127.0.0.1:$porta$3"; fi
}
conta() { api "$1" GET /admin/stats | python3 -c "import json,sys;print(json.load(sys.stdin)['$2'])"; }
seme_connessione() {  # <dati>: la persona ha risposto «si» alla domanda «Le collego a Memdoria?» (si salva in config.json)
  mkdir -p "$1"; [ -f "$1/config.json" ] || echo '{"connect_answer": "yes"}' > "$1/config.json"
}
collega_ai() {  # <dati> <nome della voce> -> 0 se compare nei file di Claude Code
  local i nome=${2:-memdoria-ai-brain}
  for i in $(seq 1 24); do grep -q "\"$nome\"" "$HOME/.claude.json" 2>/dev/null && return 0; sleep 5; done
  return 1
}
lingua_si_cambia() {  # <dati>
  local cfg porta
  porta=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['brain_port'])" "$1/config.json")
  curl -fsS -X PUT -H 'Content-Type: application/json' -d '{"lingua":"en"}' "http://127.0.0.1:$porta/api/lingua" > /dev/null || return 1
  curl -fsS "http://127.0.0.1:$porta/api/lingua" | grep -q '"lingua":"en"' || return 1
  curl -fsS -X PUT -H 'Content-Type: application/json' -d '{"lingua":"it"}' "http://127.0.0.1:$porta/api/lingua" > /dev/null || return 1
  curl -fsS "http://127.0.0.1:$porta/api/lingua" | grep -q '"lingua":"it"'
}
pagina_nel_browser() {  # <dati> <quando>
  command -v node > /dev/null || return 0
  local porta; porta=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['brain_port'])" "$1/config.json")
  local uscita r; uscita=$(node "$(dirname "$0")/pagina.mjs" "http://127.0.0.1:$porta/app/" "$RUNNER_TEMP/pagina-mac-${2// /-}" 2>&1); r=$?
  uscita=$(printf '%s' "$uscita" | tail -1)
  controlla $r "la pagina si apre nel browser e disegna il grafo ($2): $uscita"
}
controlla_primo_avvio() {  # <dati>: nella prima finestra, un server lento mostra l'attesa e poi il grafo
  local porta uscita r i
  for i in $(seq 1 120); do [ -f "$1/config.json" ] && break; sleep 0.5; done
  [ -f "$1/config.json" ] || { controlla 1 "prima riapertura dopo $VER_V: configurazione non pronta"; return; }
  porta=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['brain_port'])" "$1/config.json")
  uscita=$(node "$(dirname "$0")/pagina.mjs" "http://127.0.0.1:$porta/app/" "$RUNNER_TEMP/primo-avvio-mac-$VER_V" --server-in-riavvio 2>&1); r=$?
  controlla $r "prima riapertura dopo $VER_V: attesa pulita e ritorno del grafo senza riavviare: $(printf '%s' "$uscita" | tail -1)"
}
controlla_motore() {  # <dati nuovi> <versione nuova> <dati vecchi>: osserva la PRIMA riapertura
  local dati=$1 versione_nuova=$2 dati_vecchi=$3 porta stato visto=0 i config versione_attiva="" fine
  # Parte prima della richiesta di aggiornamento. L'endpoint /api/setup-info identifica il processo nuovo:
  # altrimenti si potrebbe scambiare lo stato sano della versione vecchia con quello della prima riapertura.
  fine=$(($(date +%s) + 720))
  while [ "$(date +%s)" -lt "$fine" ]; do
    for config in "$dati/config.json" "$dati_vecchi/config.json"; do
      [ -f "$config" ] || continue
      porta=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('brain_port',''))" "$config" 2>/dev/null)
      [ -n "$porta" ] || continue
      versione_attiva=$(curl -fsS --max-time 1 "http://127.0.0.1:$porta/api/setup-info" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('version',''))" 2>/dev/null)
      [ "$versione_attiva" = "$versione_nuova" ] && break 2
    done
    sleep 0.25
  done
  [ "$versione_attiva" = "$versione_nuova" ] || return 1
  for i in $(seq 1 160); do
    if [ -f "$dati/config.json" ]; then
      porta=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('brain_port',''))" "$dati/config.json" 2>/dev/null)
      if [ -n "$porta" ]; then
        stato=$(curl -fsS --max-time 1 "http://127.0.0.1:$porta/api/modello-locale/stato" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('stato',''))" 2>/dev/null)
        [ "$stato" = errore ] && return 1
        [ -n "$stato" ] && visto=1
      fi
    fi
    sleep 0.25
  done
  [ "$visto" = 1 ]
}
controlla_nome_dock() {  # LaunchServices: aspetta l'istanza FINALE dopo migrazione e riavvio automatico
  local i
  for i in $(seq 1 180); do
    lsappinfo list | python3 -c '
import os, plistlib, re, sys
blocchi = re.split(r"(?m)^\s*\d+\)\s+", sys.stdin.read())
app = [b for b in blocchi if "bundleID=\"it.aibrain.app\"" in b]
if len(app) != 1 or not app[0].startswith("\"Memdoria AI Brain\"") or "bundle path=\"/Applications/Memdoria AI Brain.app\"" not in app[0]:
    sys.exit(1)
pid = re.search(r"pid = (\d+)", app[0])
if not pid: sys.exit(1)
try: os.kill(int(pid.group(1)), 0)
except OSError: sys.exit(1)
with open("/Applications/Memdoria AI Brain.app/Contents/Info.plist", "rb") as f: info = plistlib.load(f)
sys.exit(0 if info.get("CFBundleVersion") == sys.argv[1] else 1)
' "$VERSIONE_NUOVA" && return 0
    sleep 1
  done
  return 1
}
prepara_feed_pulsante() {
  local versione futura
  versione=$(cat "$CODICE/VERSION")
  futura="${versione%.*}.$((${versione##*.}+1))"
  mkdir -p "$RUNNER_TEMP/feed-pulsante"
  FEED_ATTIVO="$RUNNER_TEMP/feed-pulsante/ultima-versione.json"
  FEED_NUOVO="$RUNNER_TEMP/feed-pulsante/versione-nuova.json"
  python3 "$(dirname "$0")/feed.py" "$CODICE" "$CHIAVE" "$FEED_ATTIVO" "$versione" mac "$NUOVO" "file://$NUOVO" > /dev/null || return 1
  python3 "$(dirname "$0")/feed.py" "$CODICE" "$CHIAVE" "$FEED_NUOVO" "$futura" mac "$NUOVO" "file://$NUOVO" > /dev/null || return 1
  export AI_BRAIN_UPDATES_URL="file://$FEED_ATTIVO" AI_BRAIN_AGGIORNA_OGNI=5
}
controlla_pulsante_aggiornamento() {
  local porta uscita r
  porta=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['brain_port'])" "$1/config.json")
  uscita=$(node "$(dirname "$0")/pagina.mjs" "http://127.0.0.1:$porta/app/" "$RUNNER_TEMP/pulsante-mac" --pulsante-aggiornamento "$FEED_NUOVO" "$FEED_ATTIVO" 2>&1); r=$?
  controlla $r "il pulsante in alto a destra si attiva senza riavvio dopo il cambio del feed: $(printf '%s' "$uscita" | tail -1)"
}
spegni() { pkill -f "Contents/Resources/runtime" 2>/dev/null; sleep 5; pkill -9 -f "Contents/Resources/runtime" 2>/dev/null; sleep 2; }

chat_finte
bash "$(dirname "$0")/controlla-dmg-mac.sh" "$NUOVO"; richiedi $? "il disco mostra una sola app e Applicazioni"

if [ "${CON_PULITA:-true}" = true ]; then
say "A. Installazione pulita della versione nuova"
monta_e_copia "$NUOVO" "Memdoria AI Brain.app"; controlla $? "Memdoria AI Brain.app copiata in Applicazioni"
DATI="$SUPPORTO/Memdoria-AI-Brain"
licenza "/Applications/Memdoria AI Brain.app" "$DATI"
CACHE_MODELLO="$RUNNER_TEMP/modello"
if ls "$CACHE_MODELLO"/*.gguf > /dev/null 2>&1; then mkdir -p "$DATI/modello-locale" && cp "$CACHE_MODELLO"/* "$DATI/modello-locale/" && echo "       modello preso dalla cache"; fi
seme_connessione "$DATI"
prepara_feed_pulsante; richiedi $? "elenco di prova preparato per il pulsante degli aggiornamenti"
accendi "/Applications/Memdoria AI Brain.app/Contents/MacOS/Memdoria" nuova
aspetta_lettura "$DATI"; richiedi $? "la prima lettura finisce senza errori"
C=$(conta "$DATI" conversations); [ "${C:-0}" -ge 3 ]; controlla $? "conversazioni trovate: ${C:-0} (attese almeno 3)"
# Una memoria con un cliente: il grafo deve mostrarlo (cio che l'AI ricava dalle chat finte puo' variare da giro a giro).
api "$DATI" POST /admin/remember '{"text":"Il cliente Verdi Srl usa il gestionale Alfa dal 2024.","kind":"fact","source":"collaudo","source_ai":"collaudo","entities":[{"name":"Verdi Srl","type":"client"}]}' > /dev/null
for i in $(seq 1 12); do E=$(conta "$DATI" active_entities); [ "${E:-0}" -ge 1 ] && break; sleep 10; done; [ "${E:-0}" -ge 1 ]; controlla $? "il grafo si riempie: ${E:-0} entita, $(conta "$DATI" active_memories) memorie"
[ ! -e "$SUPPORTO/AI Brain" ] && [ ! -e "$SUPPORTO/Memdoria" ]; controlla $? "nessuna cartella dati col nome di prima in un'installazione nuova"
"/Applications/Memdoria AI Brain.app/Contents/Resources/runtime/python/bin/python3.12" -E -s "$(dirname "$0")/licenze-offline.py" "/Applications/Memdoria AI Brain.app/Contents/Resources/runtime/app" "$CHIAVE"; controlla $? "gli stati della licenza (manca, giusta, scaduta, altro computer, firma rovinata) sull'app installata"
collega_ai "$DATI"; controlla $? "collega le AI: la voce di Memdoria compare nei file di Claude Code"
lingua_si_cambia "$DATI"; controlla $? "il cambio lingua (inglese e di nuovo italiano) si salva"
# Memdoria AI: scarica il suo modello e lavora (fino a 20 minuti)
modello=1
for i in $(seq 1 60); do ls "$DATI"/modello-locale/*.gguf.ok > /dev/null 2>&1 && { modello=0; break; }; sleep 20; done
controlla $modello "Memdoria AI ha scaricato il suo modello"
if [ "$modello" = 0 ]; then
  inizio=$(conta "$DATI" memories); lavora=1
  for i in $(seq 1 30); do [ -f "$DATI/modello-locale/stato.json" ] || [ "$(conta "$DATI" memories)" -gt "${inizio:-0}" ] && { lavora=0; break; }; sleep 20; done
  controlla $lavora "Memdoria AI ha cominciato a lavorare sulle conversazioni"
fi
pagina_nel_browser "$DATI" "installazione pulita"
controlla_pulsante_aggiornamento "$DATI"
if ls "$DATI"/modello-locale/*.gguf.ok > /dev/null 2>&1 && ! ls "$CACHE_MODELLO"/*.gguf > /dev/null 2>&1; then
  mkdir -p "$CACHE_MODELLO" && cp "$DATI"/modello-locale/*.gguf* "$CACHE_MODELLO"/ && echo "       modello salvato per la prossima volta"
fi
# Disinstallazione (come «Disinstalla Memdoria» nella pagina): programmi spenti, dati tolti, voci delle AI tolte
echo '{"dati": true, "backup": false}' > "$DATI/disinstalla.request"
for i in $(seq 1 60); do sleep 5; pgrep -f "Contents/Resources/runtime" > /dev/null || break; done
! pgrep -f "Contents/Resources/runtime" > /dev/null; controlla $? "dopo la disinstallazione nessun programma e' acceso"
# La cartella dei dati la toglie l'ultimo passo della disinstallazione, anche un attimo dopo che i programmi sono usciti.
for i in $(seq 1 12); do [ ! -d "$DATI" ] && break; sleep 5; done
[ ! -d "$DATI" ]; controlla $? "dopo la disinstallazione i dati sono stati tolti (rimasto: $(ls -A "$DATI" 2>/dev/null | head -5 | tr '\n' ' '))"
! grep -q 'memdoria-ai-brain' "$HOME/.claude.json" 2>/dev/null; controlla $? "dopo la disinstallazione le voci delle AI sono state tolte"
spegni
rm -rf "/Applications/Memdoria AI Brain.app" /Applications/Memdoria-AI-Brain.app /Applications/Memdoria.app "$DATI"

fi

if [ "${SOLO_PULITA:-false}" != true ]; then
say "B. Aggiornamento dall'app dalla versione di prima"
# Le versioni distribuite usano tre nomi del bundle; dalla 1.0.33 i dati hanno lo stesso percorso.
VER_V=$(basename "$VECCHIO" | sed -E 's/^AI-Brain-([0-9.]+)-.*/\1/')
[ "$VER_V" = 1.0.32 ] || [ "$VER_V" = 1.0.33 ] || [ "$VER_V" = 1.0.34 ] || [ "$VER_V" = 1.0.35 ] || [ "$VER_V" = 1.0.36 ] || [ "$VER_V" = 1.0.37 ] || { male "la versione di partenza deve essere 1.0.32|1.0.33|1.0.34|1.0.35|1.0.36|1.0.37, trovata $VER_V"; exit 1; }
NOME_V="Memdoria"
[ "$VER_V" = 1.0.33 ] && NOME_V="Memdoria-AI-Brain"
{ [ "$VER_V" = 1.0.34 ] || [ "$VER_V" = 1.0.35 ] || [ "$VER_V" = 1.0.36 ] || [ "$VER_V" = 1.0.37 ]; } && NOME_V="Memdoria AI Brain"
APP_V="/Applications/$NOME_V.app"
DATI_V="$SUPPORTO/Memdoria-AI-Brain"
[ "$VER_V" = 1.0.32 ] && DATI_V="$SUPPORTO/Memdoria"
monta_e_copia "$VECCHIO" "$NOME_V.app"; controlla $? "$NOME_V.app (versione $VER_V) copiata"
licenza "$APP_V" "$DATI_V"
# La versione di prima guarda l'elenco delle versioni in questo file, firmato con la chiave di prova.
mkdir -p "$RUNNER_TEMP/feed"
cp "$NUOVO" "$RUNNER_TEMP/feed/"
VERSIONE_NUOVA=$(cat "$CODICE/VERSION")
python3 "$(dirname "$0")/feed.py" "$CODICE" "$CHIAVE" "$RUNNER_TEMP/feed/ultima-versione.json" "$VERSIONE_NUOVA" mac "$RUNNER_TEMP/feed/$(basename "$NUOVO")" "file://$RUNNER_TEMP/feed/$(basename "$NUOVO")"
export AI_BRAIN_UPDATES_URL="file://$RUNNER_TEMP/feed/ultima-versione.json"
seme_connessione "$DATI_V"
accendi "$APP_V/Contents/MacOS/Memdoria" vecchia
aspetta_lettura "$DATI_V"; richiedi $? "la versione $VER_V finisce la lettura"
api "$DATI_V" POST /admin/remember '{"text":"Il cliente Verdi Srl usa il gestionale Alfa dal 2024.","kind":"fact","source":"collaudo","source_ai":"collaudo","entities":[{"name":"Verdi Srl","type":"client"}]}' > /dev/null
api "$DATI_V" POST /admin/remember '{"text":"Il server di Verdi Srl e in Hetzner a Norimberga.","kind":"fact","source":"collaudo","source_ai":"collaudo","entities":[{"name":"Verdi Srl","type":"client"}]}' > /dev/null
PRIMA=$(conta "$DATI_V" memories); [ "${PRIMA:-0}" -ge 2 ]; controlla $? "memorie salvate prima dell'aggiornamento: ${PRIMA:-0}"
VOCE_V=ai-brain; [ "$VER_V" != 1.0.32 ] && VOCE_V=memdoria-ai-brain
if collega_ai "$DATI_V" "$VOCE_V"; then HA_VOCI=1; ok "la versione $VER_V ha collegato le AI"; else HA_VOCI=0; echo "  --   la versione $VER_V non ha collegato le AI da sola (probabile conferma a schermo): salto i controlli sulle voci dopo l'aggiornamento"; fi
sleep 10
DATI_N="$SUPPORTO/Memdoria-AI-Brain"
VERSIONE_NUOVA=$(cat "$CODICE/VERSION")
controlla_motore "$DATI_N" "$VERSIONE_NUOVA" "$DATI_V" > "$RUNNER_TEMP/motore-primo-$VER_V.log" 2>&1 & PID_MOTORE=$!
echo aggiorna > "$DATI_V/aggiorna.request"
# L'aggiornatore puo' sostituire il bundle sul posto: si osserva il percorso reale prima della prima riapertura.
APP_N=""
for i in $(seq 1 60); do
  sleep 10
  for candidata in "/Applications/Memdoria AI Brain.app" /Applications/Memdoria-AI-Brain.app /Applications/Memdoria.app; do
    [ -f "$candidata/Contents/Info.plist" ] && grep -q "<string>$VERSIONE_NUOVA</string>" "$candidata/Contents/Info.plist" && { APP_N="$candidata"; break; }
  done
  [ -n "$APP_N" ] && break
done
[ -n "$APP_N" ]; richiedi $? "l'app e' stata sostituita dalla $VERSIONE_NUOVA"
NUM_APPS=0
for candidata in "/Applications/Memdoria AI Brain.app" /Applications/Memdoria.app /Applications/Memdoria-AI-Brain.app; do [ -d "$candidata" ] && [ ! -L "$candidata" ] && NUM_APPS=$((NUM_APPS+1)); done
[ "$NUM_APPS" = 1 ]; controlla $? "un solo bundle reale in Applicazioni dopo l'aggiornamento: $APP_N"
controlla_nome_dock; richiedi $? "dopo l'aggiornamento la prima apertura automatica arriva all'istanza finale Memdoria AI Brain senza trattini"
controlla_primo_avvio "$DATI_N"
aspetta_lettura "$DATI_N"; richiedi $? "dopo l'aggiornamento la lettura finisce senza errori"
wait "$PID_MOTORE"; controlla $? "Engine senza stato Errore durante la prima riapertura dopo $VER_V"
if [ "$VER_V" = 1.0.34 ] || [ "$VER_V" = 1.0.35 ] || [ "$VER_V" = 1.0.36 ] || [ "$VER_V" = 1.0.37 ]; then
  [ -d "/Applications/Memdoria AI Brain.app" ] && [ ! -L "/Applications/Memdoria AI Brain.app" ]; controlla $? "dalla 1.0.34 conserva il nome senza trattini dopo l'aggiornamento"
else
  [ -d "/Applications/Memdoria AI Brain.app" ] && [ ! -L "/Applications/Memdoria AI Brain.app" ] && [ -L /Applications/Memdoria-AI-Brain.app ] && [ -L /Applications/Memdoria.app ]; controlla $? "nome senza trattini nel Dock, con collegamenti per le versioni precedenti"
fi
if [ "$VER_V" = 1.0.32 ]; then
  [ -L "$SUPPORTO/Memdoria" ]; controlla $? "trasloco fatto: Memdoria e' un collegamento verso Memdoria-AI-Brain"
fi
[ -L "$HOME/.config/ai-brain" ] && [ -f "$HOME/.config/memdoria-ai-brain/token" ]; controlla $? "la cartella tecnica e' stata spostata con un collegamento per la versione di prima"
DOPO=$(conta "$DATI_N" memories); [ "${DOPO:-0}" -ge "${PRIMA:-2}" ]; controlla $? "memorie intatte: prima ${PRIMA:-?}, dopo ${DOPO:-?}"
C=$(conta "$DATI_N" conversations); [ "${C:-0}" -ge 3 ]; controlla $? "conversazioni trovate dopo l'aggiornamento: ${C:-0}"
ICONE=$(pgrep -f 'runtime/app/tray\.py$' | wc -l | tr -d ' ')
[ "${ICONE:-0}" -le 1 ]; controlla $? "una sola icona accesa: ${ICONE:-0} (nessuna versione di prima rimasta)"
if [ "${ICONE:-0}" -gt 1 ]; then mkdir -p "$RUNNER_TEMP/riservato"; ps -axo pid,ppid,lstart,command | grep 'tray\.py' | grep -v grep >> "$RUNNER_TEMP/riservato/dettagli.log"; fi
if [ "$HA_VOCI" = 1 ]; then collega_ai "$DATI_N" memdoria-ai-brain && ! grep -q '"ai-brain"' "$HOME/.claude.json" && ! grep -q 'Application Support/Memdoria"' "$HOME/.claude.json"; controlla $? "le voci delle AI usano il nome nuovo e non puntano piu' alla cartella vecchia"; fi
if [ "$HA_VOCI" = 1 ] && [ -f "$HOME/.codex/config.toml" ]; then grep -q 'mcp_servers.memdoria-ai-brain' "$HOME/.codex/config.toml" && ! grep -q 'mcp_servers.ai-brain' "$HOME/.codex/config.toml"; controlla $? "anche Codex usa la voce nuova"; fi
lingua_si_cambia "$DATI_N"; controlla $? "dopo l'aggiornamento il cambio lingua funziona"
pagina_nel_browser "$DATI_N" "dopo l'aggiornamento"
spegni

fi

say "Esito"
if [ "$KO" -gt 0 ]; then echo "COLLAUDO FALLITO ($KO controlli)"; mkdir -p "$RUNNER_TEMP/riservato"; for l in "$RUNNER_TEMP"/app-*.log; do { echo "--- $l"; tail -80 "$l"; } >> "$RUNNER_TEMP/riservato/dettagli.log"; done; exit 1; fi
echo "COLLAUDO RIUSCITO"
