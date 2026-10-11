// Apre la pagina vera di Memdoria in un browser e controlla: si carica, niente errori di script, il grafo viene disegnato.
// Uso: node pagina.mjs <indirizzo> <prefisso-schermate>   (le schermate vanno in un allegato cifrato, mai in chiaro)
// Qualunque guasto si dice in UNA riga (la causa, senza tutta la pila), poi si esce con errore.
process.on('uncaughtException', (e) => { console.log(`MALE: ${String(e?.message ?? e).split('\n').slice(0, 2).join(' | ').slice(0, 300)}`); process.exit(1); });
process.on('unhandledRejection', (e) => { console.log(`MALE: ${String(e?.message ?? e).split('\n').slice(0, 2).join(' | ').slice(0, 300)}`); process.exit(1); });
const { chromium } = await import('playwright');
const { apriPaginaDuranteRiavvio, attendiGrafoAllaPrimaLettura } = await import('./attesa-pagina.mjs');
const [indirizzo, prefisso, controllo, feedNuovo, feedAttivo] = process.argv.slice(2);
const errori = [];
const browser = await chromium.launch();
const pagina = await browser.newPage({ viewport: { width: 1280, height: 800 } });
pagina.on('pageerror', (e) => errori.push(String(e).slice(0, 120)));
if (controllo === '--server-in-riavvio') {
  // Si usa il pacchetto realmente installato, mentre il browser simula il server che tarda a tornare.
  // La stessa finestra deve mostrare l'attesa, poi i dati, senza una seconda apertura.
  let lento = true;
  let panoramicaTornata = false;
  await pagina.route('**/api/setup-info', async (route) => {
    const vera = await route.fetch();
    await route.fulfill({ response: vera, json: { ...await vera.json(), mode: 'app', brain: 'server',
      ai_connected: ['prova'], memories: 12, progress: { done: true, events: [] } } });
  });
  await pagina.route('**/api/locale/server', (route) => route.fulfill({ json: lento
    ? { risponde: false, motivo: 'riavvio', pagina: true, messaggio: 'Il server si sta riavviando: i dati tornano da soli.' }
    : { risponde: true, pagina: true } }));
  const nonDisponibile = (route) => lento
    ? route.fulfill({ status: 502, contentType: 'application/json', body: '{"detail":"Server in riavvio"}' })
    : route.fallback();
  await pagina.route('**/api/dashboard', nonDisponibile);
  await pagina.route('**/api/graph/**', nonDisponibile);
  await pagina.route('**/api/graph/overview*', async (route) => {
    if (lento) return nonDisponibile(route);
    const vera = await route.fetch();
    panoramicaTornata = vera.ok();
    await route.fulfill({ response: vera });
  });
  // Nel primo avvio l'icona compare prima che il servizio apra la porta. Appena la pagina è disponibile,
  // la prova resta in quella stessa finestra per vedere l'attesa e il ritorno del grafo.
  await apriPaginaDuranteRiavvio(pagina, indirizzo);
  await pagina.getByRole('status').filter({ hasText: 'Il server si sta riavviando: i dati tornano da soli.' }).waitFor({ timeout: 20_000 });
  await pagina.waitForTimeout(2500);
  const testo = await pagina.locator('body').innerText();
  if (/Overview unavailable|Panoramica non disponibile|I cannot read the graph|Non riesco a leggere il grafo/i.test(testo)) {
    throw new Error('la prima finestra mostra errori del grafo mentre il server riparte');
  }
  await pagina.screenshot({ path: `${prefisso}-attesa.png`, fullPage: true });
  await pagina.evaluate(() => { window.__primaApertura = true; });
  lento = false;
  // Dopo un aggiornamento la prima lettura delle conversazioni può durare oltre mezzo minuto sulle macchine lente.
  // Restiamo nella stessa pagina e aspettiamo i dati reali, senza premere ricarica o riaprire il browser.
  try {
    await attendiGrafoAllaPrimaLettura(pagina);
  } catch (errore) {
    const { mkdirSync, writeFileSync } = await import('node:fs');
    const { join } = await import('node:path');
    const cartella = join(process.env.RUNNER_TEMP || '/tmp', 'riservato');
    mkdirSync(cartella, { recursive: true });
    const stato = await pagina.locator('body').innerText().catch(() => 'pagina non leggibile');
    writeFileSync(join(cartella, 'primo-avvio.log'), `Indirizzo: ${pagina.url()}\nTesto: ${stato}\nErrori: ${errori.join('\n')}\n`);
    throw errore;
  }
  for (let i = 0; i < 240 && !panoramicaTornata; i++) await pagina.waitForTimeout(500);
  const grafo = await pagina.locator('[data-testid="cosmos-graph"]').count();
  const stessa = await pagina.evaluate(() => window.__primaApertura === true);
  const testoDopo = await pagina.locator('body').innerText();
  const erroreDopo = /Overview unavailable|Panoramica non disponibile|I cannot read the graph|Non riesco a leggere il grafo/i.test(testoDopo);
  if (!grafo || !panoramicaTornata || !stessa || erroreDopo || errori.length) {
    throw new Error(`la pagina non torna al grafo nella stessa apertura: ${grafo} grafi, risposta ${panoramicaTornata}, errori ${errori.length}, testo ${erroreDopo}`);
  }
  await pagina.screenshot({ path: `${prefisso}-ritorno.png`, fullPage: true });
  await browser.close();
  console.log('ok: attesa pulita, grafo tornato nella stessa finestra');
  process.exit(0);
}
const risposta = await pagina.goto(indirizzo, { waitUntil: 'domcontentloaded', timeout: 90_000 });
// La pagina tiene sempre una richiesta aperta (aggiornamenti dal vivo): non esiste «rete ferma». Si aspetta il disegno.
await pagina.waitForSelector('canvas, svg', { timeout: 60_000 }).catch(() => {});
await pagina.waitForTimeout(3000);
const titolo = await pagina.title();
const disegno = await pagina.locator('canvas, svg').count();
await pagina.screenshot({ path: `${prefisso}.png`, fullPage: true });
let pulsante = 'non provato';
if (controllo === '--pulsante-aggiornamento') {
  if (!feedNuovo || !feedAttivo) throw new Error('mancano i due percorsi dell’elenco delle versioni');
  const { copyFile } = await import('node:fs/promises');
  const tasto = pagina.locator('nav.view-tabs button.update-pill');
  if (await tasto.count() !== 0) throw new Error('il pulsante è già visibile prima della nuova versione');
  // La pagina resta aperta mentre cambia il feed. La prova deve vedere il pulsante nell'angolo alto a destra,
  // attivo e sulla stessa pagina, senza premere «Controlla» e senza riavviare l'app.
  let navigazioni = 0;
  pagina.on('framenavigated', (frame) => { if (frame === pagina.mainFrame()) navigazioni++; });
  await copyFile(feedNuovo, feedAttivo);
  await tasto.waitFor({ state: 'visible', timeout: 150_000 });
  if (!(await tasto.isEnabled()) || navigazioni !== 0) throw new Error('il pulsante non è attivo sulla pagina rimasta aperta');
  pulsante = 'attivo senza riavvio';
  await pagina.screenshot({ path: `${prefisso}-aggiornamento.png`, fullPage: true });
}
await browser.close();
const ok = risposta && risposta.ok() && errori.length === 0 && disegno > 0;
console.log(`${ok ? 'ok' : 'MALE'}: stato ${risposta?.status()}, titolo "${titolo}", ${disegno} disegni, ${errori.length} errori di script, pulsante ${pulsante}${errori[0] ? ' (' + errori[0] + ')' : ''}`);
process.exit(ok ? 0 : 1);
