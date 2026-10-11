#!/usr/bin/env bash
# Da un elenco di versioni trova il commit di rilascio ("Versione X.Y.Z"), dopo le correzioni fatte prima di uscire.
# Se manca quel segno, usa il primo commit che ha introdotto VERSION. Scrive la tabella e l'elenco dei collaudi.
#   risolvi-versioni.sh <cartella del codice (clone completo)> <riferimento nuovo> <elenco versioni separato da virgole>
set -eu
codice=$1; nuovo=$2; elenco=$3
python3 - "$codice" "$nuovo" "$elenco" <<'PY'
import json, os, subprocess, sys
codice, nuovo, elenco = sys.argv[1:4]
def git(*a):
    return subprocess.run(["git", "-C", codice, *a], capture_output=True, text=True).stdout.strip()
corrente = git("show", f"{nuovo}:VERSION").strip()
sha_nuovo = git("rev-parse", nuovo) or git("rev-parse", "origin/" + nuovo) or nuovo
costruzioni = [{"nome": "nuovo", "riferimento": sha_nuovo}]
collaudi = []
collaudi_win = []
visti = set()
for v in [x.strip() for x in elenco.split(",") if x.strip()]:
    if v in visti or v == corrente:
        continue
    visti.add(v)
    # La 1.0.32 ha avuto una correzione dell'installer dopo il primo cambio di VERSION: il pacchetto pubblicato
    # corrisponde al commit di rilascio, non al primo commit in cui e' apparso il numero.
    segnali = (line.split("\t", 1) for line in git("log", "--first-parent", "--format=%H%x09%s", nuovo).splitlines())
    commit = next((sha for sha, titolo in segnali if titolo == f"Versione {v}" and git("show", f"{sha}:VERSION").strip() == v), "")
    if not commit:
        commit = (git("log", "--format=%H", "-S" + v, "--", "VERSION").splitlines() or [""])[-1]
    if not commit or git("show", f"{commit}:VERSION").strip() != v:
        print(f"::warning::Non trovo il commit della versione {v}: la salto", file=sys.stderr)
        continue
    costruzioni.append({"nome": v, "riferimento": commit})
    collaudi.append({"vecchia": v, "pulita": False, "solo_pulita": False})
    collaudi_win += [{"vecchia": v, "pulita": False, "modo": "installer"}, {"vecchia": v, "pulita": False, "modo": "app"}]  # i due modi in parallelo
if not collaudi:
    print("Nessuna versione di prima da collaudare", file=sys.stderr)
# L'installazione pulita della versione nuova e' un collaudo a parte (in parallelo, senza aggiornamenti dentro).
collaudi.insert(0, {"vecchia": "nessuna", "pulita": True, "solo_pulita": True})
collaudi_win.insert(0, {"vecchia": "nessuna", "pulita": True, "modo": "nessuno"})
out = os.environ.get("GITHUB_OUTPUT")
righe = {"matrice": json.dumps(costruzioni), "collaudi": json.dumps(collaudi), "collaudi_win": json.dumps(collaudi_win), "corrente": corrente,
         "primo": costruzioni[1]["riferimento"] if len(costruzioni) > 1 else "", "primo_nome": costruzioni[1]["nome"] if len(costruzioni) > 1 else ""}
for k, v in righe.items():
    print(f"{k}={v}")
    if out:
        open(out, "a").write(f"{k}={v}\n")
PY
