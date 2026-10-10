#!/usr/bin/env bash
# Esegue un comando senza far uscire nel registro pubblico quello che stampa.
#   riservato.sh <etichetta> <cartella> <filtro del riepilogo> -- comando ...
# Nel registro escono solo: etichetta, esito, durata e UNA riga di riepilogo (numeri di prove). Il resto va in un file; se il
# comando fallisce, quel file si cifra con la chiave pubblica di registri.pem e finisce in un allegato che apre solo chi ha
# la chiave privata:  openssl cms -decrypt -inform DER -in <file>.cms -inkey ~/.config/officina-build/registri.key
set -u
etichetta=$1; cartella=$2; filtro=$3; shift 3
[ "${1:-}" = "--" ] && shift
cartelle="${RUNNER_TEMP:-/tmp}/riservato"
mkdir -p "$cartelle"
registro="$cartelle/$etichetta.log"
inizio=$(date +%s)
( cd "$cartella" && "$@" ) > "$registro" 2>&1
uscita=$?
durata=$(( $(date +%s) - inizio ))
riepilogo=$(grep -aE "$filtro" "$registro" | tail -1 | tr -d '\r' | sed -E 's/\x1b\[[0-9;]*m//g' | cut -c1-120)
echo "[$etichetta] uscita $uscita in ${durata}s${riepilogo:+ - $riepilogo}"
if [ "$uscita" -ne 0 ]; then
  openssl cms -encrypt -aes256 -binary -in "$registro" -out "$cartelle/$etichetta.cms" -outform DER \
    "${GITHUB_WORKSPACE:-.}/registri.pem" && echo "[$etichetta] dettaglio cifrato nell'allegato registri-cifrati"
fi
rm -f "$registro"
exit "$uscita"
