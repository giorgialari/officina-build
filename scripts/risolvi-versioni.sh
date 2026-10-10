#!/usr/bin/env bash
# Da un elenco di versioni (es. "1.0.25,1.0.28,1.0.30") trova il commit con cui sono uscite (il primo in cui VERSION e' diventato
# quel numero) e scrive per GitHub: la tabella da costruire (la nuova piu' tutte le vecchie) e l'elenco dei collaudi di aggiornamento.
#   risolvi-versioni.sh <cartella del codice (clone completo)> <riferimento nuovo> <elenco versioni separato da virgole>
set -eu
codice=$1; nuovo=$2; elenco=$3
python3 - "$codice" "$nuovo" "$elenco" <<'PY'
import json, os, subprocess, sys
codice, nuovo, elenco = sys.argv[1:4]
def git(*a):
    return subprocess.run(["git", "-C", codice, *a], capture_output=True, text=True).stdout.strip()
corrente = git("show", f"{nuovo}:VERSION").strip()
costruzioni = [{"nome": "nuovo", "riferimento": nuovo}]
collaudi = []
visti = set()
for v in [x.strip() for x in elenco.split(",") if x.strip()]:
    if v in visti or v == corrente:
        continue
    visti.add(v)
    commit = (git("log", "--format=%H", "-S" + v, "--", "VERSION").splitlines() or [""])[-1]  # il piu' vecchio: quello che l'ha introdotta
    if not commit or git("show", f"{commit}:VERSION").strip() != v:
        print(f"::warning::Non trovo il commit della versione {v}: la salto", file=sys.stderr)
        continue
    costruzioni.append({"nome": v, "riferimento": commit})
    collaudi.append({"vecchia": v, "pulita": not collaudi})  # l'installazione pulita si prova una volta sola
if not collaudi:
    print("Nessuna versione di prima da collaudare", file=sys.stderr)
out = os.environ.get("GITHUB_OUTPUT")
righe = {"matrice": json.dumps(costruzioni), "collaudi": json.dumps(collaudi), "corrente": corrente,
         "primo": costruzioni[1]["riferimento"] if len(costruzioni) > 1 else "", "primo_nome": costruzioni[1]["nome"] if len(costruzioni) > 1 else ""}
for k, v in righe.items():
    print(f"{k}={v}")
    if out:
        open(out, "a").write(f"{k}={v}\n")
PY
