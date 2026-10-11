import test from 'node:test';
import assert from 'node:assert/strict';
import { apriPaginaDuranteRiavvio, attendiGrafoAllaPrimaLettura } from '../scripts/attesa-pagina.mjs';

test('la prima apertura recupera la navigazione temporanea alla pagina di errore del browser', async () => {
  let aperture = 0;
  const pagina = {
    async goto() {
      aperture++;
      if (aperture === 1) throw new Error('Navigation to "http://127.0.0.1:8765/app/" is interrupted by another navigation to "chrome-error://chromewebdata/"');
      return { ok: () => true };
    },
    async waitForTimeout() {},
  };
  await apriPaginaDuranteRiavvio(pagina, 'http://127.0.0.1:8765/app/');
  assert.equal(aperture, 2);
});

test('una navigazione con un errore diverso rimane un errore', async () => {
  const pagina = {
    async goto() { throw new Error('ERR_CERT_AUTHORITY_INVALID'); },
    async waitForTimeout() { throw new Error('non doveva attendere'); },
  };
  await assert.rejects(apriPaginaDuranteRiavvio(pagina, 'https://example.test/app/'), /ERR_CERT_AUTHORITY_INVALID/);
});

test('il primo grafo può arrivare dopo i due minuti della prima lettura', async () => {
  let attesa = 0;
  const pagina = { locator: () => ({ first: () => ({
    async waitFor({ timeout }) {
      attesa = timeout;
      if (timeout < 150_000) throw new Error('la lettura impiega 150 secondi');
    },
  }) }) };
  await attendiGrafoAllaPrimaLettura(pagina);
  assert.ok(attesa >= 150_000);
});

test('il collaudo accetta il ripiego previsto quando il runner Mac non ha scheda video', async () => {
  let selettore = '';
  const pagina = { locator: (testo) => {
    selettore = testo;
    return { first: () => ({ async waitFor() {} }) };
  } };
  await attendiGrafoAllaPrimaLettura(pagina);
  assert.match(selettore, /cosmos-graph/);
  assert.match(selettore, /Il grafo non è disponibile su questo computer/);
});
