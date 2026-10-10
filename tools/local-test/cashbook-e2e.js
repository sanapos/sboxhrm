#!/usr/bin/env node
// Kiểm thử sổ quỹ / thu chi trên API LOCAL:
//   phiếu thu tự sinh khi bán (đúng quỹ theo phương thức: Tiền mặt / Tingee / tiền vào tài khoản ngân hàng),
//   số dư quỹ, tồn đầu – cuối kỳ của báo cáo Sổ quỹ POS, hủy đơn hoàn phiếu thu, chặn xóa phiếu tự động.
//
//   node cashbook-e2e.js            (cần API local đang chạy — xem README.md)
'use strict';
const path = require('path');
const fs = require('fs');
const { API, login, client, Report, todayVn } = require('./lib/api');

if (!/localhost|127\.0\.0\.1/.test(API) && process.env.SBOX_ALLOW_REMOTE !== '1') {
  console.error(`Từ chối chạy vào ${API} — chỉ dành cho API local (đặt SBOX_ALLOW_REMOTE=1 nếu thật sự cần).`);
  process.exit(2);
}

const R = new Report('Kiểm thử sổ quỹ (local)');
const tag = 'SQ' + new Date().toISOString().replace(/\D/g, '').slice(4, 12);

(async () => {
  const { token } = await login();
  const api = client(token);
  const day = todayVn();
  const tomorrow = new Date(Date.parse(day) + 86400e3).toISOString().slice(0, 10);

  const cashbook = async (from = day, to = day) =>
    (await api.get(`/api/pos/reports/cashbook/summary?from=${from}&to=${to}`)).data || {};
  const funds = async () => (await api.get('/api/CashTransactions/fund-balances')).data || [];
  const fund = (list, pred) => (list.find(pred) || { balance: 0 }).balance;
  const cashFund = (l) => fund(l, (f) => f.isCash);
  const unassigned = (l) => fund(l, (f) => !f.isCash && !f.bankAccountId);
  const bankFund = (l, id) => fund(l, (f) => f.bankAccountId === id);

  // ── Chuẩn bị ───────────────────────────────────────────────────────
  R.group('Chuẩn bị dữ liệu');
  const pRes = await api.post('/api/pos/products', {
    name: `${tag} Dịch vụ thử`, productType: 0, costPrice: 0, basePrice: 10000, onHandQty: 100,
    baseUnitName: 'Lần', isDirectSale: true, vatRate: 0,
  });
  R.must('Tạo hàng hóa thử', pRes);
  const pid = pRes.data?.id;
  let banks = (await api.get('/api/BankAccounts')).data || [];
  if (!banks.length) {
    const b = await api.post('/api/BankAccounts', {
      accountName: `${tag} TK thử`, accountNumber: '0000' + tag.slice(-6), bankCode: 'VCB',
      bankName: 'Vietcombank', bankShortName: 'VCB',
    });
    R.must('Tạo tài khoản ngân hàng thử', b);
    banks = (await api.get('/api/BankAccounts')).data || [];
  }
  const bankId = banks[0]?.id;
  R.check('Có tài khoản ngân hàng để test', !!bankId);
  if (!pid || !bankId) return finish();

  const sale = (amount, payments) => api.post('/api/pos/sales', {
    lines: [{ productId: pid, qty: amount / 10000, unitPrice: 10000 }],
    discount: 0, paidAmount: amount, paymentMethod: payments[0].paymentMethod,
    customerName: null, customerId: null, note: tag, complete: true, payments,
  });
  const vouchersOf = (cb, orderNo) => (cb.items || []).filter((i) => (i.description || '').includes(orderNo));

  const f0 = await funds();
  const cb0 = await cashbook();

  // ── 1. Phiếu thu theo phương thức ─────────────────────────────────
  R.group('1. Phiếu thu tự sinh đúng quỹ');
  const sTingee = await sale(10000, [{ amount: 10000, paymentMethod: 'Tingee' }]);
  R.must('Bán 10.000 qua Tingee', sTingee);
  const sBank = await sale(20000, [{ amount: 20000, paymentMethod: 'Tiền mặt', bankAccountId: bankId }]);
  R.must('Bán 20.000 «Tiền mặt» nhưng gắn tài khoản ngân hàng', sBank);
  const sCash = await sale(30000, [{ amount: 30000, paymentMethod: 'Tiền mặt' }]);
  R.must('Bán 30.000 tiền mặt', sCash);

  const cb1 = await cashbook();
  R.eq('Phiếu Tingee ghi «Chuyển khoản»', vouchersOf(cb1, sTingee.data?.orderNo)[0]?.paymentMethod, 'BankTransfer');
  R.eq('Phiếu gắn tài khoản ghi «Chuyển khoản»', vouchersOf(cb1, sBank.data?.orderNo)[0]?.paymentMethod, 'BankTransfer');
  R.eq('Phiếu tiền mặt ghi «Tiền mặt»', vouchersOf(cb1, sCash.data?.orderNo)[0]?.paymentMethod, 'Cash');

  const f1 = await funds();
  R.eq('Quỹ tiền mặt +30.000 (không cộng Tingee / tiền vào TK)', cashFund(f1) - cashFund(f0), 30000);
  R.eq('Quỹ tài khoản ngân hàng +20.000', bankFund(f1, bankId) - bankFund(f0, bankId), 20000);
  R.eq('Quỹ «chưa gán tài khoản» +10.000 (Tingee)', unassigned(f1) - unassigned(f0), 10000);

  // ── 2. Báo cáo Sổ quỹ POS ─────────────────────────────────────────
  R.group('2. Báo cáo Sổ quỹ: tồn đầu – cuối kỳ');
  R.eq('Tổng thu hôm nay +60.000', (cb1.income || 0) - (cb0.income || 0), 60000);
  R.check('Có tồn đầu kỳ / cuối kỳ', cb1.openingBalance !== undefined && cb1.closingBalance !== undefined);
  R.eq('Cuối kỳ = đầu kỳ + thu − chi', cb1.closingBalance, cb1.openingBalance + cb1.income - cb1.expense);
  const cbNext = await cashbook(tomorrow, tomorrow);
  R.eq('Tồn đầu ngày mai = tồn cuối hôm nay', cbNext.openingBalance, cb1.closingBalance);
  const sumDay = (cb1.byDay || []).reduce((a, d) => [a[0] + d.income, a[1] + d.expense], [0, 0]);
  R.eq('Thu theo ngày cộng lại = tổng thu', sumDay[0], cb1.income);
  R.eq('Chi theo ngày cộng lại = tổng chi', sumDay[1], cb1.expense);
  const sumMethod = (cb1.byMethod || []).filter((m) => m.type === 'Income').reduce((a, m) => a + m.total, 0);
  R.eq('Thu theo phương thức cộng lại = tổng thu', sumMethod, cb1.income);

  // ── 3. Phiếu tự động: chặn xóa, hủy đơn hoàn phiếu ────────────────
  R.group('3. Phiếu tự động & hủy đơn');
  const vCash = vouchersOf(cb1, sCash.data?.orderNo)[0];
  const del = await api.del(`/api/CashTransactions/${vCash?.id}`);
  R.check('Không xóa được phiếu thu tự sinh từ đơn bán (409)', del.status === 409, `HTTP ${del.status}`);
  const cancel = await api.post(`/api/pos/sales/${sCash.data?.id}/cancel`, { reason: `${tag} test` });
  R.must('Hủy đơn tiền mặt 30.000', cancel);
  const cb2 = await cashbook();
  R.eq('Thu hôm nay giảm 30.000 sau hủy', cb1.income - cb2.income, 30000);
  R.check('Phiếu thu của đơn hủy không còn trong sổ', vouchersOf(cb2, sCash.data?.orderNo).length === 0);
  const f2 = await funds();
  R.eq('Quỹ tiền mặt về như trước khi bán', cashFund(f2), cashFund(f0));

  finish();
})().catch((e) => {
  R.check('Lỗi không mong đợi', false, e.stack || String(e));
  finish();
});

function finish() {
  const out = path.join(__dirname, 'out');
  fs.mkdirSync(out, { recursive: true });
  R.writeJson(path.join(out, 'cashbook-e2e.json'));
  process.exitCode = R.summary() ? 1 : 0;
}
