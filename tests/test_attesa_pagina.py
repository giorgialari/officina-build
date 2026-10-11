"""Regressioni del primo browser durante l'aggiornamento, eseguite dal collaudo degli script."""

import shutil
import subprocess
from pathlib import Path

import pytest


def test_attesa_pagina_durante_la_prima_riapertura():
    node = shutil.which("node")
    if not node:
        pytest.skip("Node non disponibile")
    prova = Path(__file__).with_name("attesa_pagina.test.mjs")
    risultato = subprocess.run([node, "--test", str(prova)], capture_output=True, text=True)
    assert risultato.returncode == 0, risultato.stdout + risultato.stderr
