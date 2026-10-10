#!/usr/bin/env bash
# Cifra i file di una cartella prima di caricarli come allegato (il repo e' pubblico, gli installer non ancora usciti non
# devono poter essere scaricati da chiunque). Ogni file diventa <nome>.enc (AES-256) e accanto c'e' chiave.cms: la chiave
# casuale di questa corsa, cifrata con registri.pem. Si apre solo con la chiave privata sul Mac del proprietario
# (scripts/scarica-e-pubblica.sh lo fa da solo).
#   proteggi.sh <cartella-con-i-file> <cartella-di-uscita> <modello dei file, es. '*.exe'>
set -eu
dentro=$1; fuori=$2; modello=$3
mkdir -p "$fuori"
chiave=$(mktemp)
openssl rand -hex 32 > "$chiave"
trovati=0
for f in "$dentro"/$modello; do
  [ -f "$f" ] || continue
  openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -salt -pass "file:$chiave" -in "$f" -out "$fuori/$(basename "$f").enc"
  trovati=$((trovati+1))
done
[ "$trovati" -gt 0 ] || { echo "Nessun file da proteggere in $dentro ($modello)"; exit 1; }
openssl cms -encrypt -aes256 -binary -in "$chiave" -out "$fuori/chiave.cms" -outform DER "${GITHUB_WORKSPACE:-.}/registri.pem"
rm -f "$chiave"
echo "protetti $trovati file"
