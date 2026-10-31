#!/usr/bin/env bash
# Il modello di Memdoria AI per il collaudo con l'installazione pulita, preso dal sito vero come lo prende un cliente:
# dal 30/10/2026 /modelli/ si apre solo con il codice di 24 ore di una licenza valida. Il collaudo ha la sua licenza
# («Collaudo officina», solo per questo, la si blocca dal gestionale), nel segreto COLLAUDO_SCARICAMENTO: {"id", "computer"}.
# Con quella chiede il codice al servizio delle licenze, scarica il file e ne controlla l'impronta del registro.
#   modello-collaudo.sh <cartella del codice di ai-brain> <cartella dove metterlo>
# Senza il segreto non fa niente: il collaudo controlla allora che il sito neghi il modello alla licenza di prova.
set -euo pipefail
codice=$1; dove=$2
if [ -z "${PERMESSO:-}" ]; then echo "Nessun permesso di scaricamento: il modello non si scarica."; exit 0; fi
PY=$(command -v python3 || command -v python)  # su Windows (Git Bash) c'è solo «python»
# (tr: su Windows Python chiude le righe con \r\n, e il \r finiva nell'impronta)
read -r url file dimensione sha < <("$PY" - "$codice/backend/brain/modello_locale/registro.json" <<'PY' | tr -d '\r'
import json, sys
voce = json.load(open(sys.argv[1], encoding="utf-8"))["modelli"]["principale"]
print(voce["url"], voce["file"], voce["dimensione"], voce["sha256"])
PY
)
case "$url" in http*) ;; *) url="https://memdoria.com/$url" ;; esac
risposta=$(printf '%s' "$PERMESSO" | curl -fsS --max-time 30 -X POST https://licenze.memdoria.com/scaricamento \
  -H 'Content-Type: application/json' --data-binary @-)
chiave=$(printf '%s' "$risposta" | "$PY" -c 'import json, sys; print(json.load(sys.stdin)["codice"])' | tr -d '\r')
echo "::add-mask::$chiave"
mkdir -p "$dove"
curl -fL --retry 3 --max-time 3600 -H "X-AI-Brain-Codice: $chiave" -o "$dove/$file.parziale" "$url"
[ "$(wc -c < "$dove/$file.parziale" | tr -d ' ')" = "$dimensione" ] || { echo "Il modello scaricato non ha la dimensione del registro." >&2; exit 1; }
trovata=$(sha256sum "$dove/$file.parziale" | cut -d' ' -f1)
[ "$trovata" = "$sha" ] || { echo "Il modello scaricato non ha l'impronta del registro (${trovata:0:12}… invece di ${sha:0:12}…)." >&2; exit 1; }
mv "$dove/$file.parziale" "$dove/$file"
echo "Modello $file preso dal sito con il permesso del collaudo ($dimensione byte, impronta giusta)."
