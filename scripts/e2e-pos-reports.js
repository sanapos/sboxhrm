// E2E POS local: nghiệp vụ thật qua API của app → so báo cáo (chênh lệch trước / sau) với số tự tính.
// Chạy: SBOX_TOKEN=<access token của cửa hàng thử> [SBOX_API=http://localhost:7099] node scripts/e2e-pos-reports.js
// CHỈ chạy trên DB thử (local) — script tạo hàng, đơn, phiếu kho thật.
const fs = require('fs');
const t = process.env.SBOX_TOKEN || (() => { throw new Error('Thiếu SBOX_TOKEN'); })();
const B = process.env.SBOX_API || 'http://localhost:7099';
const H = { Authorization: 'Bearer ' + t, 'Content-Type': 'application/json' };
const today = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
const tag = 'E2E' + Date.now().toString().slice(-5);
const results = [];
const log = (...a) => console.log(...a);

async function call(method, path, body) {
  const r = await fetch(B + path, { method, headers: H, body: body === undefined ? undefined : JSON.stringify(body) });
  const txt = await r.text();
  let j; try { j = JSON.parse(txt); } catch { j = { raw: txt }; }
  if (!r.ok || j.isSuccess === false) throw new Error(`${method} ${path} → ${r.status} ${j.message || txt.slice(0, 300)}`);
  return j.data;
}
const near = (a, b) => Math.abs((a ?? 0) - (b ?? 0)) < 1;
function check(name, actual, expected) {
  const ok = near(actual, expected);
  results.push({ name, actual, expected, ok });
  log(`${ok ? '  ✅' : '  ❌'} ${name}: thực tế ${actual} · mong đợi ${expected}`);
}

async function snapshot() {
  const q = `?from=${today}&to=${today}`;
  const [sales, pnl, cash, purch, vouch, cust, supp, stock, eod, profit] = await Promise.all([
    call('GET', '/api/pos/reports/sales/summary' + q),
    call('GET', '/api/pos/reports/pnl/summary' + q),
    call('GET', '/api/pos/reports/cashbook/summary' + q),
    call('GET', '/api/pos/reports/purchases/summary' + q),
    call('GET', '/api/pos/reports/vouchers/summary' + q),
    call('GET', '/api/pos/reports/customer-debt'),
    call('GET', '/api/pos/reports/supplier-debt'),
    call('GET', '/api/pos/reports/stock/summary'),
    call('GET', '/api/pos/reports/end-of-day' + q),
    call('GET', '/api/pos/reports/profit/by-product' + q),
  ]);
  return { sales, pnl, cash, purch, vouch, cust, supp, stock, eod, profit };
}

