"""Le versioni nuove non devono richiedere una lista aggiornata a mano."""
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'versione_partenza.py'


@pytest.mark.parametrize('vecchia,nuova,nome', [
    ('1.0.32', '1.0.41', 'Memdoria'),
    ('1.0.33', '1.0.41', 'Memdoria-AI-Brain'),
    ('1.0.34', '1.0.41', 'Memdoria AI Brain'),
    ('1.0.40', '1.0.41', 'Memdoria AI Brain'),
    ('1.0.41', '1.0.42', 'Memdoria AI Brain'),
    ('1.0.99', '1.0.100', 'Memdoria AI Brain'),
])
def test_accetta_le_versioni_precedenti_e_sceglie_il_bundle(vecchia, nuova, nome):
    r = subprocess.run([sys.executable, str(SCRIPT), vecchia, nuova], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == nome


@pytest.mark.parametrize('vecchia,nuova', [('1.0.31', '1.0.41'), ('1.0.41', '1.0.41'),
    ('1.0.42', '1.0.41'), ('1.0', '1.0.41'), ('', '1.0.41'), ('1.0.40', 'non-valida')])
def test_rifiuta_pacchetti_errati_e_ritorni_indietro(vecchia, nuova):
    r = subprocess.run([sys.executable, str(SCRIPT), vecchia, nuova], capture_output=True, text=True)
    assert r.returncode == 1
    assert not r.stdout
