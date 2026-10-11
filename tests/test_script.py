"""Prove degli script di collaudo e di rilascio (nessuna rete, nessun codice di Memdoria: tutto su cartelle finte)."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

RADICE = Path(__file__).resolve().parents[1]
SCRIPT = RADICE / "scripts"
sys.path.insert(0, str(SCRIPT))
import lettura_finita  # noqa: E402


# --- lettura_finita: quando la lettura delle conversazioni e' finita --------------------------------------------------------
@pytest.mark.parametrize("progresso,atteso", [
    ({"done": False, "events": []}, 1),
    ({"events": [{"text": "Cerco le conversazioni"}]}, 1),
    ({"events": [{"text": "Grafo pronto: persone"}]}, 3),                 # versioni vecchie: ci si ferma qui
    ({"events": [{"text": "Pronto: 1 conversazioni"}]}, 3),
    ({"events": [{"text": "Grafo: 8 entita"}, {"text": "Fatto: 9 conversazioni"}]}, 0),
    ({"done": True, "events": []}, 0),
    ({"error": "si e' rotto", "events": [{"text": "Fatto: 1"}]}, 2),       # l'errore vince su «Fatto»
    ({"error": None, "events": []}, 1),
    ({}, 1),
])
def test_lettura_finita(progresso, atteso):
    assert lettura_finita.esito(progresso) == atteso


def test_lettura_finita_da_riga_di_comando(tmp_path):
    file = tmp_path / "progress.json"
    file.write_text(json.dumps({"events": [{"text": "Fatto: 3 conversazioni"}]}), encoding="utf-8")
    assert subprocess.run([sys.executable, str(SCRIPT / "lettura_finita.py"), str(file)]).returncode == 0
    file.write_text(json.dumps({"error": "x"}), encoding="utf-8")
    assert subprocess.run([sys.executable, str(SCRIPT / "lettura_finita.py"), str(file)]).returncode == 2


def test_mac_e_windows_usano_la_stessa_regola():
    """Il Mac chiama il file Python provato qui sopra; Windows la copia scritta in lettura.ps1 (provata da lettura.tests.ps1):
    le due devono nominare le stesse parole chiave."""
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    assert "lettura_finita.py" in mac
    ps = (SCRIPT / "lettura.ps1").read_text(encoding="utf-8")
    py = (SCRIPT / "lettura_finita.py").read_text(encoding="utf-8")
    for parola in ("Fatto", "Grafo", "Pronto"):
        assert parola in ps and parola in py
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "Esito-Lettura" in win


# --- risolvi-versioni: da un numero di versione al commit con cui e' uscita --------------------------------------------------
def git(cartella, *argomenti):
    return subprocess.run(["git", "-C", str(cartella), *argomenti], check=True, capture_output=True, text=True,
                          env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                               "GIT_COMMITTER_EMAIL": "t@t"}).stdout.strip()


@pytest.fixture
def repo(tmp_path):
    cartella = tmp_path / "codice"
    cartella.mkdir()
    git(cartella, "init", "-q", "-b", "main")
    sha = {}
    for versione in ("1.0.25", "1.0.26", "1.0.30", "1.0.32"):
        (cartella / "VERSION").write_text(versione + "\n")
        (cartella / f"f-{versione}.txt").write_text(versione)
        git(cartella, "add", "-A")
        git(cartella, "commit", "-qm", f"Versione {versione}")
        sha[versione] = git(cartella, "rev-parse", "HEAD")
        # un commit di lavoro dopo l'uscita: la versione e' quello in cui VERSION e' cambiata, non l'ultimo
        (cartella / "lavoro.txt").write_text(versione)
        git(cartella, "add", "-A")
        git(cartella, "commit", "-qm", f"lavoro dopo {versione}")
    return cartella, sha


def risolvi(cartella, nuovo, elenco):
    fatto = subprocess.run(["bash", str(SCRIPT / "risolvi-versioni.sh"), str(cartella), nuovo, elenco], capture_output=True, text=True)
    assert fatto.returncode == 0, fatto.stderr
    return {riga.split("=", 1)[0]: json.loads(riga.split("=", 1)[1]) if riga.split("=", 1)[1][:1] in "[{" else riga.split("=", 1)[1]
            for riga in fatto.stdout.splitlines() if "=" in riga}


def test_trova_il_commit_con_cui_e_uscita_ogni_versione(repo):
    cartella, sha = repo
    uscita = risolvi(cartella, "main", "1.0.25,1.0.30")
    matrice = {voce["nome"]: voce["riferimento"] for voce in uscita["matrice"]}
    assert matrice["1.0.25"] == sha["1.0.25"] and matrice["1.0.30"] == sha["1.0.30"]
    assert matrice["nuovo"] == git(cartella, "rev-parse", "main")  # il nuovo e' risolto in un commit preciso
    assert uscita["corrente"] == "1.0.32"


def test_una_versione_con_correzioni_prima_del_rilascio_usa_il_segnaposto_finale(repo):
    cartella, _ = repo
    (cartella / "correzione-installer.txt").write_text("installer compilabile")
    git(cartella, "add", "-A")
    git(cartella, "commit", "-qm", "Correzione installer prima del rilascio")
    git(cartella, "commit", "--allow-empty", "-qm", "Versione 1.0.32")
    rilascio = git(cartella, "rev-parse", "HEAD")
    (cartella / "VERSION").write_text("1.0.33\n")
    (cartella / "nuovo.txt").write_text("lavoro successivo")
    git(cartella, "add", "-A")
    git(cartella, "commit", "-qm", "lavoro dopo il rilascio")
    uscita = risolvi(cartella, "main", "1.0.32")
    assert uscita["matrice"][1] == {"nome": "1.0.32", "riferimento": rilascio}


def test_versione_senza_segnaposto_usa_ultimo_commit_prima_della_successiva(repo):
    cartella, _ = repo
    (cartella / "VERSION").write_text("1.0.33\n")
    git(cartella, "add", "VERSION")
    git(cartella, "commit", "-qm", "Inizio lavoro 1.0.33")
    (cartella / "correzione.txt").write_text("la versione effettivamente distribuita")
    git(cartella, "add", "-A")
    git(cartella, "commit", "-qm", "Correzione finale 1.0.33")
    rilascio = git(cartella, "rev-parse", "HEAD")
    (cartella / "VERSION").write_text("1.0.34\n")
    git(cartella, "add", "VERSION")
    git(cartella, "commit", "-qm", "Inizio lavoro 1.0.34")
    uscita = risolvi(cartella, "main", "1.0.33")
    assert uscita["matrice"][1] == {"nome": "1.0.33", "riferimento": rilascio}


def test_il_collaudo_ha_installazione_pulita_a_parte_e_i_due_modi_di_windows(repo):
    cartella, _ = repo
    uscita = risolvi(cartella, "main", "1.0.25,1.0.30")
    assert uscita["collaudi"][0] == {"vecchia": "nessuna", "pulita": True, "solo_pulita": True}
    assert [(c["vecchia"], c["pulita"]) for c in uscita["collaudi"][1:]] == [("1.0.25", False), ("1.0.30", False)]
    win = uscita["collaudi_win"]
    assert win[0] == {"vecchia": "nessuna", "pulita": True, "modo": "nessuno"}
    assert [(c["vecchia"], c["modo"]) for c in win[1:]] == [("1.0.25", "installer"), ("1.0.25", "app"), ("1.0.30", "installer"), ("1.0.30", "app")]
    assert all(c["pulita"] is False for c in win[1:])        # l'installazione pulita si fa una volta sola


def test_la_versione_corrente_e_i_doppioni_non_si_collaudano_contro_se_stessi(repo):
    cartella, _ = repo
    uscita = risolvi(cartella, "main", "1.0.32,1.0.25,1.0.25")
    assert [c["vecchia"] for c in uscita["collaudi"][1:]] == ["1.0.25"]


def test_una_versione_che_non_esiste_si_salta_senza_rompere(repo):
    cartella, _ = repo
    fatto = subprocess.run(["bash", str(SCRIPT / "risolvi-versioni.sh"), str(cartella), "main", "9.9.9,1.0.25"], capture_output=True, text=True)
    assert fatto.returncode == 0 and "9.9.9" in fatto.stderr
    assert "1.0.25" in fatto.stdout


def test_primo_e_primo_nome_per_il_collaudo_del_server(repo):
    cartella, sha = repo
    uscita = risolvi(cartella, "main", "1.0.30,1.0.25")
    assert uscita["primo"] == sha["1.0.30"] and uscita["primo_nome"] == "1.0.30"


# --- proteggi.sh / cifra.sh: gli allegati si aprono solo con la chiave privata -------------------------------------------------
def test_proteggi_cifra_e_si_riapre_con_la_chiave_privata(tmp_path):
    chiave, certificato = tmp_path / "k.key", tmp_path / "registri.pem"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(chiave), "-out", str(certificato),
                    "-days", "1", "-subj", "/CN=prova"], check=True, capture_output=True)
    dentro = tmp_path / "dentro"
    dentro.mkdir()
    (dentro / "installer.exe").write_bytes(b"contenuto segreto " * 1000)
    fuori = tmp_path / "fuori"
    ambiente = {**os.environ, "GITHUB_WORKSPACE": str(tmp_path)}
    subprocess.run(["bash", str(SCRIPT / "proteggi.sh"), str(dentro), str(fuori), "*.exe"], check=True, capture_output=True, env=ambiente)
    assert sorted(p.name for p in fuori.iterdir()) == ["chiave.cms", "installer.exe.enc"]
    assert b"contenuto segreto" not in (fuori / "installer.exe.enc").read_bytes()
    segreto = subprocess.run(["openssl", "cms", "-decrypt", "-inform", "DER", "-in", str(fuori / "chiave.cms"), "-inkey", str(chiave)],
                             check=True, capture_output=True).stdout
    aperto = subprocess.run(["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "10000", "-pass", "stdin",
                             "-in", str(fuori / "installer.exe.enc")], input=segreto, check=True, capture_output=True).stdout
    assert aperto == b"contenuto segreto " * 1000


def test_proteggi_senza_file_si_ferma(tmp_path):
    (tmp_path / "registri.pem").write_text("x")
    fatto = subprocess.run(["bash", str(SCRIPT / "proteggi.sh"), str(tmp_path / "vuota"), str(tmp_path / "out"), "*.exe"],
                           capture_output=True, text=True, env={**os.environ, "GITHUB_WORKSPACE": str(tmp_path)})
    assert fatto.returncode != 0


# --- riservato.sh: nel registro pubblico escono solo esito e numeri ----------------------------------------------------------
def test_riservato_non_stampa_l_output_del_comando(tmp_path):
    (tmp_path / "registri.pem").write_text("x")
    ambiente = {**os.environ, "RUNNER_TEMP": str(tmp_path), "GITHUB_WORKSPACE": str(tmp_path)}
    fatto = subprocess.run(["bash", str(SCRIPT / "riservato.sh"), "prova", str(tmp_path), "[0-9]+ passed", "--", "bash", "-c",
                            "echo 'codice segreto: def funzione_privata(): pass'; echo '12 passed in 3s'"],
                           capture_output=True, text=True, env=ambiente)
    assert fatto.returncode == 0
    assert "12 passed" in fatto.stdout and "funzione_privata" not in fatto.stdout + fatto.stderr


def test_riservato_se_fallisce_lascia_il_dettaglio_cifrato_e_non_in_chiaro(tmp_path):
    chiave, certificato = tmp_path / "k.key", tmp_path / "registri.pem"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(chiave), "-out", str(certificato),
                    "-days", "1", "-subj", "/CN=prova"], check=True, capture_output=True)
    ambiente = {**os.environ, "RUNNER_TEMP": str(tmp_path), "GITHUB_WORKSPACE": str(tmp_path)}
    fatto = subprocess.run(["bash", str(SCRIPT / "riservato.sh"), "rosso", str(tmp_path), "[0-9]+ failed", "--", "bash", "-c",
                            "echo 'Traceback: file privato.py riga 12'; echo '1 failed'; exit 1"],
                           capture_output=True, text=True, env=ambiente)
    assert fatto.returncode == 1
    assert "privato.py" not in fatto.stdout + fatto.stderr
    cifrato = tmp_path / "riservato" / "rosso.cms"
    assert cifrato.is_file() and not (tmp_path / "riservato" / "rosso.log").exists()
    chiaro = subprocess.run(["openssl", "cms", "-decrypt", "-inform", "DER", "-in", str(cifrato), "-inkey", str(chiave)],
                            check=True, capture_output=True, text=True).stdout
    assert "privato.py riga 12" in chiaro


# --- i file che il collaudo copia o legge devono esistere e avere la sintassi giusta ----------------------------------------
def test_la_chiave_di_prova_e_la_sua_pubblica_vanno_insieme():
    from cryptography.hazmat.primitives import serialization
    import base64

    privata = serialization.load_pem_private_key((RADICE / "chiave-prova" / "chiave-privata.pem").read_bytes(), password=None)
    pubblica = base64.urlsafe_b64encode(privata.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode().rstrip("=")
    assert pubblica == (RADICE / "chiave-prova" / "pubblica.txt").read_text().strip()


def test_la_chiave_di_prova_non_e_quella_vera():
    assert (RADICE / "chiave-prova" / "pubblica.txt").read_text().strip() != "m_QL-tOfVLrSvzxol1xv06rGbLooUUh5YLFlwyOxHxw"


def test_gli_script_bash_hanno_sintassi_giusta():
    for script in SCRIPT.glob("*.sh"):
        assert subprocess.run(["bash", "-n", str(script)], capture_output=True).returncode == 0, script.name


def test_gli_script_python_hanno_sintassi_giusta():
    import ast

    for script in SCRIPT.glob("*.py"):
        ast.parse(script.read_text(encoding="utf-8"))


# --- «collega le AI»: la risposta «si» si mette prima del primo avvio, come se la persona avesse cliccato ----------------------
def estrai_funzione_bash(nome):
    testo = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    inizio = testo.index(f"{nome}() {{")
    return testo[inizio:testo.index("\n}\n", inizio) + 3]


def test_il_seme_della_connessione_mette_si_e_non_sovrascrive_una_scelta(tmp_path):
    funzione = estrai_funzione_bash("seme_connessione")
    nuova = tmp_path / "dati-nuovi"
    subprocess.run(["bash", "-c", f'{funzione}\nseme_connessione "{nuova}"'], check=True)
    assert json.loads((nuova / "config.json").read_text()) == {"connect_answer": "yes"}
    scelta = tmp_path / "gia-scelta"
    scelta.mkdir()
    (scelta / "config.json").write_text('{"connect_answer": "no"}')
    subprocess.run(["bash", "-c", f'{funzione}\nseme_connessione "{scelta}"'], check=True)
    assert json.loads((scelta / "config.json").read_text()) == {"connect_answer": "no"}   # una scelta fatta resta


def test_mac_il_seme_viene_prima_dell_avvio_dell_app():
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    for avvio in ('accendi "/Applications/Memdoria AI Brain.app/Contents/MacOS/Memdoria" nuova', 'accendi "$APP_V/Contents/MacOS/Memdoria" vecchia'):
        assert avvio in mac
        assert mac.rfind("seme_connessione", 0, mac.index(avvio)) < mac.index(avvio)
    assert "connetti.request" not in mac, "la richiesta cancella la risposta e rimostra la domanda: senza schermo non ha risposta"


def test_windows_il_seme_viene_prima_dell_avvio_e_non_si_manda_la_richiesta():
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert win.count("Seme-Connessione") >= 3
    assert win.index("Seme-Connessione $dati\n    Prepara-Feed-Pulsante\n    Accendi $app") > 0
    assert "Seme-Connessione $datiVecchi\n    Accendi $vecchia" in win
    assert "connetti.request" not in win


def test_windows_prima_di_fermarsi_salva_i_dettagli():
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    richiedi = win[win.index("function Richiedi"):win.index("function Controlla")]
    assert richiedi.index("Salva-Dettagli") < richiedi.index("throw")


def test_mac_conta_come_icona_solo_il_processo_dell_icona():
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    assert "pgrep -fc 'tray.py'" not in mac
    assert "runtime/app/tray" in mac and "ps -axo" in mac       # e se sono due, mostra quali


def test_i_nomi_delle_prove_di_powershell_sono_ascii():
    assert (RADICE / "tests" / "lettura.tests.ps1").read_text(encoding="utf-8").isascii()


def test_pagina_dice_il_guasto_in_una_riga_anche_se_il_browser_manca():
    # Su Windows il guasto si vedeva solo come «Node.js v22»: ora la causa sta in una riga che comincia con MALE.
    import subprocess, pathlib, shutil
    if not shutil.which("node"):
        return
    radice = pathlib.Path(__file__).resolve().parent.parent
    r = subprocess.run(["node", str(radice / "scripts" / "pagina.mjs"), "http://127.0.0.1:1/", "x"], capture_output=True, text=True, cwd="/")
    assert r.returncode != 0
    assert r.stdout.strip().splitlines()[-1].startswith("MALE:"), r.stdout + r.stderr


def test_windows_accetta_il_collegamento_ripara_in_italiano_e_in_inglese():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "Ripara Memdoria.lnk" in s and "Repair Memdoria.lnk" in s


def test_windows_aspetta_e_racconta_cosa_resta_della_cartella_vecchia():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "stata tolta (rimasto:" in s and "$fineTolta" in s


def test_windows_dice_l_ultimo_passo_se_la_lettura_non_finisce():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert s.count("ultimoPasso") >= 3


def test_mac_aspetta_il_grafo_e_dice_le_memorie():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-mac.sh").read_text(encoding="utf-8")
    assert "do E=$(conta" in s and "active_memories" in s


def test_workflow_mettono_in_cache_browser_pip_e_npm_senza_percorsi_con_due_punti():
    import pathlib, re
    w = pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows"
    prove = (w / "prove.yml").read_text(encoding="utf-8")
    rilascio = (w / "rilascio.yml").read_text(encoding="utf-8")
    assert prove.count("path: ~/.cache/ms-playwright") == 2
    assert prove.count("cache: npm") == 3 and prove.count("cache: pip") == 3
    assert "browser-win-playwright-1.49.1" in rilascio and "browser-mac-playwright-1.49.1" in rilascio
    for testo in (prove, rilascio):
        for percorso in re.findall(r"^\s+path: (.*)$", testo, re.M):
            assert ".." not in percorso, percorso


def test_pagina_non_aspetta_la_rete_ferma_e_il_mac_non_perde_l_esito():
    import pathlib
    r = pathlib.Path(__file__).resolve().parent.parent / "scripts"
    assert "networkidle" not in (r / "pagina.mjs").read_text(encoding="utf-8")
    mac = (r / "collaudo-mac.sh").read_text(encoding="utf-8")
    assert "| tail -1); local r=$?" not in mac  # il codice di uscita era quello di tail, mai quello di node


def test_collaudi_di_installazione_pulita_mettono_un_cliente_nel_grafo_loro_stessi():
    import pathlib
    r = pathlib.Path(__file__).resolve().parent.parent / "scripts"
    win = (r / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert win.index("Seme-Connessione $dati\n    Prepara-Feed-Pulsante\n    Accendi $app") < win.index("Salva-Memoria $dati 'Il cliente Verdi Srl") < win.index("il grafo si riempie")
    mac = (r / "collaudo-mac.sh").read_text(encoding="utf-8")
    inizio = mac.index("A. Installazione pulita")
    assert mac.index("Verdi Srl", inizio) < mac.index("il grafo si riempie", inizio)


def test_windows_aspetta_l_avvio_automatico_e_non_accetta_la_cartella_vecchia_nemmeno_vuota():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "$fineAvvio" in s and "non ha piu' file" not in s and "programmi accesi" in s


def test_anche_la_versione_nuova_si_prende_dalla_cache_se_il_commit_e_lo_stesso():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "rilascio.yml").read_text(encoding="utf-8")
    assert "matrix.nome == 'nuovo'" not in s and "matrix.nome != 'nuovo'" not in s
    # la chiave porta il commit (la versione nuova e' gia' un commit, non un nome di ramo) e la chiave pubblica di prova
    assert s.count("key: inst-win-${{ matrix.riferimento }}-${{ hashFiles('chiave-prova/pubblica.txt') }}") == 1
    assert s.count("key: inst-mac-${{ matrix.riferimento }}-${{ hashFiles('chiave-prova/pubblica.txt') }}") == 1


def test_il_commit_della_versione_nuova_e_risolto_prima_della_costruzione():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "risolvi-versioni.sh").read_text(encoding="utf-8")
    assert '"nome": "nuovo", "riferimento": sha_nuovo' in s


def test_riservato_dice_le_fasi_lunghe_e_non_perde_il_codice_di_uscita(tmp_path):
    import os, pathlib, subprocess
    radice = pathlib.Path(__file__).resolve().parent.parent
    (tmp_path / "w").mkdir()
    comando = "printf '\\n\\033[1;36m▸ uno\\033[0m\\n'; sleep 21; echo '> due'; sleep 1; echo fine; exit 3"
    r = subprocess.run(["bash", str(radice / "scripts" / "riservato.sh"), "prova", "w", "fine", "--", "bash", "-c", comando],
                       capture_output=True, text=True, cwd=tmp_path, env={**os.environ, "RUNNER_TEMP": str(tmp_path)})
    assert r.returncode == 3, r.stdout + r.stderr
    assert "fasi lunghe: uno 21s" in r.stdout or "fasi lunghe: uno 22s" in r.stdout, r.stdout
    assert "due" not in r.stdout.split("fasi lunghe:")[1]  # le fasi brevi non escono


def test_windows_accende_con_le_opzioni_del_collegamento_di_quella_versione():
    # La 1.0.25 parte con il solo tray.py: con -E -s -S moriva subito e non scriveva niente.
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    corpo = s[s.index("function Accendi"):s.index("function Aspetta-Lettura")]
    assert "CreateShortcut" in corpo and "$collegamento.Arguments" in corpo
    assert "TargetPath -like" in corpo  # solo se il collegamento punta a QUESTA cartella
    assert "'-E', '-s', '-S'" in corpo   # e se non c'e', le opzioni di oggi


def test_le_prove_che_si_saltavano_girano_su_github():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "prove.yml").read_text(encoding="utf-8")
    assert "AI_BRAIN_TEST_SSHD: '1'" in s and "AI_BRAIN_TEST_GRANDE: '1'" in s
    for prova in ("test_online_ssh.py", "test_riservatezza.py"):
        assert prova in s
    # le due che non girano su Linux, con il loro motivo scritto nel workflow
    assert "--deselect backend/tests/test_online_ssh.py::test_a_bridge_left_alive_by_a_crash_is_closed_before_reconnecting" in s
    assert "AI_BRAIN_RUNTIME_PROVA" in s and "runtime VERO" in s
    assert "openssh-server" in s


def test_windows_dice_perche_resta_la_cartella_vecchia_vuota():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "NOTA: la cartella si e'' lasciata togliere" in s and "NOTA: la cartella e' occupata" in s
    assert "Controlla (-not $esiste)" in s  # una cartella rimasta, anche vuota, e' un difetto


def test_windows_aspetta_l_installer_e_racconta_dove_si_ferma_l_aggiornamento_dall_app():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "NOTA: aggiornamento dall'app fermo" in s and "scaricati: [" in s
    assert "inizioInstaller" in s and "attesa $([int]" in s


def test_il_lavoro_extra_non_porta_piu_con_se_neo4j_e_java_che_non_servono():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "prove.yml").read_text(encoding="utf-8")
    extra = s[s.index("  extra:"):s.index("  controlli-pagina:")]
    assert "neo4j.tar.gz" not in extra and "setup-java" not in extra


def test_mac_aspetta_che_i_dati_spariscano_e_windows_nomina_solo_i_programmi_della_cartella_vecchia():
    import pathlib
    r = pathlib.Path(__file__).resolve().parent.parent / "scripts"
    mac = (r / "collaudo-mac.sh").read_text(encoding="utf-8")
    assert 'for i in $(seq 1 12); do [ ! -d "$DATI" ] && break' in mac
    win = (r / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "programmi della cartella vecchia" in win and "$_.ExecutablePath -like \"$vecchia" in win


def test_la_cartella_di_prima_si_controlla_dopo_che_la_app_nuova_e_accesa_e_ha_letto():
    # La toglie l'installer o, al piu', l'app nuova all'apertura: il controllo viene dopo la lettura della versione nuova.
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert s.index("dopo l'aggiornamento la lettura finisce senza errori") < s.index("stata tolta (rimasto:")


def test_windows_rifa_la_richiesta_di_aggiornamento_se_la_versione_di_prima_non_la_legge():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "$ultimaRichiesta" in s and "AddMinutes(2)" in s


def test_windows_dice_chi_tiene_occupata_la_cartella_vecchia_con_handle():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "handle64.exe" in s and "NOTA handle:" in s
    assert s.index("handle64.exe") < s.index("NOTA: la cartella e' occupata")  # prima di dire che e' occupata si cerca chi la tiene


def test_windows_dice_comando_e_padre_del_processo_che_tiene_la_cartella():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "NOTA   comando:" in s and "lanciato da:" in s and "questo collaudo e' il processo" in s


def test_rilascio_server_la_firma_resta_leggibile_a_tutti_dentro_l_immagine():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "rilascio.yml").read_text(encoding="utf-8")
    blocco = s[s.index("Immagine, firma, compressione e controlli"):s.index("Allegato cifrato", s.index("Immagine, firma, compressione e controlli"))]
    assert blocco.index("umask 077") < blocco.index("umask 022") < blocco.index("chmod 644 impronte/impronte.json.firma") < blocco.index("docker cp impronte/impronte.json.firma")


def test_rilascio_windows_il_passo_dei_modelli_non_si_ferma_agli_avvisi_di_python():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "rilascio.yml").read_text(encoding="utf-8")
    inizio = s.index("    - name: Modelli della ricerca\n      shell: powershell")
    passo = s[inizio:s.index("    - name: App e impronte", inizio)]
    assert "$ErrorActionPreference = 'Continue'" in passo and "*> $null" not in passo


def test_lo_schermo_finto_non_si_azzera_quando_si_chiude_l_ultimo_programma():
    # Con 4 processi in parallelo, Xvfb che si azzera dava «Xlib ... Broken pipe» a chi si collegava dopo (giro 38070043954).
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "prove.yml").read_text(encoding="utf-8")
    assert s.count("xvfb-run -a -s \"-screen 0 1280x1024x24 -noreset\"") == 2
    assert "xvfb-run -a python" not in s


def test_windows_riavvia_la_versione_di_prima_se_l_aggiornamento_dall_app_non_parte():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "$riavvii -lt 2" in s and "$ultimoRiavvio.AddMinutes(3)" in s and "riavvio la versione di prima" in s
    assert "$fine = (Get-Date).AddMinutes(9)" in s  # il tempo massimo e' stretto: 15 minuti erano attesa sprecata
    assert s.index('Richiedi ($verInstallata.Trim() -eq $versioneNuova)') < s.index('Accendi $nuova')


def test_windows_stampa_cosa_dicono_i_registri_della_versione_di_prima_sugli_aggiornamenti():
    import pathlib
    s = (pathlib.Path(__file__).resolve().parent.parent / "scripts" / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert "NOTA log:" in s and "nessuna riga sugli aggiornamenti" in s
    assert s.index("NOTA log:") < s.index("NOTA: aggiornamento dall'app fermo.")
def test_collaudo_aggiorna_dalla_1032_e_dalla_1033():
    import json

    versioni = json.loads((Path(__file__).resolve().parents[1] / "versioni-in-uso.json").read_text())
    assert versioni == ["1.0.32", "1.0.33"]


def test_il_collaudo_controlla_il_pulsante_sulla_pagina_rimasta_aperta():
    pagina = (SCRIPT / "pagina.mjs").read_text(encoding="utf-8")
    assert "nav.view-tabs button.update-pill" in pagina
    assert pagina.index("tasto.count() !== 0") < pagina.index("copyFile(feedNuovo, feedAttivo)")
    assert pagina.index("copyFile(feedNuovo, feedAttivo)") < pagina.index("tasto.waitFor({ state: 'visible'")
    assert "tasto.isEnabled()" in pagina and "navigazioni !== 0" in pagina
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    for script in (mac, win):
        assert "--pulsante-aggiornamento" in script and "AI_BRAIN_AGGIORNA_OGNI" in script
        assert "feed.py" in script


def test_il_collaudo_della_migrazione_distingue_1032_e_1033():
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert '1.0.32|1.0.33' in mac and '$SUPPORTO/Memdoria' in mac
    assert 'NOME_V="Memdoria-AI-Brain"' in mac
    assert "$HOME/.config/memdoria-ai-brain/token" in mac and "mcp_servers.memdoria-ai-brain" in mac
    assert "@('1.0.32', '1.0.33')" in win and '$Local\\Memdoria"' in win
    assert "$nomeVecchio = if ($separata) { 'Memdoria' } else { 'Memdoria-AI-Brain' }" in win
    assert 'memdoria-ai-brain\\token' in win and 'mcp_servers\\.memdoria-ai-brain' in win


def test_il_mac_riconosce_l_aggiornamento_sul_percorso_esistente_e_rifiuta_due_app():
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    assert '/Applications/Memdoria AI Brain.app' in mac
    assert 'for candidata in "/Applications/Memdoria AI Brain.app" /Applications/Memdoria.app /Applications/Memdoria-AI-Brain.app' in mac
    assert 'APP_N="$candidata"' in mac and 'controlla_nome_dock; richiedi $?' in mac
    assert '[ "$NUM_APPS" = 1 ]' in mac
    assert 'lsappinfo list' in mac and 'bundleID=\\"it.aibrain.app\\"' in mac
    assert 'bundle path=\\"/Applications/Memdoria AI Brain.app\\"' in mac


def test_il_mac_controlla_prima_riapertura_motore_e_pagina_dopo_entrambi_gli_aggiornamenti():
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    pagina = (SCRIPT / "pagina.mjs").read_text(encoding="utf-8")
    assert 'controlla_primo_avvio' in mac
    assert 'controlla_motore' in mac
    assert '--server-in-riavvio' in mac and '--server-in-riavvio' in pagina
    assert 'Overview unavailable' in pagina and 'I cannot read the graph' in pagina
    assert 'controlla_nome_dock; richiedi $?' in mac
    assert 'nuova-dopo' not in mac  # il collaudo non maschera un mancato riavvio automatico


def test_il_browser_aspetta_che_la_porta_dell_app_si_apra_prima_di_provare_il_riavvio_del_server():
    pagina = (SCRIPT / "pagina.mjs").read_text(encoding="utf-8")
    prima = pagina.split("if (controllo === '--server-in-riavvio')", 1)[1].split('const risposta =', 1)[0]
    assert 'ERR_CONNECTION_REFUSED' in prima
    assert "await pagina.goto(indirizzo, { waitUntil: 'domcontentloaded', timeout: 90_000 })" in prima
    assert 'await pagina.waitForTimeout(500)' in prima


def test_il_browser_aspetta_la_fine_della_prima_lettura_prima_di_giudicare_il_grafo():
    pagina = (SCRIPT / "pagina.mjs").read_text(encoding="utf-8")
    assert "[data-testid=\"cosmos-graph\"]" in pagina
    assert 'waitFor({ timeout: 120_000 })' in pagina
    assert 'i < 240 && !panoramicaTornata' in pagina


def test_mac_chiede_il_collegamento_dei_dati_1032_solo_se_si_parte_dalla_1032():
    mac = (SCRIPT / "collaudo-mac.sh").read_text(encoding="utf-8")
    assert 'if [ "$VER_V" = 1.0.32 ]; then' in mac
    assert 'trasloco fatto: Memdoria e' in mac


def test_windows_controlla_motore_e_pagina_alla_prima_riapertura_dopo_entrambi_gli_aggiornamenti():
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert 'Avvia-Controllo-Motore' in win
    assert '--server-in-riavvio' in win
    assert "@('1.0.32', '1.0.33')" in win
    assert '$pidVecchi' in win and '$nuovoTray' in win
    assert 'VERSION' in win and '$versioneNuova' in win
    assert '$osservaMotore = Avvia-Controllo-Motore' in win
    assert win.index('$osservaMotore = Avvia-Controllo-Motore') < win.index(r'Installa $Nuovo "$env:RUNNER_TEMP\installa-sopra.log"')
    assert win.index('$osservaMotore = Avvia-Controllo-Motore') < win.index(r'Set-Content "$datiVecchi\aggiorna.request"')
    assert 'Wait-Job' in win and 'Receive-Job' in win
    assert 'Controlla-Motore $datiNuovi' not in win


def test_windows_attende_il_motore_anche_se_il_primo_avvio_richiede_piu_di_un_minuto():
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert 'Wait-Job -Job $osservaMotore -Timeout 180' in win
    assert 'monitor non terminato entro 180 secondi' in win


def test_windows_aspetta_l_eseguibile_prima_di_dichiarare_completa_l_installazione():
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert 'while (-not (Test-Path $exeNuovo)' in win
    assert win.index('while (-not (Test-Path $exeNuovo)') < win.index("Controlla (Test-Path $exeNuovo)")
    assert "Name = 'Memdoria AI Brain.exe'" in win and '/api/setup-info' in win and '-Milliseconds 250' in win


def test_windows_aspetta_la_fine_dell_installer_prima_del_nuovo_processo():
    # VERSION ed eseguibile possono apparire mentre la copia continua: nel collaudo 38155424023
    # l'installer era ancora acceso dopo 90 secondi e la prova ha fermato un aggiornamento sano.
    win = (SCRIPT / "collaudo-windows.ps1").read_text(encoding="utf-8")
    assert 'while ((Get-Date) -lt $fineInstaller -and (Installer-InCorso))' in win
    assert win.index('while ((Get-Date) -lt $fineInstaller -and (Installer-InCorso))') < win.index('$fineTray =')
    assert 'Richiedi (-not (Installer-InCorso))' in win
