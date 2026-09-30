// node svg2png.cjs in.svg out.png [size]: renders an SVG with a transparent background.
// Setup: in this folder, `npm i playwright-core`; render with
// `node svg2png.cjs Combat.svg Combat.png 1024`, then downscale to 512px.
const fs = require('fs'); const { chromium } = require('playwright-core');
(async () => {
  const [inp, out, size = '1024'] = process.argv.slice(2);
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const page = await browser.newPage({ viewport: { width: +size, height: +size } });
  const svg = fs.readFileSync(inp, 'utf8').replace(/width="\d+" height="\d+"/, `width="${size}" height="${size}"`);
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await page.locator('svg').screenshot({ path: out, omitBackground: true });
  await browser.close();
})();
