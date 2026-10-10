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
  for d in "$HOME/Library/Application Support/AI Brain" "$HOME/Library/Application Support/Memdoria"; do
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
  mkdir -p "$HOME/.gemini/antigravity/brain/8bd7e99a/.system_generated/logs" "$HOME/.gemini/tmp/h1/chats" "$HOME/.claude/projects/-lavoro-sito"
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
  local dati=$1 i
  for i in $(seq 1 90); do
    sleep 10; rm -rf "$dati/lingua-da-scegliere"
    if [ -f "$dati/progress.json" ]; then
      python3 -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d.get('done') and not d.get('error') else (2 if d.get('error') else 1))" "$dati/progress.json"
      case $? in 0) return 0;; 2) return 2;; esac
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
collega_ai() {  # <dati> -> 0 se la voce di Memdoria compare nei file di Claude Code
  echo connetti > "$1/connetti.request"
  local i
  for i in $(seq 1 18); do sleep 5; grep -q 'ai-brain' "$HOME/.claude.json" 2>/dev/null && return 0; done
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
  local uscita; uscita=$(node "$(dirname "$0")/pagina.mjs" "http://127.0.0.1:$porta/app/" "$RUNNER_TEMP/pagina-mac-${2// /-}" 2>&1 | tail -1); local r=$?
  controlla $r "la pagina si apre nel browser e disegna il grafo ($2): $uscita"
}
spegni() { pkill -f "Contents/Resources/runtime" 2>/dev/null; sleep 5; pkill -9 -f "Contents/Resources/runtime" 2>/dev/null; sleep 2; }

chat_finte

if [ "${CON_PULITA:-true}" = true ]; then
say "A. Installazione pulita della versione nuova"
monta_e_copia "$NUOVO" "Memdoria.app"; controlla $? "Memdoria.app copiata in Applicazioni"
DATI="$SUPPORTO/Memdoria"
licenza /Applications/Memdoria.app "$DATI"
accendi /Applications/Memdoria.app/Contents/MacOS/Memdoria nuova
aspetta_lettura "$DATI"; richiedi $? "la prima lettura finisce senza errori"
C=$(conta "$DATI" conversations); [ "${C:-0}" -ge 3 ]; controlla $? "conversazioni trovate: ${C:-0} (attese almeno 3)"
E=$(conta "$DATI" active_entities); [ "${E:-0}" -ge 1 ]; controlla $? "il grafo si riempie: ${E:-0} entita"
[ ! -e "$SUPPORTO/AI Brain" ]; controlla $? "nessuna cartella AI Brain in un'installazione nuova"
"/Applications/Memdoria.app/Contents/Resources/runtime/python/bin/python3.12" -E -s "$(dirname "$0")/licenze-offline.py" "/Applications/Memdoria.app/Contents/Resources/runtime/app" "$CHIAVE"; controlla $? "gli stati della licenza (manca, giusta, scaduta, altro computer, firma rovinata) sull'app installata"
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
# Disinstallazione (come «Disinstalla Memdoria» nella pagina): programmi spenti, dati tolti, voci delle AI tolte
echo '{"dati": true, "backup": false}' > "$DATI/disinstalla.request"
for i in $(seq 1 60); do sleep 5; pgrep -f "Contents/Resources/runtime" > /dev/null || break; done
! pgrep -f "Contents/Resources/runtime" > /dev/null; controlla $? "dopo la disinstallazione nessun programma e' acceso"
[ ! -d "$DATI" ]; controlla $? "dopo la disinstallazione i dati sono stati tolti"
! grep -q 'ai-brain' "$HOME/.claude.json" 2>/dev/null; controlla $? "dopo la disinstallazione le voci delle AI sono state tolte"
spegni
rm -rf /Applications/Memdoria.app "$DATI"

fi

