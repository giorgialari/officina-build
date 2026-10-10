"""Attivazione con l'email, controllo periodico e liberazione del posto con il SERVIZIO VERO delle licenze, usando una licenza
di collaudo (la mail sta nel segreto LICENZA_COLLAUDO_EMAIL, mai nel registro). Gira col codice vero (chiave pubblica vera).
Uso: licenza-vera.py <cartella del codice>   (variabile EMAIL_COLLAUDO)
Stampa solo OK o MALE. Il posto si libera sempre, anche se qualcosa va storto."""
import os, sys, tempfile
from pathlib import Path

codice = Path(sys.argv[1])
sys.path[:0] = [str(codice / "backend" / "app"), str(codice)]
import licenza

email = os.environ["EMAIL_COLLAUDO"]
versione = (codice / "VERSION").read_text().strip()
dati = Path(tempfile.mkdtemp())
KO = 0
def controlla(ok, cosa):
    global KO
    print(("  OK   " if ok else "  MALE ") + cosa)
    KO += 0 if ok else 1

try:
    try:
        licenza.activate_email(dati, "collaudo-senza-licenza@example.invalid", versione)
        controlla(False, "un'email senza licenza viene rifiutata")
    except licenza.LicenseError:
        controlla(True, "un'email senza licenza viene rifiutata con la frase giusta")
    stato = licenza.activate_email(dati, email, versione)
    controlla(stato.get("state") == "ok", f"l'attivazione con l'email funziona (stato {stato.get('state')})")
    controlla(licenza.status(dati, kind="computer")["state"] == "ok", "la chiave arrivata vale su questo computer")
    controlla(licenza.read_check(dati) is not None, "con la chiave arriva il primo controllo firmato")
    (dati / licenza.CHECK_NAME).unlink(missing_ok=True)
    risposta = licenza.check_online(dati, versione)
    controlla(risposta.get("state") == "ok", f"il controllo periodico risponde «ok» ({risposta.get('state')})")
    controlla((dati / licenza.CHECK_NAME).exists(), "il controllo firmato viene salvato")
    controlla(licenza.status(dati, kind="computer")["state"] == "ok", "dopo il controllo la licenza vale ancora")

    # Il tempo senza rete, simulato: tolleranza di 3 giorni dall'ultimo controllo firmato. Ogni prova su una copia, perche'
    # la licenza si ricorda l'ultima ora vista e un salto in avanti falserebbe le prove dopo.
    import shutil, time
    ORA = 3600
    ultimo = licenza.read_check(dati)
    quando = licenza._parse_ts(str(ultimo.get("quando") or "")) or time.time()
    def a_distanza(ore, prove_dopo=None):
        copia = Path(tempfile.mkdtemp()) / "dati"
        shutil.copytree(dati, copia)
        return licenza.license_gate(copia, now_ts=quando + ore * ORA, kind="computer"), copia
    stato, _ = a_distanza(0.1)
    controlla(stato["state"] == "ok" and not stato.get("warning"), "subito dopo un controllo: vale, senza avviso")
    stato, _ = a_distanza(26)
    controlla(stato["state"] == "ok" and bool(stato.get("warning")), "dopo 26 ore senza controllo: vale, con l'avviso")
    stato, _ = a_distanza(71)
    controlla(stato["state"] == "ok", "dopo 71 ore senza controllo: vale ancora (tolleranza di 3 giorni)")
    stato, copia = a_distanza(73)
    controlla(stato["state"] == "disconnected", f"dopo 73 ore senza controllo: si ferma («{stato['state']}»)")
    controlla(bool(stato.get("message")), "e dice alla persona cosa fare")
    # Un controllo che torna a funzionare rimette tutto a posto (qui il servizio vero risponde ora).
    risposta = licenza.check_online(copia, versione)
    controlla(risposta.get("state") == "ok" and licenza.license_gate(copia, kind="computer")["state"] == "ok", "tornata la rete, il controllo rimette la licenza a posto")
    stato, _ = a_distanza(-50)
    controlla(stato["state"] == "disconnected", "orologio portato indietro: non allunga la licenza («disconnessa»)")
    stato, _ = a_distanza(24 * 40)
    controlla(stato["state"] != "ok", "orologio molto avanti: non vale")
finally:
    liberato = licenza.release_seat(dati, versione)
    controlla(liberato, "il posto di questo computer viene liberato")


# --- licenze decise dal registro: scaduta, bloccata, posto server ------------------------------------------------------------
def non_vale(email, cosa):
    """L'attivazione o il primo controllo devono dire di no: o con una frase (rifiuto) o con uno stato diverso da «ok»."""
    cartella = Path(tempfile.mkdtemp())
    try:
        stato = licenza.activate_email(cartella, email, versione)
        gate = licenza.license_gate(cartella, kind="computer")
        risposta = licenza.check_online(cartella, versione)
        ok = stato.get("state") != "ok" or gate.get("state") != "ok" or risposta.get("state") not in ("ok", "offline")
        controlla(ok, f"{cosa}: non vale (stato {stato.get('state')}, controllo {risposta.get('state')})")
        controlla(bool(stato.get("message") or gate.get("message")) or risposta.get("state") != "ok", f"{cosa}: la persona riceve la frase")
    except licenza.LicenseError as errore:
        controlla(True, f"{cosa}: rifiutata con la frase giusta")
        controlla(len(str(errore)) > 10, f"{cosa}: la frase non e' vuota")
    finally:
        licenza.release_seat(cartella, versione)

for variabile, cosa in (("EMAIL_SCADUTA", "licenza scaduta nel registro"), ("EMAIL_BLOCCATA", "licenza bloccata nel registro")):
    if os.environ.get(variabile):
        non_vale(os.environ[variabile], cosa)
    else:
        print(f"  --   {cosa}: segreto non impostato, salto")

if os.environ.get("EMAIL_SERVER"):
    email_s = os.environ["EMAIL_SERVER"]
    computer = Path(tempfile.mkdtemp())
    server = Path(tempfile.mkdtemp())
    macchina_server = "5E2A-0000-C011"
    try:
        licenza.activate_email(computer, email_s, versione)
        codice_download = licenza.download_code(computer, fresh=True)
        controlla(str(codice_download.get("codice", "")).startswith("asc_"), "il computer ottiene il codice per scaricare il server")
        stato = licenza.activate_email(server, email_s, versione, machine=macchina_server, kind="server", code=codice_download["codice"])
        controlla(stato.get("state") == "ok", f"il posto server si attiva con email e codice (stato {stato.get('state')})")
        controlla(licenza.status(server, machine=macchina_server, kind="server")["state"] == "ok", "la chiave del server vale sul server")
        controlla(licenza.status(server, machine=macchina_server, kind="computer")["state"] != "ok", "la stessa chiave non vale come licenza di un computer")
        risposta = licenza.check_online(server, versione, machine=macchina_server, kind="server")
        controlla(risposta.get("state") == "ok", f"il controllo periodico del server risponde ok ({risposta.get('state')})")
    except licenza.LicenseError as errore:
        controlla(False, f"flusso del posto server: {str(errore)[:120]}")
    finally:
        rilasciato = licenza.release_server_seat(server, versione, machine=macchina_server)
        controlla(rilasciato is not False, "il posto del server viene liberato")
        controlla(licenza.release_seat(computer, versione), "il posto del computer viene liberato")
else:
    print("  --   posto server: segreto non impostato, salto")
sys.exit(1 if KO else 0)
