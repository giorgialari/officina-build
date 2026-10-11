// Apre la pagina vera di Memdoria in un browser e controlla: si carica, niente errori di script, il grafo viene disegnato.
// Uso: node pagina.mjs <indirizzo> <prefisso-schermate>   (le schermate vanno in un allegato cifrato, mai in chiaro)
// Qualunque guasto si dice in UNA riga (la causa, senza tutta la pila), poi si esce con errore.
process.on('uncaughtException', (e) => { console.log(`MALE: ${String(e?.message ?? e).split('\n').slice(0, 2).join(' | ').slice(0, 300)}`); process.exit(1); });
process.on('unhandledRejection', (e) => { console.log(`MALE: ${String(e?.message ?? e).split('\n').slice(0, 2).join(' | ').slice(0, 300)}`); process.exit(1); });
const { chromium } = await import('playwright');
const [indirizzo, prefisso, controllo, feedNuovo, feedAttivo] = process.argv.slice(2);
const errori = [];
const browser = await chromium.launch();
const pagina = await browser.newPage({ viewport: { width: 1280, height: 800 } });
pagina.on('pageerror', (e) => errori.push(String(e).slice(0, 120)));
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