(async () => {
  log(`== E2E POS ${tag} · ngày ${today}`);
  const before = await snapshot();

  // 1) Danh mục: nhà cung cấp, khách, 2 hàng hóa + 1 dịch vụ
  const sup = await call('POST', '/api/pos/purchase/suppliers', { name: `NCC ${tag}`, phone: '0911' + tag.slice(-6) });
  const cus = await call('POST', '/api/pos/customers', { name: `Khách ${tag}`, phone: '0922' + tag.slice(-6) });
  const mk = (name, price, cost, type = 0, unit = 'Cái') =>
    call('POST', '/api/pos/products/quick', { name: `${name} ${tag}`, basePrice: price, costPrice: cost, onHandQty: 0, baseUnitName: unit, productType: type, vatRate: 0, vatExempt: true });
  const P1 = await mk('Cà phê sữa', 25000, 10000, 0, 'Ly');
  const P2 = await mk('Bánh mì', 15000, 8000, 0, 'Ổ');
  const P3 = await mk('Phí giao hàng', 10000, 0, 1, 'Lần');
  log('1) Tạo NCC, khách, 3 hàng:', P1.productCode, P2.productCode, P3.productCode);

  // 2) Nhập hàng: P1 40 @10k, P2 30 @8k = 640.000, trả 400.000 (nợ NCC 240.000)
  const line = (p, qty, cost) => ({ productId: p.id, qty, costPrice: cost, discountAmount: 0, vatRate: 0, vatIncluded: true, vatExempt: true, unitName: p.baseUnitName });
  const rc = await call('POST', '/api/pos/purchase/receipts', {
    supplierId: sup.id, note: tag, discountAmount: 0, discountIsPercent: false, discountInput: 0,
    paidAmount: 400000, complete: true, paymentMethod: 'Tiền mặt', lines: [line(P1, 40, 10000), line(P2, 30, 8000)],
  });
  // Phiếu nhập không chọn NCC (trả đủ ngay): 5 ly @10k = 50.000
  const rc2 = await call('POST', '/api/pos/purchase/receipts', {
    supplierId: null, note: tag + ' không NCC', discountAmount: 0, discountIsPercent: false, discountInput: 0,
    paidAmount: 50000, complete: true, paymentMethod: 'Tiền mặt', lines: [line(P1, 5, 10000)],
  });
  log('2b) Nhập không NCC', rc2.receiptNo, rc2.status);
  log('2) Nhập hàng', rc.receiptNo, rc.status, 'tổng', rc.totalAmount ?? rc.total, 'đã trả', rc.paidAmount);

  // 3) Bán 4 đơn
  const sale = (lines, extra) => call('POST', '/api/pos/sales', {
    lines: lines.map(([p, qty, disc]) => ({ productId: p.id, qty, unitPrice: p.basePrice, discountAmount: disc || 0 })),
    discount: 0, paidAmount: 0, paymentMethod: 'Tiền mặt', complete: true,
    clientRequestId: tag + Math.random().toString(36).slice(2), ...extra,
  });
  const O1 = await sale([[P1, 2], [P2, 1]], { paidAmount: 65000 });
  const O2 = await sale([[P1, 3]], { discount: 5000, paidAmount: 70000, paymentMethod: 'Chuyển khoản' });
  const O3 = await sale([[P2, 4], [P3, 1]], { customerId: cus.id, customerName: cus.name, paidAmount: 30000 });
  // voucher giảm 5.000
  const vcode = 'V' + tag;
  await call('POST', '/api/pos/vouchers', { code: vcode, name: vcode, discountType: 1, discountValue: 5000, minOrderAmount: 0, isActive: true });
  // O4: voucher 5k (server tự trừ), khách đưa 25.000 cho đơn 20.000 → thối 5.000
  const O4 = await sale([[P1, 1]], { voucherCode: vcode, paidAmount: 25000 });
  // O5: giảm 3.000 trên dòng
  const O5 = await sale([[P2, 2, 3000]], { paidAmount: 27000 });
  for (const o of [O1, O2, O3, O4, O5]) log('3) Đơn', o.orderNo, 'tổng', o.total, 'đã trả', o.paidAmount, o.status);

  // 4) Khách trả 1 ly cà phê của O1 (tiền mặt)
  await call('POST', `/api/pos/sales/${O1.id}/return`, { lines: [{ productId: P1.id, qty: 1 }], note: tag, refundPaymentMethod: 'Tiền mặt' });
  log('4) Trả hàng O1: 1 ', P1.name);

  // 5) Thu nợ khách 20.000 cho O3
  await call('POST', `/api/pos/customers/${cus.id}/payments`, { amount: 20000, paymentMethod: 'Tiền mặt', note: tag, saleOrderId: O3.id });
  log('5) Thu nợ khách 20.000');

  // 6) Kiểm kho P2: máy 25 → đếm 23 (thiếu 2 = 16.000)
  const cnt = await call('POST', '/api/pos/stock/counts', { name: tag, note: tag });
  const cntL = await call('POST', `/api/pos/stock/counts/${cnt.id}/lines/add`, [{ productId: P2.id }]);
  const l2 = cntL.lines.find(l => l.productId === P2.id);
  log('6) Kiểm kho: số máy P2 =', l2.systemQty);
  await call('PUT', `/api/pos/stock/counts/${cnt.id}/lines`, { lines: [{ lineId: l2.id, countedQty: 21, isChecked: true }] });
  const cntDone = await call('POST', `/api/pos/stock/counts/${cnt.id}/complete`, {});
  log('   hoàn thành', cntDone.countNo, cntDone.status);

  // 7) Xuất hủy P1 ×2 (20.000), dùng nội bộ P2 ×1 (8.000)
  async function issue(kind, p, qty, note) {
    const d = await call('POST', `/api/pos/stock/${kind}`, {});
    const withLines = await call('POST', `/api/pos/stock/${kind}/${d.id}/lines/add`, [{ productId: p.id }]);
    const ln = withLines.lines.find(l => l.productId === p.id);
    await call('PUT', `/api/pos/stock/${kind}/${d.id}/lines`, { lines: [{ lineId: ln.id, qty }] });
    await call('PUT', `/api/pos/stock/${kind}/${d.id}`, { note });
    return call('POST', `/api/pos/stock/${kind}/${d.id}/complete`, {});
  }
  const dmg = await issue('damage', P1, 2, 'Đổ vỡ ' + tag);
  const iu = await issue('internal-use', P2, 1, 'Nhân viên ăn sáng ' + tag);
  log('7) Xuất hủy', dmg.issueNo, dmg.totalValue, '· dùng nội bộ', iu.issueNo, iu.totalValue);

  // 8) Trả NCC P1 ×3 @10k, trừ công nợ
  const pr = await call('POST', '/api/pos/purchase/returns', {
    supplierId: sup.id, note: tag, discountAmount: 0, refundReceived: 0, complete: true,
    lines: [{ productId: P1.id, qty: 3, costPrice: 10000, discountAmount: 0, unitName: P1.baseUnitName }],
  });
  log('8) Trả NCC', pr.returnNo, pr.status);

  const after = await snapshot();
  const d = (f) => (f(after) ?? 0) - (f(before) ?? 0);

  log('\n== Tồn kho từng hàng');
  const g = async (p) => call('GET', `/api/pos/products/${p.id}`);
  check('Tồn Cà phê (40 +5 −2 −3 −1 +1 trả −2 hủy −3 trả NCC)', (await g(P1)).onHandQty, 35);
  check('Tồn Bánh mì (30 −1 −4 −2 → đếm 21 −1 nội bộ)', (await g(P2)).onHandQty, 20);

  log('\n== Báo cáo doanh thu (chênh lệch hôm nay)');
  check('Số đơn bán', d(s => s.sales.orderCount), 5);
  check('Đã thu của đơn (40k sau trả + 70k + 50k gồm thu nợ + 20k + 27k)', d(s => s.sales.totalPaid), 207000);
  check('Giảm giá (5k đơn + 5k voucher + 3k dòng)', d(s => s.sales.totalDiscount), 13000);
  check('Hoàn trả (1 ly cà phê)', d(s => s.sales.totalRefund), 25000);
  check('Doanh thu thuần (265k − 13k giảm − 25k trả)', d(s => s.sales.totalRevenue), 227000);
  check('Giá vốn (6 ly ×10k + 7 bánh ×8k − 1 ly trả)', d(s => s.sales.totalCogs), 106000);
  check('Lãi gộp', d(s => s.sales.totalProfit), 121000);

  log('\n== Lãi lỗ');
  check('PnL doanh thu', d(s => s.pnl.revenue), 227000);
  check('PnL giá vốn', d(s => s.pnl.cogs), 106000);
  check('Chi phí hủy hàng (2 ly ×10k)', d(s => s.pnl.damageCost), 20000);
  check('Chi phí dùng nội bộ (1 bánh ×8k)', d(s => s.pnl.internalUseCost), 8000);
  check('Thiếu khi kiểm kho (2 bánh ×8k)', d(s => s.pnl.countLossCost), 16000);

  log('\n== Sổ quỹ');
  check('Thu (65k + 70k + 30k + 20k + 27k bán + 20k thu nợ — không gồm tiền thối)', d(s => s.cash.income), 232000);
  check('Chi (400k + 50k trả nhập hàng + 25k hoàn khách)', d(s => s.cash.expense), 475000);

  log('\n== Nhập hàng / NCC');
  check('Số phiếu nhập', d(s => s.purch.receiptCount), 2);
  check('SL nhập', d(s => s.purch.receiptQty), 75);
  check('Tiền nhập', d(s => s.purch.receiptAmount), 690000);
  check('Đã trả nhập hàng trong kỳ (400k NCC + 50k phiếu không NCC)', d(s => s.purch.paidInPeriod), 450000);
  check('Phiếu trả NCC', d(s => s.purch.returnCount), 1);
  check('Giá trị trả NCC', d(s => s.purch.returnAmount), 30000);
  check('Công nợ NCC (+240k −30k)', d(s => s.supp.sumDebt), 210000);

  log('\n== Khách / voucher / tồn kho tổng');
  check('Công nợ khách (40k − 20k thu)', d(s => s.cust.sumDebt), 20000);
  check('Lượt dùng voucher', d(s => s.vouch.uses), 1);
  check('Tiền giảm voucher', d(s => s.vouch.totalDiscount), 5000);
  check('Tổng SL tồn (+35 +20)', d(s => s.stock.totalQty), 55);
  check('Giá trị tồn (35×10k + 20×8k)', d(s => s.stock.inventoryValue), 510000);

  log('\n== Cuối ngày');
  check('EOD số đơn', d(s => s.eod.orderCount), 5);
  check('EOD hoàn trả', d(s => s.eod.refundTotal), 25000);
  check('EOD khách còn nợ', d(s => s.eod.debtTotal), 20000);
  const o4 = await call('GET', `/api/pos/sales/${O4.id}`);
  check('O4: tổng sau voucher', o4.total, 20000);
  check('O4: đã trả (không gồm tiền thối)', o4.paidAmount, 20000);

  const rec = await call('GET', `/api/cashtransactions/reconcile?fromDate=${today}&toDate=${today}`);
  log('\n== Đối soát sổ quỹ ↔ chứng từ:', rec.checkedVouchers, 'phiếu,', rec.checkedOrders, 'đơn,', rec.issues.length, 'vấn đề');
  for (const i of rec.issues) log('   ⚠', i.kind, i.documentNo || i.cashCode, i.message);
  check('Đối soát: vấn đề của các đơn test', rec.issues.filter(i => [O1, O2, O3, O4, O5].some(o => o.orderNo === i.documentNo)).length, 0);

  const fail = results.filter(r => !r.ok);
  log(`\n== KẾT QUẢ: ${results.length - fail.length}/${results.length} đạt`);
  fs.writeFileSync(require('os').tmpdir() + '/e2e_pos_result.json', JSON.stringify({ tag, today, results, ids: { P1: P1.id, P2: P2.id, P3: P3.id, O1: O1.id, O2: O2.id, O3: O3.id, O4: O4.id, O5: O5.id, sup: sup.id, cus: cus.id } }, null, 1));
})().catch(e => { console.error('LỖI:', e.message); process.exit(1); });
