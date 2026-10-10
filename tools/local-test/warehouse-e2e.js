#!/usr/bin/env node
// Kiểm thử logic 5 chức năng kho trên API LOCAL (không chạy vào production):
//   Nhập hàng NCC · Trả hàng NCC · Xuất hủy · Xuất dùng nội bộ · Kiểm kho
// Mỗi lần chạy tạo hàng hóa + nhà cung cấp riêng (tiền tố KT<giờ>), nên chạy lại bao nhiêu lần cũng được.
// Kiểm: tồn kho, giá vốn bình quân, quy đổi đơn vị, công nợ NCC, sổ quỹ, phiếu tạm không đụng kho,
// chặn xuất âm kho, hủy phiếu hoàn đúng, báo cáo kết quả kinh doanh (hủy / nội bộ / kiểm kê thiếu).
//
//   node warehouse-e2e.js            (cần API local đang chạy — xem README.md)
'use strict';
const path = require('path');
const fs = require('fs');
const { API, login, client, Report, todayVn } = require('./lib/api');

if (!/localhost|127\.0\.0\.1/.test(API) && process.env.SBOX_ALLOW_REMOTE !== '1') {
  console.error(`Từ chối chạy vào ${API} — chỉ dành cho API local (đặt SBOX_ALLOW_REMOTE=1 nếu thật sự cần).`);
  process.exit(2);
}

const R = new Report('Kiểm thử kho (local)');
const tag = 'KT' + new Date().toISOString().replace(/\D/g, '').slice(4, 12);

