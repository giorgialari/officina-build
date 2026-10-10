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
# Ogni titolo di fase («▸ ...» o «> ...») si segna con l'ora: nel registro pubblico escono solo i nomi e i secondi delle fasi
# lunghe, per sapere dove va il tempo senza far uscire il resto.
tempi="$registro.tempi"; : > "$tempi"
( cd "$cartella" && "$@" ) 2>&1 | TEMPI_FASI="$tempi" perl -ne 'BEGIN { $| = 1 } print; if (/^\s*(?:\e\[[0-9;]*m)?(?:▸|>) ?(.*?)(?:\e\[[0-9;]*m)?\s*$/) { open(T, ">>", $ENV{TEMPI_FASI}) or next; print T time() . "\t$1\n"; close T }' > "$registro"
uscita=${PIPESTATUS[0]}
durata=$(( $(date +%s) - inizio ))
riepilogo=$(grep -aE "$filtro" "$registro" | tail -1 | tr -d '\r' | sed -E 's/\x1b\[[0-9;]*m//g' | cut -c1-120)
echo "[$etichetta] uscita $uscita in ${durata}s${riepilogo:+ - $riepilogo}"
fasi=$(awk -F'\t' -v fine="$(date +%s)" '{ t[NR]=$1; n[NR]=$2 } END { for (i=1;i<=NR;i++) { d=(i<NR?t[i+1]:fine)-t[i]; if (d>=20) printf "%s%s %ds", (s++?", ":""), substr(n[i],1,40), d } }' "$tempi" 2>/dev/null)
[ -n "$fasi" ] && echo "[$etichetta] fasi lunghe: $fasi"
rm -f "$tempi"
if [ "$uscita" -ne 0 ]; then
  openssl cms -encrypt -aes256 -binary -in "$registro" -out "$cartelle/$etichetta.cms" -outform DER \
    "${GITHUB_WORKSPACE:-.}/registri.pem" && echo "[$etichetta] dettaglio cifrato nell'allegato registri-cifrati"
fi
rm -f "$registro"
exit "$uscita"
