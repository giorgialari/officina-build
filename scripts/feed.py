"""Elenco delle versioni firmato con la chiave di PROVA (mai quella vera), per provare l'aggiornamento dall'app.
Uso: feed.py <codice> <chiave.pem> <uscita.json> <versione> <mac|windows> <file> <indirizzo del file>"""
import hashlib, json, sys
from pathlib import Path

codice, chiave, uscita, versione, sistema, file, indirizzo = sys.argv[1:8]
sys.path[:0] = [f"{codice}/backend/app", codice]
import aggiornamenti
from cryptography.hazmat.primitives import serialization

percorso = Path(file)
h = hashlib.sha256()
with percorso.open("rb") as f:
    while pezzo := f.read(1 << 20):
        h.update(pezzo)
privata = serialization.load_pem_private_key(Path(chiave).read_bytes(), password=None)
elenco = {"version": versione, "date": "2026-10-10", "mandatory": False, "notes": "collaudo",
          "files": {sistema: {"name": percorso.name, "url": indirizzo, "sha256": h.hexdigest(), "size": percorso.stat().st_size}}}
Path(uscita).write_text(json.dumps(aggiornamenti.sign_manifest(elenco, privata)))
print("elenco firmato")
