// Giờ cắt ngày qua đêm (ReportDayStartHour) — tạo đơn sát mốc giờ, so chênh lệch trước/sau trên từng báo cáo POS.
// Chạy: SBOX_TOKEN=<JWT cửa hàng test> [SBOX_API=http://localhost:7099] node scripts/e2e-pos-daycut.js [giờ_cắt=4]
// Chỉ chạy trên DB test — tạo đơn ngày 19–21/09/2026, tạm bật «sửa giờ bán» rồi trả thiết lập cũ.
const t = process.env.SBOX_TOKEN;
if (!t) { console.error('Thiếu SBOX_TOKEN'); process.exit(1); }
const B = process.env.SBOX_API || 'http://localhost:7099', H = { Authorization: 'Bearer ' + t, 'Content-Type': 'application/json' };
const CUT = Number(process.argv[2] ?? 4);
const tag = 'DC' + Date.now().toString().slice(-5);
let pass = 0, fail = 0;
async function call(m, p, b, soft) {
  const r = await fetch(B + p, { method: m, headers: H, body: b === undefined ? undefined : JSON.stringify(b) });
  const x = await r.text(); let j; try { j = JSON.parse(x); } catch { j = { raw: x }; }
  if (!r.ok || j.isSuccess === false) { const e = `${m} ${p} → ${r.status} ${j.message || x.slice(0, 200)}`; if (soft) return { __err: e }; throw new Error(e); }
  return j.data;
}
const ok = (n, a, e) => { const g = Math.abs((a ?? NaN) - e) < 0.5; g ? pass++ : fail++; console.log(`  ${g ? '✅' : '❌'} ${n}: ${a} (mong đợi ${e})`); };
const vn = (mo, d, h, mi = 0) => new Date(Date.UTC(2026, mo - 1, d, h - 7, mi)).toISOString();
const day = '2026-09-20', prev = '2026-09-19', next = '2026-09-21';
const q = (f) => `from=${f}&to=${f}`;
const sumDay = (arr, d, f = 'total') => (arr || []).filter(x => String(x.date).startsWith(d)).reduce((a, x) => a + (x[f] || 0), 0);

async function snap(d) {
  const s = await call('GET', `/api/pos/reports/sales/summary?${q(d)}`);
  const eod = await call('GET', `/api/pos/reports/end-of-day?${q(d)}`);
  const ov = await call('GET', `/api/pos/reports/analysis/overview?${q(d)}`);
  const pnl = await call('GET', `/api/pos/reports/pnl/summary?${q(d)}`);
  const cb = await call('GET', `/api/pos/reports/cashbook/summary?${q(d)}`);
  const so = await call('GET', `/api/pos/reports/sales/orders?${q(d)}&pageSize=500`);
  const list = await call('GET', `/api/pos/sales?${q(d)}&statuses=Completed&pageSize=500`);
  const shifts = await call('GET', `/api/pos/cashier-shifts?${q(d)}`, undefined, true);
  return {
    revenue: s.totalRevenue, orders: s.orderCount,
    byDay: sumDay(s.byDay, d), byDayAll: (s.byDay || []).reduce((a, x) => a + x.total, 0),
    profitByDay: sumDay(s.profitByDay, d, 'revenue'),
    hours: s.byHour, eod: eod.netSales, drawer: eod.drawerCash, ov: ov.current?.revenue, pnl: pnl.netRevenue ?? pnl.revenue,
    cash: cb.income, rptOrders: (so.items || so.rows || []).length, listOrders: (list.items || []).length,
    shifts: shifts.__err ? null : (shifts.items || shifts).length,
  };
}

(async () => {
  const st0 = await call('GET', '/api/pos/sell-settings');
  let extra = {}; try { extra = JSON.parse(st0.extraJson || '{}'); } catch { }
  try {
    await call('PUT', '/api/pos/sell-settings', { ...st0, reportDayStartHour: CUT, extraJson: JSON.stringify({ ...extra, allowEditSaleTime: true }) });
    const before = { [prev]: await snap(prev), [day]: await snap(day), [next]: await snap(next) };
    const p = await call('POST', '/api/pos/products/quick', { name: `Bia tươi ${tag}`, basePrice: 10000, costPrice: 4000, onHandQty: 0, baseUnitName: 'Ly', productType: 1, vatRate: 0, vatExempt: true });
    // [số ly, giờ VN, ngày KD mong đợi với giờ cắt CUT]
    const biz = (d, h) => (h < CUT ? (d === 20 ? prev : day) : (d === 20 ? day : next));
    const plan = [[1, 20, 3, 30], [2, 20, 4, 30], [3, 20, 23, 30], [4, 21, 2, 0], [5, 21, 4, 10]];
    for (const [qty, d, h, mi] of plan)
      await call('POST', '/api/pos/sales', {
        lines: [{ productId: p.id, qty, unitPrice: 10000 }], discount: 0, paymentMethod: 'Tiền mặt', complete: true,
        paidAmount: qty * 10000, saleDate: vn(9, d, h, mi), note: tag, clientRequestId: tag + Math.random().toString(36).slice(2),
      });
    const exp = { [prev]: { m: 0, n: 0 }, [day]: { m: 0, n: 0 }, [next]: { m: 0, n: 0 } };
    for (const [qty, d, h] of plan) { const k = biz(d, h); exp[k].m += qty * 10000; exp[k].n++; }
    console.log(`Giờ cắt ${CUT}h: đơn 03:30·04:30·23:30 ngày 20, 02:00·04:10 ngày 21 → mong đợi`, JSON.stringify(exp));
    for (const d of [prev, day, next]) {
      const a = await snap(d), b = before[d], e = exp[d];
      console.log(`\n Ngày KD ${d}`);
      ok('Doanh thu (báo cáo bán hàng)', a.revenue - b.revenue, e.m);
      ok('Số đơn', a.orders - b.orders, e.n);
      ok('Biểu đồ doanh thu theo ngày — cột đúng ngày', a.byDay - b.byDay, e.m);
      ok('Biểu đồ theo ngày — không rơi sang cột ngày khác', (a.byDayAll - b.byDayAll) - (a.byDay - b.byDay), 0);
      ok('Biểu đồ lãi theo ngày', a.profitByDay - b.profitByDay, e.m);
      ok('Cuối ngày — doanh thu', a.eod - b.eod, e.m);
      ok('Cuối ngày — tiền mặt két', a.drawer - b.drawer, e.m);
      ok('Phân tích tổng quan', a.ov - b.ov, e.m);
      ok('Lãi lỗ', a.pnl - b.pnl, e.m);
      ok('Sổ quỹ POS — thu', a.cash - b.cash, e.m);
      ok('Danh sách đơn (báo cáo)', a.rptOrders - b.rptOrders, e.n);
      ok('Màn Đơn hàng — lọc theo ngày', a.listOrders - b.listOrders, e.n);
      if (d === day && a.hours) console.log('   theo giờ (ngày 20):', JSON.stringify(a.hours.filter(x => x.total).map(x => [x.hour, x.total])));
    }
  } catch (e) { fail++; console.error('LỖI', e.message); }
  finally {
    await call('PUT', '/api/pos/sell-settings', st0);
    console.log(`\n== ${pass} đạt, ${fail} lỗi`);
  }
})();
