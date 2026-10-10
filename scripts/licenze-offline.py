"""Gli stati della licenza provati sull'app INSTALLATA (il suo Python e il suo codice compilato), senza rete.
Uso (con il Python dell'app): python -E -s licenze-offline.py <cartella runtime/app dell'app> <chiave privata di prova>
Stampa una riga per prova (OK o MALE) e esce con 1 se una e' sbagliata. Non stampa mai una chiave."""
import sys, tempfile
from pathlib import Path

app, chiave = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(app))
import licenza

KO = 0
def controlla(ok, cosa):
    global KO
    print(("  OK   " if ok else "  MALE ") + cosa)
    KO += 0 if ok else 1

def stato_di(contenuto):
    cartella = Path(tempfile.mkdtemp())
    if contenuto is not None:
        (cartella / licenza.FILE_NAME).write_text(contenuto, encoding="utf-8")
    return licenza.status(cartella)

mio = licenza.machine_code()
valida = licenza.issue("Collaudo", "collaudo@example.invalid", "2099-12-31", mio, chiave)
scaduta = licenza.issue("Collaudo", "collaudo@example.invalid", "2020-01-01", mio, chiave)
altro = licenza.issue("Collaudo", "collaudo@example.invalid", "2099-12-31", "AAAA-BBBB-CCCC", chiave)
rovinata = valida[:-6] + ("AAAAAA" if not valida.endswith("AAAAAA") else "BBBBBB")
del_server = licenza.issue("Collaudo", "", "2099-12-31", "", chiave, tipo="server")

controlla(stato_di(None)["state"] == "missing", "senza licenza: lo stato e' «manca» (la schermata chiede l'email)")
controlla(stato_di(valida)["state"] == "ok", "licenza giusta per questo computer: vale")
controlla(stato_di(scaduta)["state"] == "expired", "licenza scaduta: lo stato e' «scaduta»")
controlla(stato_di(altro)["state"] == "invalid", "licenza di un altro computer: rifiutata")
controlla(stato_di(rovinata)["state"] == "invalid", "licenza con la firma rovinata: rifiutata")
controlla(stato_di(del_server)["state"] == "invalid", "la chiave del posto server non vale su un computer")
controlla(bool(licenza.status(Path(tempfile.mkdtemp()))["message"]), "ogni stato porta la frase per la persona")
sys.exit(1 if KO else 0)
