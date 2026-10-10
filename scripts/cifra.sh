#!/usr/bin/env bash
# Cifra con la chiave pubblica di registri.pem tutti i file .log che trova in $RUNNER_TEMP/riservato (per l'allegato).
set -u
cartella="${RUNNER_TEMP:-/tmp}/riservato"
for f in "$cartella"/*.log; do
  [ -f "$f" ] || continue
  openssl cms -encrypt -aes256 -binary -in "$f" -out "${f%.log}.cms" -outform DER "${GITHUB_WORKSPACE:-.}/registri.pem" && rm -f "$f"
done
ls "$cartella" 2>/dev/null | sed 's/^/allegato: /'
