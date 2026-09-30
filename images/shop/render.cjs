// To re-render: in this folder, `npm i three playwright-core`, then
// `node render.cjs . ` (writes 1024px PNGs; the committed ones are downscaled
// to 512px). The scenes themselves are in icons.html.
// Serves this folder, opens icons.html in headless Chromium and saves each
// canvas render as a PNG. Usage: node render.cjs <outDir> [name...]
const http = require('http'), fs = require('fs'), path = require('path');
const { chromium } = require('playwright-core');
const outDir = process.argv[2]; const only = process.argv.slice(3);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript' };
const server = http.createServer((req, res) => {
  const file = path.join(__dirname, decodeURIComponent(req.url.split('?')[0]));
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(0, async () => {
  const port = server.address().port;
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage();
  page.on('console', m => console.log('[page]', m.text()));
  page.on('pageerror', e => console.log('[error]', e.message));
  await page.goto(`http://localhost:${port}/icons.html`);
  await page.waitForFunction(() => window.ready === true, null, { timeout: 60000 });
  const names = only.length ? only : await page.evaluate(() => Object.keys(window.SCENES));
  for (const name of names) {
    const data = await page.evaluate(n => window.renderIcon(n), name);
    fs.writeFileSync(path.join(outDir, name + '.png'), Buffer.from(data.split(',')[1], 'base64'));
    console.log('saved', name);
  }
  await browser.close(); server.close();
});
