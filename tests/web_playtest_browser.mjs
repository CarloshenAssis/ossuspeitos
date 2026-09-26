// Fase 9 (PR2): cliente Web completo no Chromium headless.
//
// Uso: node tests/web_playtest_browser.mjs <dir-do-export> <cenário> [args]
//   offline               abre a página sem servidor: menu pronto, online
//                         configurado para o Railway, sem criar/entrar local.
//   room <porta> <código> entra numa sala de um servidor local pelo menu
//                         (código digitado em minúsculas), marca PRONTO,
//                         joga a rodada, vê o resultado e sai da sala.
//   external              JOGAR ONLINE no servidor padrão (Railway), cria uma
//                         sala e fecha (a sala vazia some em 30 s).
// Cada linha do console do jogo é impressa como `WEB_CONSOLE <texto>`; o
// cenário termina com `WEB_TEST_OK` ou `WEB_TEST_FAILED motivo=...`.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require('playwright');
} catch {
  playwright = require(path.join(process.env.PLAYWRIGHT_GLOBAL || '/opt/node22/lib/node_modules', 'playwright'));
}

const [root, scenario, ...rest] = process.argv.slice(2);
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };

function serve(dir) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const url = new URL(req.url, 'http://localhost');
      let file = path.join(dir, decodeURIComponent(url.pathname));
      if (!file.startsWith(path.resolve(dir))) { res.writeHead(403); res.end(); return; }
      if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
      if (!fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

const lines = [];
function waitFor(pattern, timeoutMs) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const tick = () => {
      const hit = lines.find((line) => pattern.test(line));
      if (hit) return resolve(hit);
      if (Date.now() - started > timeoutMs) return reject(new Error(`timeout waiting ${pattern}`));
      setTimeout(tick, 100);
    };
    tick();
  });
}

async function main() {
  const server = await serve(path.resolve(root));
  const port = server.address().port;
  const browser = await playwright.chromium.launch({
    headless: true,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('console', (msg) => { const text = msg.text(); lines.push(text); console.log(`WEB_CONSOLE ${text}`); });
  page.on('pageerror', (err) => { lines.push(`PAGE_ERROR ${err.message}`); console.log(`WEB_PAGE_ERROR ${err.message}`); });
  let query = '';
  if (scenario === 'room') {
    const [serverPort, code] = rest;
    const typed = `${code.slice(0, 3)}-${code.slice(3)}`.toLowerCase();
    query = `?online-url=${encodeURIComponent(`ws://127.0.0.1:${serverPort}`)}&menu-auto=online&menu-room=join&room-code=${typed}`
      + '&menu-name=Navegador&menu-room-ready-min-players=4&menu-room-leave-after-result=true';
  } else if (scenario === 'external') {
    query = '?menu-auto=online&menu-room=create&menu-name=SondaWeb';
  } else if (scenario === 'offline-injection') {
    // URL de servidor vinda de fora de localhost não pode ser aceita.
    query = '?online-url=wss%3A%2F%2Fevil.example&menu-name=Teste';
  }
  const url = `http://127.0.0.1:${port}/${query}`;
  console.log(`WEB_OPEN ${url}`);
  try {
    await page.goto(url, { waitUntil: 'load', timeout: 60000 });
    const ready = await waitFor(/^MENU_READY /, 60000);
    if (!/local_play=false/.test(ready)) throw new Error('local play visible on web');
    if (scenario === 'offline' || scenario === 'offline-injection') {
      if (!/online=configured source=project_settings/.test(ready)) throw new Error(`unexpected online source: ${ready}`);
      await page.waitForTimeout(2000);
      if (lines.some((l) => /CLIENT_CONNECTING/.test(l))) throw new Error('connected without JOGAR ONLINE');
      await page.screenshot({ path: path.join(process.env.WEB_SHOTS || '.', `web_${scenario}.png`) });
    } else if (scenario === 'room') {
      await waitFor(/^MENU_ROOM_SHOWN code=/, 30000);
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(process.env.WEB_SHOTS || '.', 'web_room.png') });
      await waitFor(/^CLIENT_VIEW id=Navegador game=true/, 60000);
      await page.waitForTimeout(1500);
      await page.screenshot({ path: path.join(process.env.WEB_SHOTS || '.', 'web_match.png') });
      await waitFor(/^CLIENT_ROOM_STATE .* phase=lobby round_id=1 .*result=true/, 90000);
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(process.env.WEB_SHOTS || '.', 'web_result.png') });
      await waitFor(/^MENU_RETURNED reason=left/, 30000);
    } else if (scenario === 'external') {
      const joined = await waitFor(/^ROOM_JOINED id=SondaWeb code=/, 45000);
      console.log(`WEB_EXTERNAL_ROOM ${joined}`);
      await waitFor(/^CLIENT_ROOM_STATE .* phase=lobby round_id=0 players=1 /, 15000);
    } else {
      throw new Error(`unknown scenario ${scenario}`);
    }
    if (lines.some((l) => /SCRIPT ERROR|PAGE_ERROR/.test(l))) throw new Error('script or page error');
    console.log(`WEB_TEST_OK scenario=${scenario}`);
    await browser.close();
    server.close();
    process.exit(0);
  } catch (error) {
    console.log(`WEB_TEST_FAILED scenario=${scenario} motivo=${error.message}`);
    try { await page.screenshot({ path: path.join(process.env.WEB_SHOTS || '.', `web_${scenario}_failure.png`) }); } catch {}
    await browser.close();
    server.close();
    process.exit(1);
  }
}

main();