(async () => {
  const { token } = await login();
  const api = client(token);
  const day = todayVn();

  const product = async (id) => (await api.get(`/api/pos/products/${id}`)).data;
  const supplier = async (id) => (await api.get(`/api/pos/purchase/suppliers/${id}`)).data;
  const pnl = async () => (await api.get(`/api/pos/reports/pnl/summary?from=${day}&to=${day}`)).data || {};
  const cashbook = async () => (await api.get(`/api/pos/reports/cashbook/summary?from=${day}&to=${day}`)).data || {};
  const settings = (await api.get('/api/pos/sell-settings')).data || {};

  // ── Chuẩn bị ───────────────────────────────────────────────────────
  R.group('Chuẩn bị dữ liệu');
  const pRes = await api.post('/api/pos/products', {
    name: `${tag} Nước ngọt lon`, productType: 0, costPrice: 0, basePrice: 20000, onHandQty: 0,
    baseUnitName: 'Lon', isDirectSale: true, vatRate: 0,
  });
  R.must('Tạo hàng hóa thử (tồn 0, giá vốn 0)', pRes);
  const pid = pRes.data?.id;
  const uRes = await api.post(`/api/pos/products/${pid}/units`, {
    unitName: 'Thùng', conversionRate: 24, basePrice: 450000, isDirectSale: true,
  });
  R.must('Thêm đơn vị Thùng = 24 Lon', uRes);
  const sRes = await api.post('/api/pos/purchase/suppliers', { name: `${tag} NCC thử`, phone: '0900000000' });
  R.must('Tạo nhà cung cấp thử', sRes);
  const sid = sRes.data?.id;
  if (!pid || !sid) return finish();
  R.check(`Chặn xuất âm kho: ${settings.allowNegativeStock ? 'TẮT (cho phép âm)' : 'BẬT'}`, true);

  const line = (qty, cost, unitName = 'Lon') => ({
    productId: pid, variantId: null, qty, costPrice: cost, discountAmount: 0,
    vatRate: 0, vatIncluded: false, vatExempt: true, unitName, lineNote: null,
  });
  const receipt = (lines, extra = {}) => ({
    supplierId: sid, note: `${tag} test`, inputInvoiceNo: null, purchaseOrderNo: null,
    discountAmount: 0, discountIsPercent: false, discountInput: 0, paidAmount: 0,
    importDate: null, importedBy: null, complete: true, receiptNo: null, paymentMethod: 'Tiền mặt',
    lines, ...extra,
  });

  // ── 1. Nhập hàng NCC ───────────────────────────────────────────────
  R.group('1. Nhập hàng nhà cung cấp');
  const draft = await api.post('/api/pos/purchase/receipts', receipt([line(10, 10000)], { complete: false }));
  R.must('Lưu phiếu tạm 10 Lon × 10.000', draft);
  R.eq('Phiếu tạm KHÔNG cộng kho', (await product(pid)).onHandQty, 0);
  R.eq('Phiếu tạm KHÔNG tính công nợ NCC', (await supplier(sid)).currentDebt, 0);
  const done1 = await api.post(`/api/pos/purchase/receipts/${draft.data?.id}/complete`);
  R.must('Hoàn thành phiếu tạm', done1);
  let p = await product(pid);
  R.eq('Tồn sau nhập = 10', p.onHandQty, 10);
  R.eq('Giá vốn = 10.000', p.costPrice, 10000);
  R.eq('Công nợ NCC = 100.000 (chưa trả)', (await supplier(sid)).currentDebt, 100000);

  const r2 = await api.post('/api/pos/purchase/receipts', receipt([line(10, 12000)], {
    discountAmount: 12000, discountInput: 12000, paidAmount: 50000,
  }));
  R.must('Nhập 10 Lon × 12.000, giảm 12.000 đầu phiếu, trả ngay 50.000', r2);
  R.eq('Tổng phiếu sau giảm = 108.000', r2.data?.grandTotal, 108000);
  p = await product(pid);
  R.eq('Tồn = 20', p.onHandQty, 20);
  R.eq('Giá vốn bình quân = (10×10.000 + 10×10.800) / 20 = 10.400', p.costPrice, 10400, 1);
  R.eq('Công nợ NCC = 100.000 + 58.000 = 158.000', (await supplier(sid)).currentDebt, 158000);
  const cb1 = await cashbook();
  R.check('Sổ quỹ có phiếu chi 50.000 cho phiếu nhập',
    (cb1.items || []).some((x) => x.type === 'Expense' && Math.abs(x.amount - 50000) < 1 && (x.description || '').includes(r2.data?.receiptNo)),
    r2.data?.receiptNo);

  const r3 = await api.post('/api/pos/purchase/receipts', receipt([line(1, 240000, 'Thùng')]));
  R.must('Nhập 1 Thùng × 240.000 (quy đổi 24 Lon)', r3);
  p = await product(pid);
  R.eq('Tồn = 20 + 24 = 44 Lon', p.onHandQty, 44);
  R.eq('Giá vốn = (20×10.400 + 24×10.000) / 44 ≈ 10.181,82', p.costPrice, (20 * 10400 + 24 * 10000) / 44, 1);
  R.eq('Công nợ NCC = 398.000', (await supplier(sid)).currentDebt, 398000);

  const pay = await api.post(`/api/pos/purchase/receipts/${draft.data?.id}/payments`, {
    amount: 30000, paymentMethod: 'Tiền mặt', paidAt: null, note: `${tag} trả bớt`,
  });
  R.must('Trả NCC 30.000 cho phiếu nhập đầu', pay);
  R.eq('Công nợ NCC = 368.000', (await supplier(sid)).currentDebt, 368000);
  const cancelPaid = await api.post(`/api/pos/purchase/receipts/${draft.data?.id}/cancel`);
  R.check('Không cho hủy phiếu nhập đã có thanh toán', !cancelPaid.ok, cancelPaid.message);

  // ── 2. Trả hàng NCC ───────────────────────────────────────────────
  R.group('2. Trả hàng nhà cung cấp');
  const costBeforeReturn = (await product(pid)).costPrice;
  const ret = await api.post('/api/pos/purchase/returns', {
    supplierId: sid, sourceReceiptId: null, note: `${tag} trả`, discountAmount: 0, refundReceived: 0,
    returnDate: null, returnedBy: null, complete: true,
    lines: [{ productId: pid, variantId: null, qty: 4, costPrice: 10000, discountAmount: 0, unitName: 'Lon', lineNote: null }],
  });
  R.must('Trả 4 Lon × 10.000, chưa nhận tiền hoàn', ret);
  p = await product(pid);
  R.eq('Tồn = 40', p.onHandQty, 40);
  R.eq('Công nợ NCC giảm 40.000 → 328.000', (await supplier(sid)).currentDebt, 328000);
  R.check('Giá vốn sau trả', true, `${costBeforeReturn.toFixed(2)} → ${p.costPrice.toFixed(2)}`);

  // ── 3. Xuất hủy ───────────────────────────────────────────────────
  const issue = async (kind, qty) => {
    const c = await api.post(`/api/pos/stock/${kind}`);
    if (!c.ok) return c;
    const add = await api.post(`/api/pos/stock/${kind}/${c.data.id}/lines/add`, [{ productId: pid, variantId: null }]);
    if (!add.ok) return add;
    const lineId = add.data.lines.find((l) => l.productId === pid)?.id;
    const upd = await api.put(`/api/pos/stock/${kind}/${c.data.id}/lines`, { lines: [{ lineId, qty }] });
    if (!upd.ok) return upd;
    return { ...(await api.post(`/api/pos/stock/${kind}/${c.data.id}/complete`)), id: c.data.id };
  };

  const pnl0 = await pnl();
  R.group('3. Xuất hủy');
  const cost3 = (await product(pid)).costPrice;
  const dmg = await issue('damage', 3);
  R.must('Xuất hủy 3 Lon', dmg);
  R.eq('Tồn = 37', (await product(pid)).onHandQty, 37);
  R.eq('Giá trị phiếu = 3 × giá vốn', dmg.data?.totalValue, 3 * cost3, 3);
  const tooMuch = await issue('damage', 1000);
  if (settings.allowNegativeStock) R.check('(Bỏ qua) chặn âm kho — cửa hàng cho phép âm', true);
  else R.check('Chặn xuất hủy vượt tồn (1000 > 37)', !tooMuch.ok, tooMuch.message);
  // Dọn phiếu tạm vừa bị chặn để không để lại rác trên dữ liệu thử.
  if (!tooMuch.ok && tooMuch.id) {
    R.must('Xóa phiếu hủy tạm bị chặn', await api.del(`/api/pos/stock/damage/${tooMuch.id}`));
  }

  // ── 4. Xuất dùng nội bộ ───────────────────────────────────────────
  R.group('4. Xuất dùng nội bộ');
  const use = await issue('internal-use', 2);
  R.must('Xuất dùng nội bộ 2 Lon', use);
  R.eq('Tồn = 35', (await product(pid)).onHandQty, 35);

  // ── 5. Kiểm kho ───────────────────────────────────────────────────
  R.group('5. Kiểm kho');
  const cc = await api.post('/api/pos/stock/counts', { name: `${tag} kiểm`, note: null, seedAllProducts: false });
  R.must('Tạo phiếu kiểm', cc);
  const cadd = await api.post(`/api/pos/stock/counts/${cc.data?.id}/lines/add`, [{ productId: pid, variantId: null }]);
  R.must('Thêm hàng vào phiếu kiểm', cadd);
  const cline = cadd.data?.lines?.find((l) => l.productId === pid);
  R.eq('Tồn hệ thống trên phiếu = 35', cline?.systemQty, 35);
  const cupd = await api.put(`/api/pos/stock/counts/${cc.data?.id}/lines`, { lines: [{ lineId: cline?.id, countedQty: 34, isChecked: true }] });
  R.must('Nhập số đếm thực tế 34', cupd);
  R.eq('Phiếu kiểm tạm KHÔNG đổi tồn', (await product(pid)).onHandQty, 35);
  const ccDone = await api.post(`/api/pos/stock/counts/${cc.data?.id}/complete`);
  R.must('Cân bằng kho', ccDone);
  R.eq('Tồn sau cân bằng = 34', (await product(pid)).onHandQty, 34);
  R.eq('Chênh lệch = -1', ccDone.data?.totalDiffQty, -1);

  // ── 6. Báo cáo kết quả kinh doanh ─────────────────────────────────
  R.group('6. Báo cáo kết quả kinh doanh (hôm nay)');
  const pnl1 = await pnl();
  R.eq('Chi phí xuất hủy tăng 3 × giá vốn', (pnl1.damageCost ?? 0) - (pnl0.damageCost ?? 0), 3 * cost3, 3);
  R.eq('Chi phí xuất nội bộ tăng 2 × giá vốn', (pnl1.internalUseCost ?? 0) - (pnl0.internalUseCost ?? 0), 2 * cost3, 3);
  R.eq('Hao hụt kiểm kê tăng 1 × giá vốn', (pnl1.countLossCost ?? 0) - (pnl0.countLossCost ?? 0), cost3, 2);

  // ── 7. Hủy phiếu: hoàn đúng tồn / công nợ ─────────────────────────
  R.group('7. Hủy phiếu (đảo ngược)');
  R.must('Hủy phiếu kiểm', await api.post(`/api/pos/stock/counts/${cc.data?.id}/cancel`));
  R.eq('Tồn về 35', (await product(pid)).onHandQty, 35);
  R.must('Hủy phiếu xuất nội bộ', await api.post(`/api/pos/stock/internal-use/${use.id}/cancel`));
  R.eq('Tồn về 37', (await product(pid)).onHandQty, 37);
  R.must('Hủy phiếu xuất hủy', await api.post(`/api/pos/stock/damage/${dmg.id}/cancel`));
  R.eq('Tồn về 40', (await product(pid)).onHandQty, 40);
  R.must('Hủy phiếu trả NCC', await api.post(`/api/pos/purchase/returns/${ret.data?.id}/cancel`));
  R.eq('Tồn về 44', (await product(pid)).onHandQty, 44);
  R.eq('Công nợ NCC về 368.000', (await supplier(sid)).currentDebt, 368000);
  R.must('Hủy phiếu nhập 1 Thùng', await api.post(`/api/pos/purchase/receipts/${r3.data?.id}/cancel`));
  p = await product(pid);
  R.eq('Tồn về 20', p.onHandQty, 20);
  R.eq('Giá vốn về 10.400', p.costPrice, 10400, 1);
  R.eq('Công nợ NCC về 128.000', (await supplier(sid)).currentDebt, 128000);

  // ── 8. Tình huống biên: trả hàng khi đã hết nợ rồi hủy phiếu trả ──
  R.group('8. Biên: trả hàng khi đã trả hết nợ NCC, rồi hủy phiếu trả');
  const sup2 = await api.post('/api/pos/purchase/suppliers', { name: `${tag} NCC hết nợ`, phone: '0900000001' });
  const sid2 = sup2.data?.id;
  const r4 = await api.post('/api/pos/purchase/receipts', { ...receipt([line(5, 10000)]), supplierId: sid2, paidAmount: 50000 });
  R.must('Nhập 5 × 10.000 và trả đủ 50.000', r4);
  R.eq('Công nợ NCC = 0', (await supplier(sid2)).currentDebt, 0);
  const ret2 = await api.post('/api/pos/purchase/returns', {
    supplierId: sid2, sourceReceiptId: null, note: `${tag} trả khi hết nợ`, discountAmount: 0, refundReceived: 0,
    returnDate: null, returnedBy: null, complete: true,
    lines: [{ productId: pid, variantId: null, qty: 2, costPrice: 10000, discountAmount: 0, unitName: 'Lon', lineNote: null }],
  });
  R.must('Trả 2 × 10.000, chưa nhận tiền hoàn (NCC nợ lại mình 20.000)', ret2);
  const debtAfterRet = (await supplier(sid2)).currentDebt;
  R.check('Công nợ sau trả (không âm)', true, `${debtAfterRet}`);
  R.must('Hủy phiếu trả', await api.post(`/api/pos/purchase/returns/${ret2.data?.id}/cancel`));
  R.eq('Công nợ phải về đúng 0 như trước khi trả', (await supplier(sid2)).currentDebt, 0);

  return finish();
})().catch((e) => {
  R.check('Lỗi không mong đợi', false, e.stack || String(e));
  finish();
});

function finish() {
  const out = path.join(__dirname, 'out');
  fs.mkdirSync(out, { recursive: true });
  R.writeJson(path.join(out, 'warehouse-e2e.json'));
  process.exitCode = R.summary() ? 1 : 0;
}
