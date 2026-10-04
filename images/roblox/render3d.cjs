// Serves this folder, opens scene3d.html in headless Chromium and saves each
// shot as _<name>_raw.png. Usage: node render3d.cjs [name...]
const http = require('http'), fs = require('fs'), path = require('path');
const { chromium } = require('playwright-core');
const only = process.argv.slice(2);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const file = path.join(__dirname, decodeURIComponent(req.url.split('?')[0]));
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' }); res.end(data);
  });
}).listen(0, async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage();
  page.on('pageerror', e => console.log('[error]', e.message));
  await page.goto(`http://localhost:${server.address().port}/scene3d.html`);
  await page.waitForFunction(() => window.ready === true, null, { timeout: 120000 });
  const names = only.length ? only : await page.evaluate(() => Object.keys(window.SHOTS));
  for (const name of names) {
    const data = await page.evaluate(n => window.renderShot(n), name);
    fs.writeFileSync(path.join(__dirname, `_${name}_raw.png`), Buffer.from(data.split(',')[1], 'base64'));
    console.log('saved', name);
  }
  await browser.close(); server.close();
});
