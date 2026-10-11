#!/usr/bin/env python3
"""Aggiunge cronologie interamente inventate al profilo di una VM Lume di prova.

Uso: python3 seme_chat_lume.py /Users/lume
Il seme è ripetibile: gli stessi file vengono riscritti, senza toccare altre chat.
"""

from __future__ import annotations

import json
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


# Due conversazioni per tema. Ogni frase è un'affermazione o una scelta della persona,
# non una proposta dell'AI: l'Engine può ricavarne memorie verificabili dalla fonte.
MONDI = [
    ("faro", "Progetto Faro", [
        ["Il progetto Faro prepara confezioni in carta riciclata per la Bottega Prisma.",
         "Ho scelto il blu mare per le etichette di Faro insieme ad Ada Velin.",
         "La presentazione di Faro è prevista nella Sala Corallo del Centro Niva.",
         "Conservo i campioni delle confezioni di Faro nell'Atelier Marea."],
        ["Per Faro preferisco fotografie reali scattate da Milo Taren alle immagini generate.",
         "Ada Velin cura i testi di Faro e Milo Taren segue le fotografie.",
         "Ho deciso di mostrare le confezioni di Faro alla Fiera delle Idee di Porto Lira.",
         "Per il catalogo di Faro useremo i colori del mare di Porto Lira."],
    ]),
    ("orto", "Giardino Aurora", [
        ["Nel Giardino Aurora coltivo basilico, pomodori e salvia con Nilo Varen.",
         "Il Giardino Aurora si trova accanto alla Casa dei Tigli.",
         "Preferisco irrigare il Giardino Aurora al mattino presto.",
         "Ho raccolto i primi pomodori del Giardino Aurora per la cucina di Casa Zafferano."],
        ["Nel Giardino Aurora ho riservato l'aiuola nord alle erbe aromatiche.",
         "Nilo Varen porta il compost dal Circolo Cartavento ogni venerdì.",
         "Ho scelto semi locali per il Giardino Aurora insieme a Leda Orin.",
         "La festa del raccolto del Giardino Aurora si terrà alla Casa dei Tigli."],
    ]),
    ("viaggio", "Viaggio a Porto Lira", [
        ["A novembre visiterò Porto Lira con Ada Velin e Leda Orin.",
         "Abbiamo prenotato la Locanda delle Vele vicino al Museo delle Correnti.",
         "Preferisco raggiungere Porto Lira in treno e muovermi a piedi.",
         "Voglio dedicare una mattina al Mercato delle Conchiglie di Porto Lira."],
        ["Al Museo delle Correnti ho visto una mostra sulle mappe di mare.",
         "Ho scelto il Sentiero Azzurro per la passeggiata da Porto Lira a Cala Niva.",
         "Ada Velin ha fotografato il faro di Cala Niva per il nostro diario di viaggio.",
         "Alla Locanda delle Vele ho preferito la stanza che guarda il porto."],
    ]),
    ("lettura", "Circolo Cartavento", [
        ["Il Circolo Cartavento si incontra alla Biblioteca Smeraldo ogni secondo sabato.",
         "Con Tessa Miren ho scelto il romanzo Le Isole di Vetro per novembre.",
         "Preferisco incontri di lettura con discussione libera, senza presentazioni lunghe.",
         "Nilo Varen organizza il tavolo dei libri della Biblioteca Smeraldo."],
        ["Al Circolo Cartavento abbiamo letto Le Isole di Vetro con Tessa Miren.",
         "Per dicembre ho proposto il racconto Il Giardino delle Ore al Circolo Cartavento.",
         "La Biblioteca Smeraldo presta la Sala Foglia al nostro circolo.",
         "Tengo le note dei libri del Circolo Cartavento in un quaderno cartaceo."],
    ]),
    ("musica", "Ensemble Rugiada", [
        ["Suono il violoncello nell'Ensemble Rugiada con Elio Saren.",
         "Le prove dell'Ensemble Rugiada si svolgono al Teatro Cometa il martedì.",
         "Preferisco iniziare le prove con il brano Vento di Carta.",
         "Elio Saren dirige il concerto di primavera al Teatro Cometa."],
        ["L'Ensemble Rugiada parteciperà alla Festa di Cala Niva.",
         "Ho scelto di suonare Vento di Carta prima di Notte Chiara.",
         "Per il concerto useremo le luci preparate dall'Atelier Marea.",
         "Dopo le prove con Elio Saren registro le note musicali nel mio quaderno."],
    ]),
    ("cucina", "Casa Zafferano", [
        ["A Casa Zafferano cucino con Mara Velli ogni domenica.",
         "La ricetta della zuppa dorata usa la salvia del Giardino Aurora.",
         "Preferisco servire la zuppa dorata con pane integrale.",
         "Mara Velli organizza la cena d'autunno alla Casa dei Tigli."],
        ["Per la cena d'autunno ho scelto pomodori del Giardino Aurora.",
         "A Casa Zafferano tengo un quaderno per le ricette provate.",
         "Ho preparato i biscotti al limone con Mara Velli per il Circolo Cartavento.",
         "La ricetta dei biscotti al limone viene dalla zia immaginaria Dalia Velli."],
    ]),
    ("animali", "Nebbia e gli animali", [
        ["Nebbia è il mio gatto e dorme vicino alla finestra della Casa dei Tigli.",
         "La veterinaria Iva Solen segue Nebbia alla Clinica Quercia.",
         "Preferisco portare Nebbia alla Clinica Quercia al mattino.",
         "Ho deciso di usare una coperta morbida nel trasportino di Nebbia."],
        ["Nebbia gioca con il gomitolo blu che mi ha regalato Tessa Miren.",
         "Iva Solen ha controllato Nebbia alla Clinica Quercia in primavera.",
         "Nel giardino della Casa dei Tigli Nebbia osserva gli uccelli dalla veranda.",
         "Tengo i documenti di Nebbia in una cartellina nella Casa dei Tigli."],
    ]),
    ("arte", "Atelier Marea", [
        ["All'Atelier Marea dipingo acquerelli con la pittrice Alma Doren.",
         "La mostra Colori di Cala Niva sarà ospitata dal Museo delle Correnti.",
         "Preferisco carta ruvida per gli acquerelli dell'Atelier Marea.",
         "Alma Doren ha scelto tre miei quadri per la mostra."],
        ["Ho dipinto un acquerello del Sentiero Azzurro per Colori di Cala Niva.",
         "All'Atelier Marea conservo pennelli e campioni del progetto Faro.",
         "Per la mostra al Museo delle Correnti userò cornici di legno chiaro.",
         "Milo Taren fotografa i quadri dell'Atelier Marea per il catalogo."],
    ]),
    ("scuola", "Scuola Brina", [
        ["Alla Scuola Brina tengo un laboratorio di disegno con la docente Rina Vale.",
         "Il laboratorio usa foglie del Giardino Aurora come modelli.",
         "Preferisco lasciare ai bambini tempo per osservare prima di disegnare.",
         "Rina Vale organizza la mostra dei disegni nella Sala Foglia."],
        ["Ho portato acquerelli dall'Atelier Marea alla Scuola Brina.",
         "La mostra della Scuola Brina si intitola Piccole Tracce.",
         "Per Piccole Tracce abbiamo scelto cartoncini riciclati della Bottega Prisma.",
         "Rina Vale mi ha chiesto di ripetere il laboratorio in primavera."],
    ]),
    ("volontariato", "Associazione Ponte Blu", [
        ["Faccio volontariato con l'Associazione Ponte Blu a Porto Lira.",
         "Mira Tolen coordina le consegne di libri alla Biblioteca Smeraldo.",
         "Preferisco fare i turni del sabato mattina con Mira Tolen.",
         "L'Associazione Ponte Blu raccoglie libri per la Scuola Brina."],
        ["Abbiamo consegnato libri alla Scuola Brina con l'Associazione Ponte Blu.",
         "Ho scelto la Sala Corallo per la prossima raccolta di libri.",
         "Mira Tolen tiene l'elenco dei libri donati alla Biblioteca Smeraldo.",
         "Per la raccolta di dicembre collaboriamo con il Circolo Cartavento."],
    ]),
    ("cammino", "Gruppo Passo Lento", [
        ["Cammino con il Gruppo Passo Lento sul Sentiero Azzurro ogni mese.",
         "Oren Fali guida il gruppo fino al Rifugio Ventoalto.",
         "Preferisco percorsi con soste frequenti e acqua disponibile.",
         "Il Gruppo Passo Lento si ritrova alla Stazione di Porto Lira."],
        ["Al Rifugio Ventoalto ho incontrato Leda Orin dopo la camminata.",
         "Con Oren Fali abbiamo scelto un percorso breve per novembre.",
         "Tengo una mappa cartacea del Sentiero Azzurro nello zaino.",
         "Il Gruppo Passo Lento visiterà Cala Niva in primavera."],
    ]),
    ("casa", "Casa dei Tigli", [
        ["Abito nella Casa dei Tigli vicino al Giardino Aurora.",
         "Ho scelto tende color sabbia per il soggiorno della Casa dei Tigli.",
         "L'artigiana Vera Solen ripara i mobili della veranda.",
         "Preferisco luce calda nella stanza dove leggo Le Isole di Vetro."],
        ["Vera Solen ha restaurato il tavolo della Casa dei Tigli.",
         "Ho spostato i libri del Circolo Cartavento nella stanza a nord.",
         "Per la veranda ho scelto vasi fatti dalla Bottega Prisma.",
         "Nebbia dorme sul cuscino verde vicino alla libreria."],
    ]),
    ("stelle", "Osservatorio Celeste", [
        ["Visito l'Osservatorio Celeste con Oren Fali una volta al mese.",
         "La guida Sena Moren conduce le serate sulle costellazioni.",
         "Preferisco osservare il cielo dalla Terrazza Niva quando è sereno.",
         "Ho annotato la posizione della Luna nel quaderno dell'Osservatorio Celeste."],
        ["Sena Moren ha organizzato una serata all'Osservatorio Celeste per la Scuola Brina.",
         "Porterò la mappa del cielo alla Terrazza Niva con Oren Fali.",
         "Ho deciso di visitare l'Osservatorio Celeste prima del concerto al Teatro Cometa.",
         "Le fotografie della Luna di Milo Taren saranno esposte nella Sala Foglia."],
    ]),
    ("teatro", "Teatro Cometa", [
        ["Aiuto il Teatro Cometa a preparare la rassegna Storie in Luce.",
         "La regista Nora Falen cura le letture di Storie in Luce.",
         "Ho scelto la Sala Corallo per l'incontro con il Circolo Cartavento.",
         "Preferisco biglietti di carta riciclata per la rassegna."],
        ["Nora Falen ha invitato l'Ensemble Rugiada a Storie in Luce.",
         "Ho preparato il programma della rassegna con Ada Velin.",
         "Il Teatro Cometa ospiterà la mostra Piccole Tracce della Scuola Brina.",
         "Per Storie in Luce useremo le fotografie di Milo Taren."],
    ]),
    ("tecnica", "Archivio Atlas", [
        ["Per l'Archivio Atlas sviluppo un'app in Python con dati in SQLite.",
         "L'Archivio Atlas cataloga le fotografie di Milo Taren per l'Atelier Marea.",
         "Ho scelto di tenere una copia locale dell'Archivio Atlas alla Biblioteca Smeraldo.",
         "Preferisco schermate semplici e leggibili per l'app Archivio Atlas."],
        ["Ho corretto la ricerca nell'Archivio Atlas usando Python.",
         "Per l'Archivio Atlas ho deciso di esportare i dati in CSV ogni venerdì.",
         "Milo Taren ha verificato la lista delle fotografie di Cala Niva.",
         "La copia di SQLite dell'Archivio Atlas resta sul computer di prova."],
    ]),
    ("bottega", "Bottega Prisma", [
        ["La Bottega Prisma produce quaderni artigianali con Leda Orin.",
         "Ho scelto carta riciclata per i quaderni del Circolo Cartavento.",
         "Leda Orin vende i quaderni al Mercato delle Conchiglie.",
         "Preferisco copertine blu e verde per la collezione Marea."],
        ["La collezione Marea della Bottega Prisma sarà presentata a Porto Lira.",
         "Ho ordinato scatole per Faro alla Bottega Prisma.",
         "Leda Orin insegna a rilegare quaderni alla Scuola Brina.",
         "Per il prossimo laboratorio useremo cartoncini della collezione Marea."],
    ]),
]


