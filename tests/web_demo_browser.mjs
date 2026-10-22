import { chromium } from 'playwright';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const root = path.resolve(process.argv[2] ?? 'build/site-offline');
const port = Number(process.env.TEST_PORT ?? 28141);
const base = '/ossuspeitos/';
const errors = [];
const sockets = [];
const engineLogs = [];
const contentTypes = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };

const server = http.createServer((req, res) => {
  let pathname = decodeURIComponent(new URL(req.url, `http://127.0.0.1:${port}`).pathname);
  if (!pathname.startsWith(base)) { res.writeHead(404).end('base path required'); return; }
  pathname = pathname.slice(base.length);
  if (!pathname || pathname.endsWith('/')) pathname += 'index.html';
  const target = path.resolve(root, pathname);
  if (!target.startsWith(root + path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) {
    res.writeHead(404).end('not found'); return;
  }
  res.setHeader('content-type', contentTypes[path.extname(target)] ?? 'application/octet-stream');
  fs.createReadStream(target).pipe(res);
});

const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROMIUM_BIN || undefined,
  args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader'],
});
try {
  await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, ignoreHTTPSErrors: false });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(`PAGE ${error.message}`));
  page.on('console', message => {
    engineLogs.push(message.text());
    if (message.type() === 'error' || /SCRIPT ERROR|ERROR:|Failed to load|WebGL.*(lost|error)/i.test(message.text())) errors.push(`CONSOLE ${message.text()}`);
  });
  page.on('websocket', socket => {
    sockets.push(socket.url());
    socket.on('socketerror', error => errors.push(`SOCKET ${error}`));
  });
  page.on('requestfailed', request => errors.push(`REQUEST ${request.url()} ${request.failure()?.errorText}`));
  page.on('response', response => {
    if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`);
  });

  await page.goto(`http://127.0.0.1:${port}${base}`, { waitUntil: 'networkidle' });
  if (!await page.getByText('DEMONSTRAÇÃO OFFLINE').isVisible()) throw new Error('offline landing label missing');
  if (await page.locator('a[href*="playtest"], a:has-text("ONLINE NO NAVEGADOR")').count()) throw new Error('online link appears on landing');
  if (!await page.getByText(/Multiplayer indisponível/).isVisible()) throw new Error('multiplayer limitation missing');
  await page.getByRole('link', { name: 'ABRIR DEMONSTRAÇÃO' }).click();
  await page.waitForURL(`**${base}demo/`);
  await page.waitForFunction(() => [...document.scripts].some(script => script.src.includes('index.js')));
  await page.waitForFunction(() => document.querySelector('canvas')?.width > 800, null, { timeout: 120_000 });
  await page.waitForTimeout(4000);
  const canvas = page.locator('canvas').first();
  const box = await canvas.boundingBox();
  if (!box || box.width < 800 || box.height < 450) throw new Error(`canvas too small: ${JSON.stringify(box)}`);
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.keyboard.down('w');
  await page.waitForTimeout(500);
  await page.keyboard.up('w');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(4000);
  await page.screenshot({ path: process.env.WEB_SHOTS ? `${process.env.WEB_SHOTS}/offline-demo.png` : '/tmp/offline-demo.png' });
  if (!engineLogs.some(line => /DEMO_READY simulated_players=4 network=disabled/.test(line))) {
    throw new Error(`offline demo readiness marker missing from browser logs: ${engineLogs.filter(Boolean).join(' | ')}`);
  }
  if (sockets.length) throw new Error(`unexpected WebSocket connection: ${sockets.join(', ')}`);
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(`WEB_DEMO_BROWSER_OK base=${base} canvas=${Math.round(box.width)}x${Math.round(box.height)} websocket_count=${sockets.length} stable_ms=8000`);
} catch (error) {
  console.error(`WEB_DEMO_BROWSER_FAILED ${error.stack ?? error}`);
  process.exitCode = 1;
} finally {
  await browser.close();
  server.close();
}
