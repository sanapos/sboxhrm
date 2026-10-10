#!/usr/bin/env node
// Chụp giao diện 5 màn kho (điện thoại 390×844 + máy tính 1366×860) trên bản web LOCAL,
// gồm danh sách, mở phiếu đầu tiên và màn tạo phiếu (điện thoại: nút nổi góc dưới phải).
// Ảnh lưu ở tools/local-test/out/ui/ + một trang tổng hợp index.html để xem nhanh.
//
//   node ui-shots.js            (cần API + web proxy local đang chạy — xem README.md)
//   SBOX_UI_ONLY=PosStockCounts node ui-shots.js     (chỉ một màn)
'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright-core');
const { login } = require('./lib/api');

const WEB = process.env.SBOX_WEB || 'http://localhost:8190';
const CHROME = process.env.CHROME_PATH || [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  '/usr/bin/google-chrome',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
].find((p) => fs.existsSync(p));

const SCREENS = [
  ['PosPurchaseReceipts', 'Nhập hàng NCC'],
  ['PosPurchaseReturns', 'Trả hàng NCC'],
  ['PosDamageIssues', 'Xuất hủy'],
  ['PosInternalUseIssues', 'Xuất dùng nội bộ'],
  ['PosStockCounts', 'Kiểm kho'],
].filter(([m]) => !process.env.SBOX_UI_ONLY || process.env.SBOX_UI_ONLY.split(',').includes(m));

const VIEWS = [
  // [tên, rộng, cao, các bước sau khi mở màn: [tên ảnh, [x,y] để bấm | null]]
  ['mobile', 390, 844, [['list', null], ['detail', [195, 190]], ['create', [300, 750]]]],
  ['desktop', 1366, 860, [['list', null], ['detail', [300, 230]]]],
];

(async () => {
  if (!CHROME) throw new Error('Không thấy Chrome — đặt CHROME_PATH.');
  const { token, refresh } = await login();
  const out = path.join(__dirname, 'out', 'ui');
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const shots = [];
  const errors = [];
  try {
    for (const [module, label] of SCREENS) {
      for (const [view, w, h, steps] of VIEWS) {
        for (const [step, click] of steps) {
          const page = await browser.newPage({ viewport: { width: w, height: h } });
          page.on('pageerror', (e) => errors.push(`${module}/${view}/${step}: ${e.message}`));
          await page.goto(WEB + '/');
          // Phiên đăng nhập + mở thẳng chức năng (giống link /#/m/<Mã>).
          await page.evaluate(([a, r, m]) => {
            localStorage.setItem('flutter.access_token', JSON.stringify(a));
            localStorage.setItem('flutter.refresh_token', JSON.stringify(r));
            sessionStorage.setItem('sbox_module', m);
          }, [token, refresh, module]);
          await page.reload();
          await page.waitForTimeout(9000);
          if (click) {
            await page.mouse.click(click[0], click[1]);
            await page.waitForTimeout(3500);
          }
          const file = `${module}-${view}-${step}.png`;
          await page.screenshot({ path: path.join(out, file) });
          shots.push({ module, label, view, step, file });
          console.log(`  ảnh ${file}`);
          await page.close();
        }
      }
    }
  } finally {
    await browser.close();
  }
  const rows = SCREENS.map(([m, label]) => `
    <h2>${label} <small>${m}</small></h2>
    <div class="row">${shots.filter((s) => s.module === m)
      .map((s) => `<figure class="${s.view}"><img src="${s.file}" loading="lazy"><figcaption>${s.view} · ${s.step}</figcaption></figure>`)
      .join('')}</div>`).join('');
  fs.writeFileSync(path.join(out, 'index.html'), `<!doctype html><meta charset="utf-8"><title>Giao diện kho — local</title>
<style>body{font:14px system-ui;margin:16px;background:#f6f7f9}h2{margin:24px 0 8px}small{color:#888;font-weight:400}
.row{display:flex;gap:12px;overflow-x:auto}figure{margin:0;background:#fff;padding:6px;border-radius:8px}
figure.mobile img{width:260px}figure.desktop img{width:640px}figcaption{text-align:center;color:#666;margin-top:4px}</style>
<h1>Giao diện kho — ${new Date().toLocaleString('vi-VN')}</h1>${errors.length ? `<pre style="color:#b00">${errors.join('\n')}</pre>` : ''}${rows}`);
  console.log(`\nXong ${shots.length} ảnh → ${path.join(out, 'index.html')}${errors.length ? `\nLỗi trang: ${errors.length}` : ''}`);
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