def scrivi_jsonl(percorso: Path, righe: list[dict]) -> None:
    percorso.parent.mkdir(parents=True, exist_ok=True)
    percorso.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in righe), encoding="utf-8")


def crea(destinazione: Path) -> tuple[int, int]:
    num_claude = num_codex = 0
    for indice, (tema, cartella, sessioni) in enumerate(MONDI):
        for numero, frasi in enumerate(sessioni):
            istante = datetime(2026, 10, 11, 8, 0, tzinfo=timezone.utc) + timedelta(minutes=indice * 22 + numero * 9)
            identita = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"memdoria-seme-1034-{tema}-{numero}"))
            cwd = f"/Users/lume/Mondi-di-prova/{cartella.replace(' ', '-')}"
            if numero == 0:
                righe = []
                for passo, frase in enumerate(frasi):
                    ora = (istante + timedelta(minutes=passo * 2)).isoformat().replace("+00:00", "Z")
                    righe.append({"type": "user", "cwd": cwd, "sessionId": identita,
                                  "timestamp": ora, "message": {"role": "user", "content": frase}})
                    righe.append({"type": "assistant", "cwd": cwd, "sessionId": identita,
                                  "timestamp": ora, "message": {"role": "assistant", "content": [
                                      {"type": "text", "text": "Ho capito e terrò presente quello che hai detto."}]}})
                scrivi_jsonl(destinazione / ".claude/projects" / f"-Users-lume-Mondi-di-prova-{tema}" /
                             f"memdoria-seme-{tema}.jsonl", righe)
                num_claude += 1
            else:
                righe = [{"type": "session_meta", "timestamp": istante.isoformat().replace("+00:00", "Z"),
                          "payload": {"id": identita, "cwd": cwd, "timestamp": istante.isoformat().replace("+00:00", "Z")}}]
                for passo, frase in enumerate(frasi):
                    ora = (istante + timedelta(minutes=passo * 2)).isoformat().replace("+00:00", "Z")
                    righe.append({"type": "event_msg", "timestamp": ora,
                                  "payload": {"type": "user_message", "message": frase}})
                    righe.append({"type": "response_item", "timestamp": ora,
                                  "payload": {"type": "message", "role": "assistant", "content": [
                                      {"type": "output_text", "text": "Ho capito e terrò presente quello che hai detto."}]}})
                scrivi_jsonl(destinazione / ".codex/sessions/2026/10/11" /
                             f"rollout-memdoria-seme-{tema}.jsonl", righe)
                num_codex += 1
    return num_claude, num_codex


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Uso: seme_chat_lume.py CARTELLA_HOME_DELLA_VM")
    claude, codex = crea(Path(sys.argv[1]).expanduser())
    print(f"Create {claude} chat Claude Code e {codex} chat Codex, tutte inventate.")
