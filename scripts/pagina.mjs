// Apre la pagina vera di Memdoria in un browser e controlla: si carica, niente errori di script, il grafo viene disegnato.
// Uso: node pagina.mjs <indirizzo> <prefisso-schermate>   (le schermate vanno in un allegato cifrato, mai in chiaro)
import { chromium } from 'playwright';
const [indirizzo, prefisso] = process.argv.slice(2);
const errori = [];
const browser = await chromium.launch();
const pagina = await browser.newPage({ viewport: { width: 1280, height: 800 } });
pagina.on('pageerror', (e) => errori.push(String(e).slice(0, 120)));
const risposta = await pagina.goto(indirizzo, { waitUntil: 'networkidle', timeout: 90_000 });
await pagina.waitForTimeout(8000);
const titolo = await pagina.title();
const disegno = await pagina.locator('canvas, svg').count();
await pagina.screenshot({ path: `${prefisso}.png`, fullPage: true });
await browser.close();
const ok = risposta && risposta.ok() && errori.length === 0 && disegno > 0;
console.log(`${ok ? 'ok' : 'MALE'}: stato ${risposta?.status()}, titolo "${titolo}", ${disegno} disegni, ${errori.length} errori di script${errori[0] ? ' (' + errori[0] + ')' : ''}`);
process.exit(ok ? 0 : 1);
