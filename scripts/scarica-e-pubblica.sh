#!/usr/bin/env bash
# Da lanciare SUL TUO MAC, a rilascio costruito: scarica gli allegati cifrati di una corsa di «Rilascio», li apre con la tua
# chiave privata e lancia lo script di pubblicazione di sempre. E' l'unico passo che tocca il sito, e lo fai tu.
#   scarica-e-pubblica.sh <numero della corsa> <cartella del codice di ai-brain>
set -eu
corsa=$1; codice=$2
chiave_privata="${REGISTRI_CHIAVE:-$HOME/.config/officina-build/registri.key}"
lavoro=$(mktemp -d "$HOME/rilascio-XXXXXX")
cd "$lavoro"
gh run download "$corsa" -R giorgialari/officina-build -p 'rilascio-*'
apri() {  # <cartella con i .enc e chiave.cms>
  local k; k=$(mktemp)
  # il job Windows scrive la chiave con fine riga \r\n: il \r va tolto, se no «bad decrypt»
  openssl cms -decrypt -inform DER -in "$1/chiave.cms" -inkey "$chiave_privata" | tr -d '\r' > "$k"
  for f in "$1"/*.enc; do openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -pass "file:$k" -in "$f" -out "${f%.enc}"; rm -f "$f"; done
  rm -f "$k" "$1/chiave.cms"
}
for d in rilascio-*; do apri "$d"; done
ls -l rilascio-*/
V=$(tr -d ' \n' < "$codice/VERSION")
echo "Pubblico la versione $V dal tuo Mac (come sempre)."
read -r -p "Continuo? [s/N] " r; [ "$r" = s ] || exit 0
NOTE=$(tr '\n' ' ' < "$codice/NOVITA.txt")
cd "$codice"
uv run --no-project --with cryptography python deploy/comune/pubblica.py --mac "$(ls "$lavoro"/rilascio-mac/*.dmg)" --windows "$(ls "$lavoro"/rilascio-windows/*.exe)" --note "$NOTE"
uv run --no-project --with cryptography python deploy/comune/pubblica_server.py --versione "$V" \
  --amd64 "$(ls "$lavoro"/rilascio-server-amd64/*.tar)" --arm64 "$(ls "$lavoro"/rilascio-server-arm64/*.tar)"
echo "Fatto. Cancella la cartella $lavoro quando vuoi."