say "B. Aggiornamento dall'app dalla versione di prima"
# Fino alla 1.0.30 l'app si chiama «AI Brain» e i dati stanno in «AI Brain» (al primo avvio nuovo si traslocano in «Memdoria»);
# dalla 1.0.31 sono gia' «Memdoria»: non c'e' trasloco da controllare.
VER_V=$(basename "$VECCHIO" | sed -E 's/^AI-Brain-([0-9.]+)-.*/\1/')
if [ "$VER_V" != "1.0.31" ] && [ "$(printf '%s\n%s\n' "$VER_V" 1.0.31 | sort -V | head -1)" = "$VER_V" ]; then SEPARATA=1; NOME_V="AI Brain"; else SEPARATA=0; NOME_V="Memdoria"; fi
APP_V="/Applications/$NOME_V.app"
DATI_V="$SUPPORTO/$NOME_V"
monta_e_copia "$VECCHIO" "$NOME_V.app"; controlla $? "$NOME_V.app (versione $VER_V) copiata"
licenza "$APP_V" "$DATI_V"
# La versione di prima guarda l'elenco delle versioni in questo file, firmato con la chiave di prova.
mkdir -p "$RUNNER_TEMP/feed"
cp "$NUOVO" "$RUNNER_TEMP/feed/"
VERSIONE_NUOVA=$(cat "$CODICE/VERSION")
python3 "$(dirname "$0")/feed.py" "$CODICE" "$CHIAVE" "$RUNNER_TEMP/feed/ultima-versione.json" "$VERSIONE_NUOVA" mac "$RUNNER_TEMP/feed/$(basename "$NUOVO")" "file://$RUNNER_TEMP/feed/$(basename "$NUOVO")"
export AI_BRAIN_UPDATES_URL="file://$RUNNER_TEMP/feed/ultima-versione.json"
accendi "$APP_V/Contents/MacOS/$NOME_V" vecchia
aspetta_lettura "$DATI_V"; richiedi $? "la versione $VER_V finisce la lettura"
api "$DATI_V" POST /admin/remember '{"text":"Il cliente Verdi Srl usa il gestionale Alfa dal 2024.","kind":"fact","source":"collaudo","source_ai":"collaudo","entities":[{"name":"Verdi Srl","type":"client"}]}' > /dev/null
api "$DATI_V" POST /admin/remember '{"text":"Il server di Verdi Srl e in Hetzner a Norimberga.","kind":"fact","source":"collaudo","source_ai":"collaudo","entities":[{"name":"Verdi Srl","type":"client"}]}' > /dev/null
PRIMA=$(conta "$DATI_V" memories); [ "${PRIMA:-0}" -ge 2 ]; controlla $? "memorie salvate prima dell'aggiornamento: ${PRIMA:-0}"
if collega_ai "$DATI_V"; then HA_VOCI=1; ok "la versione $VER_V ha collegato le AI"; else HA_VOCI=0; echo "  --   la versione $VER_V non ha collegato le AI da sola (probabile conferma a schermo): salto i controlli sulle voci dopo l'aggiornamento"; fi
sleep 10
echo aggiorna > "$DATI_V/aggiorna.request"
# l'app scarica, installa, si spegne e si riapre da sola: si aspetta la versione nuova
plist="$APP_V/Contents/Info.plist"
for i in $(seq 1 60); do
  sleep 10
  [ -f "$plist" ] && grep -q "<string>$VERSIONE_NUOVA</string>" "$plist" && break
done
grep -q "<string>$VERSIONE_NUOVA</string>" "$plist"; controlla $? "l'app e' stata sostituita dalla $VERSIONE_NUOVA"
DATI_N="$SUPPORTO/Memdoria"
for i in $(seq 1 30); do pgrep -f "$NOME_V.app/Contents/Resources/runtime/python.*tray.py" > /dev/null && break; sleep 10; done
pgrep -f "tray.py" > /dev/null || { echo "  (l'app non si e' riaperta da sola: la accendo come farebbe la persona)"; accendi "$APP_V/Contents/MacOS/Memdoria" nuova-dopo; }
aspetta_lettura "$DATI_N"; richiedi $? "dopo l'aggiornamento la lettura finisce senza errori"
if [ "$SEPARATA" = 1 ]; then
  [ -L "$SUPPORTO/AI Brain" ]; controlla $? "trasloco fatto: AI Brain e' un collegamento verso Memdoria"
else
  echo "  --   la $VER_V ha gia' i dati in Memdoria: niente trasloco da controllare"
fi
DOPO=$(conta "$DATI_N" memories); [ "${DOPO:-0}" -ge "${PRIMA:-2}" ]; controlla $? "memorie intatte: prima ${PRIMA:-?}, dopo ${DOPO:-?}"
C=$(conta "$DATI_N" conversations); [ "${C:-0}" -ge 3 ]; controlla $? "conversazioni trovate dopo l'aggiornamento: ${C:-0}"
[ "$(pgrep -fc 'tray.py')" -le 1 ]; controlla $? "una sola icona accesa (nessuna versione di prima rimasta)"
if [ "$HA_VOCI" = 1 ]; then grep -q 'ai-brain' "$HOME/.claude.json" && ! grep -q 'Application Support/AI Brain' "$HOME/.claude.json"; controlla $? "le voci delle AI sono rimaste e non puntano piu' alla cartella vecchia"; fi
lingua_si_cambia "$DATI_N"; controlla $? "dopo l'aggiornamento il cambio lingua funziona"
pagina_nel_browser "$DATI_N" "dopo l'aggiornamento"
spegni

say "Esito"
if [ "$KO" -gt 0 ]; then echo "COLLAUDO FALLITO ($KO controlli)"; mkdir -p "$RUNNER_TEMP/riservato"; for l in "$RUNNER_TEMP"/app-*.log; do { echo "--- $l"; tail -80 "$l"; } >> "$RUNNER_TEMP/riservato/dettagli.log"; done; exit 1; fi
echo "COLLAUDO RIUSCITO"
