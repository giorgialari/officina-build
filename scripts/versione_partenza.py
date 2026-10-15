"""Verifica il verso dell'aggiornamento e sceglie il nome storico del bundle Mac."""
import re
import sys


def numeri(testo):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', testo):
        raise ValueError('numero di versione non valido')
    return tuple(int(n) for n in testo.split('.'))


def nome_bundle(vecchia, nuova):
    prima, dopo = numeri(vecchia), numeri(nuova)
    if not (1, 0, 32) <= prima < dopo:
        raise ValueError('la versione di partenza deve essere almeno 1.0.32 e precedente alla nuova')
    if prima == (1, 0, 32):
        return 'Memdoria'
    if prima == (1, 0, 33):
        return 'Memdoria-AI-Brain'
    return 'Memdoria AI Brain'


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('indicare versione di partenza e versione nuova')
        print(nome_bundle(*sys.argv[1:]))
    except ValueError as errore:
        print(str(errore), file=sys.stderr)
        sys.exit(1)
