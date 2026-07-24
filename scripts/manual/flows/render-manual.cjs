'use strict';

const { chromium } = require('playwright');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

async function main() {
const htmlPath = process.env.MANUAL_HTML_PATH;
const pdfPath = process.env.MANUAL_PDF_PATH;

if (!htmlPath || !pdfPath) {
  throw new Error('MANUAL_HTML_PATH y MANUAL_PDF_PATH son obligatorias.');
}

const browser = await chromium.launch({ headless: true });

try {
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1000 },
    colorScheme: 'light',
    reducedMotion: 'reduce',
  });

  await page.goto(pathToFileURL(path.resolve(htmlPath)).href, {
    waitUntil: 'load',
  });

  await page.emulateMedia({ media: 'print' });
  await page.evaluate(async () => {
    if (document.fonts?.ready) {
      await document.fonts.ready;
    }

    const images = Array.from(document.images);
    await Promise.all(images.map((image) => {
      if (image.complete && image.naturalWidth > 0) {
        return Promise.resolve();
      }

      return new Promise((resolve, reject) => {
        image.addEventListener('load', resolve, { once: true });
        image.addEventListener('error', () => reject(new Error(`No se pudo cargar ${image.alt}`)), { once: true });
      });
    }));
  });

  await page.pdf({
    path: path.resolve(pdfPath),
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate: [
      '<div style="width:100%;font-family:Arial,sans-serif;font-size:8px;',
      'color:#667085;text-align:center;padding:0 12mm;">',
      'Gestudio · Manual de usuarios nuevos · Página ',
      '<span class="pageNumber"></span> de <span class="totalPages"></span>',
      '</div>',
    ].join(''),
    margin: {
      top: '12mm',
      right: '12mm',
      bottom: '16mm',
      left: '12mm',
    },
  });
} finally {
  await browser.close();
}

console.log(`PDF generado en ${pdfPath}`);

}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
