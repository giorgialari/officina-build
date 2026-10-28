// La prima riapertura puo' cadere proprio mentre il servizio cambia processo.
// Il browser mostra per un istante la propria pagina di errore: si riprova nella stessa finestra.
const MESSAGGI_TRANSITORI = [
  'ERR_CONNECTION_REFUSED',
  'ERR_CONNECTION_RESET',
  'ERR_EMPTY_RESPONSE',
  'chrome-error://chromewebdata/',
];

export async function apriPaginaDuranteRiavvio(pagina, indirizzo) {
  const limiteApertura = Date.now() + 150_000;
  for (;;) {
    try {
      await pagina.goto(indirizzo, { waitUntil: 'domcontentloaded', timeout: 90_000 });
      return;
    } catch (errore) {
      if (!MESSAGGI_TRANSITORI.some((messaggio) => String(errore).includes(messaggio)) ||
          Date.now() >= limiteApertura) throw errore;
      await pagina.waitForTimeout(500);
    }
  }
}

export async function attendiGrafoAllaPrimaLettura(pagina) {
  // Sul Mac del collaudo la migrazione dalla 1.0.32 ha richiesto circa 150 secondi.
  // I runner Mac possono non offrire la scheda video al browser: in quel caso la pagina mostra il suo ripiego previsto.
  await pagina.locator('[data-testid="graph"], [data-testid="cosmos-graph"], .graph-state:has-text("Il grafo non è disponibile su questo computer")')
    .first().waitFor({ timeout: 240_000 });
}
