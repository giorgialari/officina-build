#!/usr/bin/env bash
# Prova il server acceso come farebbe una persona. Due fasi:
#   scrivi   : salva una memoria e la ritrova (server appena acceso)
#   verifica : dopo un riavvio o un aggiornamento la memoria c'e' ancora, se ne salva un'altra e si ritrovano entrambe
#   prova-server.sh <cartella con docker-compose.yml e .env> <fase>
set -u
cartella=$1; fase=$2
T=$(grep '^BRAIN_TOKEN=' "$cartella/.env" | cut -d= -f2)
H="Authorization: Bearer $T"; B=http://127.0.0.1:8765
mkdir -p "${RUNNER_TEMP:-/tmp}/riservato"; D="${RUNNER_TEMP:-/tmp}/riservato/risposte.log"
KO=0
controlla() { if [ "$1" = 0 ]; then echo "  OK   $2"; else echo "  MALE $2"; KO=$((KO+1)); fi; }
chiama() { curl -sS --max-time 60 -H "$H" "$@" 2>&1; }
salva() {
  chiama -X POST -H 'Content-Type: application/json' "$B/admin/remember" \
    -d "{\"text\":\"$1\",\"kind\":\"fact\",\"source\":\"collaudo\",\"source_ai\":\"collaudo\",\"entities\":[{\"name\":\"Verdi Srl\",\"type\":\"client\"}]}"
}
conta() { chiama "$B/admin/stats" | python3 -c "import json,sys;print(json.load(sys.stdin)['memories'])" 2>/dev/null; }
case "$fase" in
  scrivi)
    R=$(chiama "$B/health"); echo "health: $R" >> "$D"; [ -n "$R" ]; controlla $? "il server risponde"
    R=$(salva "Il cliente Verdi Srl usa il gestionale Alfa dal 2024."); echo "salva: $R" >> "$D"
    echo "$R" | grep -q '"status":"created"'; controlla $? "una memoria si salva"
    sleep 5
    R=$(chiama -X POST -H 'Content-Type: application/json' "$B/admin/search" -d '{"query":"gestionale Alfa","limit":5}'); echo "cerca: $R" >> "$D"
    echo "$R" | grep -q 'Alfa'; controlla $? "la memoria si ritrova con la ricerca"
    [ "$(conta)" = 1 ]; controlla $? "il conto delle memorie e' 1"
    ;;
  verifica)
    for i in $(seq 1 60); do curl -fsS "$B/health" > /dev/null 2>&1 && break; sleep 5; done
    curl -fsS "$B/health" > /dev/null 2>&1; controlla $? "il server risponde dopo il riavvio o l'aggiornamento"
    [ "$(conta)" = 1 ]; controlla $? "la memoria di prima c'e' ancora"
    R=$(chiama -X POST -H 'Content-Type: application/json' "$B/admin/search" -d '{"query":"gestionale Alfa","limit":5}'); echo "cerca dopo: $R" >> "$D"
    echo "$R" | grep -q 'Alfa'; controlla $? "la memoria di prima si ritrova con la ricerca"
    R=$(salva "Il server di Verdi Srl e in Hetzner a Norimberga."); echo "salva dopo: $R" >> "$D"
    echo "$R" | grep -q '"status":"created"'; controlla $? "dopo l'aggiornamento si salva una memoria nuova"
    [ "$(conta)" = 2 ]; controlla $? "il conto delle memorie e' 2"
    ;;
esac
[ "$KO" = 0 ]
