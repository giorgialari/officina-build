#!/usr/bin/env bash
# Il disco mostrato nel Finder deve avere una sola app visibile e il collegamento ad Applicazioni.
# I nomi vecchi restano nel disco, nascosti, perché gli aggiornamenti già installati li cercano.
set -eu
trap 'echo "Disco di installazione non conforme, riga $LINENO" >&2' ERR
dmg=$1
punto=$(mktemp -d)
smonta() {
  hdiutil detach "$punto" -quiet 2>/dev/null || true
  rmdir "$punto" 2>/dev/null || true
}
trap smonta EXIT
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$punto" >/dev/null

[ -d "$punto/Memdoria AI Brain.app" ]
[ -L "$punto/Applications" ]
[ "$(readlink "$punto/Applications")" = /Applications ]

for vecchio in 'AI Brain.app' 'Memdoria.app' 'Memdoria-AI-Brain.app'; do
  [ -L "$punto/$vecchio" ]
  [ "$(readlink "$punto/$vecchio")" = 'Memdoria AI Brain.app' ]
  [ "$(stat -f '%Sf' "$punto/$vecchio")" = hidden ]
done

for documento in 'Leggimi.txt' "Licenza d'uso.txt" 'Terms of use.txt'; do
  [ -f "$punto/$documento" ]
  [ "$(stat -f '%Sf' "$punto/$documento")" = hidden ]
done

echo 'OK: una sola app visibile nel disco; collegamenti e documenti presenti ma nascosti.'
