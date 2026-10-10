"""Quando la lettura delle conversazioni di Memdoria e' finita, guardando progress.json: la stessa regola per Mac (collaudo-mac.sh)
e, scritta uguale, per Windows (lettura.ps1). Uscita: 0 finita, 1 ancora in corso, 2 errore, 3 «Grafo»/«Pronto» visto ma non ancora
«Fatto» (le versioni vecchie non lo scrivono: il chiamante aspetta qualche giro e poi accetta)."""
import json
import sys


def esito(progresso: dict) -> int:
    eventi = [str(e.get("text", "")) for e in progresso.get("events") or []]
    if progresso.get("error"):
        return 2
    if progresso.get("done") or any(t.startswith("Fatto") for t in eventi):
        return 0
    return 3 if any(t.startswith(("Grafo", "Pronto")) for t in eventi) else 1


if __name__ == "__main__":
    sys.exit(esito(json.load(open(sys.argv[1], encoding="utf-8"))))
