// Test nghiệp vụ theo ngành: karaoke/bi-a (tính giờ), khách sạn (theo ngày), spa (liệu trình + hoa hồng mỗi buổi),
// salon (hoa hồng dịch vụ, bắt buộc chọn NV), gym (thẻ buổi / thẻ tháng, check-in), nhà hàng (mở bàn → gửi bếp → thanh toán).
// Chạy: SBOX_TOKEN=<JWT cửa hàng test> SBOX_API=http://localhost:7099 node scripts/e2e-pos-industries.js
// Chỉ chạy trên DB test — script tạm bật tính giờ / gói buổi / hoa hồng rồi trả thiết lập cũ, và tạo dữ liệu thử.
const t = process.env.SBOX_TOKEN;
if (!t) { console.error('Thiếu SBOX_TOKEN'); process.exit(1); }
const B = process.env.SBOX_API || 'http://localhost:7099', H = { Authorization: 'Bearer ' + t, 'Content-Type': 'application/json' };
const tag = 'IN' + Date.now().toString().slice(-5);
const today = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
let pass = 0, fail = 0;
const cleanup = { areas: [], resources: [] };
async function call(m, p, b, soft) {
  const r = await fetch(B + p, { method: m, headers: H, body: b === undefined ? undefined : JSON.stringify(b) });
  const x = await r.text(); let j; try { j = JSON.parse(x); } catch { j = { raw: x }; }
  if (!r.ok || j.isSuccess === false) {
    const msg = `${m} ${p} → ${r.status} ${j.message || x.slice(0, 300)}`;
    if (soft) return { __err: msg };
    throw new Error(msg);
  }
  return j.data;
}
const ok = (n, a, e) => { const g = Math.abs((a ?? NaN) - e) < 0.5; g ? pass++ : fail++; console.log(`  ${g ? '✅' : '❌'} ${n}: ${a} (mong đợi ${e})`); };
const yes = (n, c, extra = '') => { c ? pass++ : fail++; console.log(`  ${c ? '✅' : '❌'} ${n}${extra ? ' — ' + extra : ''}`); };
const ago = min => new Date(Date.now() - min * 60e3).toISOString();
const now = () => new Date().toISOString();

async function product(name, price, extra) {
  const q = await call('POST', '/api/pos/products/quick', { name: `${name} ${tag}`, basePrice: price, costPrice: 0, onHandQty: 0, baseUnitName: extra.unit || 'Lần', productType: 1, vatRate: 0, vatExempt: true });
  const full = await call('GET', `/api/pos/products/${q.id}`);
  await call('PUT', `/api/pos/products/${q.id}`, { ...full, originalOnHandQty: full.onHandQty, ...extra.fields });
  return call('GET', `/api/pos/products/${q.id}`);
}
const sale = (lines, extra = {}) => call('POST', '/api/pos/sales', {
  lines, discount: 0, paymentMethod: 'Tiền mặt', complete: true, paidAmount: 0,
  clientRequestId: tag + Math.random().toString(36).slice(2), ...extra,
}, extra.__soft);

(async () => {
  const st0 = await call('GET', '/api/pos/sell-settings');
  console.log(`Cửa hàng: ngành ${st0.sellProfile} · giờ ${st0.enableHourlyBilling} · gói buổi ${st0.enableSessionPacks} · hoa hồng ${st0.enableStaffCommission}`);
  await call('PUT', '/api/pos/sell-settings', { ...st0, enableHourlyBilling: true, enableSessionPacks: true, enableStaffCommission: true, requireStaffOnService: false, enableResources: true });
  const sellers = await call('GET', '/api/pos/sales/sellers');
  const staff = (sellers.items || sellers).filter(s => s.employeeId || s.id);
  const emp = staff[0], emp2 = staff[1] || staff[0];
  const empId = e => e.employeeId || e.id;
  console.log('NV:', staff.slice(0, 3).map(s => s.name || s.fullName || s.displayName).join(', '));
  try {
    // ── 1. KARAOKE / BI-A: tính giờ ───────────────────────────────
    console.log('\n1) Karaoke / bi-a — tính giờ');
    const kara = await product('Phòng karaoke', 120000, { unit: 'Giờ', fields: { serviceBillingMode: 'PerHour', minBillMinutes: 60, billRoundMinutes: 15 } });
    yes('Lưu kiểu tính giờ', kara.serviceBillingMode === 'PerHour' && kara.minBillMinutes === 60 && kara.billRoundMinutes === 15, `${kara.serviceBillingMode} min ${kara.minBillMinutes} tròn ${kara.billRoundMinutes}`);
    let o = await sale([{ productId: kara.id, qty: 1, unitPrice: 120000, serviceStartedAt: ago(95), serviceEndedAt: now() }]);
    ok('Hát 95 phút → làm tròn 15p = 105p = 1,75 giờ', o.lines[0].qty, 1.75);
    ok('   tiền 1,75 × 120.000', o.total, 210000);
    o = await sale([{ productId: kara.id, qty: 1, unitPrice: 120000, serviceStartedAt: ago(20), serviceEndedAt: now() }]);
    ok('Hát 20 phút → tính tối thiểu 60p', o.total, 120000);
    o = await sale([{ productId: kara.id, qty: 1, unitPrice: 120000, serviceStartedAt: ago(119.5), serviceEndedAt: now(), servicePauseMinutes: 30 }]);
    ok('120 phút, tạm dừng 30p → tính 90p = 180.000', o.total, 180000);

    const bida = await product('Bàn bi-a', 50000, { unit: 'Block', fields: { serviceBillingMode: 'PerBlock', billRoundMinutes: 30, graceMinutes: 5, openingFee: 20000, openingMinutes: 60 } });
    o = await sale([{ productId: bida.id, qty: 1, unitPrice: 50000, serviceStartedAt: ago(4), serviceEndedAt: now() }]);
    ok('Bi-a 4 phút (miễn 5p) → chỉ phí mở bàn 20.000', o.total, 20000);
    o = await sale([{ productId: bida.id, qty: 1, unitPrice: 50000, serviceStartedAt: ago(75), serviceEndedAt: now() }]);
    // 75 − 5 miễn = 70 → tròn block 30 = 90; trừ 60p đã gồm phí mở = 30p = 1 block
    ok('Bi-a 75 phút → phí mở 20k (gồm 60p) + 1 block 50k', o.total, 70000);
    const pv = await call('POST', '/api/pos/service-billing/preview', { mode: 'PerHour', unitPrice: 120000, minBillMinutes: 60, billRoundMinutes: 15, elapsedMinutes: [10, 61, 95] }, true);
    yes('Bảng xem trước giá giờ (preview)', !pv.__err, pv.__err || JSON.stringify((pv.rows || pv).slice?.(0, 3)?.map(r => [r.elapsedMinutes, r.total])));

    // Đơn karaoke lưu tạm rồi hoàn thành từ màn Đơn hàng (không gửi lại dòng) → phải tính giờ tới lúc thanh toán
    const dk = await sale([{ productId: kara.id, qty: 1, unitPrice: 120000, serviceStartedAt: ago(95) }], { complete: false, paidAmount: 0 });
    const dkDone = await call('POST', `/api/pos/sales/${dk.id}/complete`, {}, true);
    if (dkDone.__err) yes('Hoàn thành đơn giờ từ màn Đơn hàng', false, dkDone.__err);
    else ok('Hoàn thành đơn giờ từ màn Đơn hàng → tính lại 95p = 210.000', dkDone.total, 210000);
    // Mở phòng thật: phiên → đơn nháp có dòng giờ → thanh toán ngay → tính tối thiểu 60p
    const area = await call('POST', '/api/pos/service-areas', { name: `Khu ${tag}`, code: tag, sortOrder: 99, areaType: 'Room', isActive: true });
    cleanup.areas.push(area.id);
    const room = await call('POST', '/api/pos/service-resources', { areaId: area.id, code: 'P' + tag.slice(-3), name: `Phòng ${tag}`, resourceKind: 'Room', capacity: 10, defaultServiceProductId: kara.id, isActive: true });
    cleanup.resources.push(room.id);
    const ses = await call('POST', '/api/pos/resource-sessions/open', { resourceId: room.id, guestCount: 4 });
    const draft = await call('GET', `/api/pos/sales/${ses.saleOrderId}`);
    yes('Mở phòng → tạo đơn nháp có dòng giờ', draft.lines.some(l => l.productId === kara.id), `${draft.orderNo}, ${draft.lines.length} dòng`);
    await call('POST', `/api/pos/resource-sessions/${ses.sessionId}/pause`, {}, true);
    const rs = await call('GET', '/api/pos/service-resources');
    const r1 = (rs.items || rs).find(x => x.id === room.id);
    yes('Tạm dừng giờ → phòng hiện trạng thái dừng', r1?.pausedAt != null, `occupancy ${r1?.occupancyStatus}`);
    await call('POST', `/api/pos/resource-sessions/${ses.sessionId}/resume`, {}, true);
    const done = await call('POST', `/api/pos/sales/${ses.saleOrderId}/complete`, { paidAmount: 120000, paymentMethod: 'Tiền mặt' }, true);
    if (done.__err) yes('Thanh toán phòng', false, done.__err);
    else {
      ok('Thanh toán phòng vừa mở → tối thiểu 60p = 120.000', done.total, 120000);
      const rs2 = await call('GET', '/api/pos/service-resources');
      const r2 = (rs2.items || rs2).find(x => x.id === room.id);
      yes('Phòng trống / chờ dọn sau thanh toán', !r2?.openSessionId, `occupancy ${r2?.occupancyStatus}`);
    }

    // ── 2. KHÁCH SẠN: theo ngày ────────────────────────────────────
    console.log('\n2) Khách sạn — theo ngày');
    const hotel = await product('Phòng đôi', 500000, { unit: 'Ngày', fields: { serviceBillingMode: 'PerDay' } });
    // Giờ VN = UTC+7. Chính sách mặc định: nhận 14:00, trả 12:00 (+30p ân hạn), trả muộn tới 18:00 = +½, nhận sớm từ 05:00 = +½.
    const vn = (d, h, m = 0) => new Date(Date.UTC(2026, 8, d, h - 7, m)).toISOString();
    const stays = [
      ['Nhận 14:00 → trả 11:00 hôm sau', vn(1, 14), vn(2, 11), 1],
      ['Nhận 14:00 → trả 12:20 (trong ân hạn)', vn(1, 14), vn(2, 12, 20), 1],
      ['Nhận 14:00 → trả muộn 15:00', vn(1, 14), vn(2, 15), 1.5],
      ['Nhận 14:00 → trả 19:00 (quá 18h)', vn(1, 14), vn(2, 19), 2],
      ['Nhận sớm 09:00 → trả 11:00 hôm sau', vn(1, 9), vn(2, 11), 1.5],
      ['Nhận 14:00 → ở 3 đêm trả 11:00', vn(1, 14), vn(4, 11), 3],
    ];
    for (const [label, st, en, exp] of stays) {
      o = await sale([{ productId: hotel.id, qty: 1, unitPrice: 500000, serviceStartedAt: st, serviceEndedAt: en }]);
      ok(`${label} → ${exp} đêm`, o.lines[0].qty, exp);
    }
    ok('   tiền 3 đêm × 500.000', o.total, 1500000);

    // ── 3. SPA: liệu trình nhiều buổi + hoa hồng mỗi buổi ──────────
    console.log('\n3) Spa — liệu trình + hoa hồng mỗi buổi');
    const cus = await call('POST', '/api/pos/customers', { name: `Khách spa ${tag}`, phone: '0955' + tag.slice(-6) });
    const pack = await product('Liệu trình trị mụn 10 buổi', 1000000, { unit: 'Gói', fields: { serviceBillingMode: 'PerSession', sessionPackCount: 10, sessionPackValidDays: 90, commissionMode: 'PercentOfLine', commissionPercent: 10, commissionPerSession: true } });
    yes('Lưu gói 10 buổi / 90 ngày / HH 10% mỗi buổi', pack.sessionPackCount === 10 && pack.sessionPackValidDays === 90 && pack.commissionPerSession, `${pack.sessionPackCount} buổi, ${pack.sessionPackValidDays} ngày, HH ${pack.commissionMode} ${pack.commissionPercent}% mỗi buổi=${pack.commissionPerSession}`);
    const po = await sale([{ productId: pack.id, qty: 1, unitPrice: 1000000 }], { customerId: cus.id, customerName: cus.name, paidAmount: 1000000 });
    let bals = await call('GET', `/api/pos/session-balances?customerId=${cus.id}`);
    const bal = (bals.items || bals).find(b => b.productId === pack.id);
    ok('Bán gói → khách có 10 buổi', bal?.remainingSessions, 10);
    const days = bal?.expiresAt ? Math.round((new Date(bal.expiresAt) - Date.now()) / 864e5) : NaN;
    ok('Hạn dùng ≈ 90 ngày', days, 90);
    const comm0 = await call('GET', `/api/pos/reports/staff-commission?from=${today}&to=${today}&productId=${pack.id}`);
    const rows0 = comm0.rows || comm0.items || comm0.lines || [];
    ok('Lúc bán gói (HH mỗi buổi) chưa tính hoa hồng', rows0.reduce((s, r) => s + (r.commissionAmount || 0), 0), 0);
    const rd = await call('POST', '/api/pos/session-balances/redeem', { balanceId: bal.id, sessions: 1, employeeId: empId(emp), note: tag });
    bals = await call('GET', `/api/pos/session-balances?customerId=${cus.id}`);
    ok('Làm 1 buổi → còn 9', (bals.items || bals).find(b => b.id === bal.id)?.remainingSessions, 9);
    ok('Hoa hồng buổi: 1.000.000 / 10 × 10%', rd.commissionAmount, 10000);
    const comm1 = await call('GET', `/api/pos/reports/staff-commission?from=${today}&to=${today}&productId=${pack.id}`);
    const rows1 = comm1.rows || comm1.items || comm1.lines || [];
    ok('Báo cáo hoa hồng có buổi vừa làm', rows1.reduce((s, r) => s + (r.commissionAmount || 0), 0), 10000);
    const over = await call('POST', '/api/pos/session-balances/redeem', { balanceId: bal.id, sessions: 20, employeeId: empId(emp) }, true);
    yes('Trừ quá số buổi còn lại bị chặn', !!over.__err, over.__err?.split('→ ')[1]);

    // ── 4. SALON: hoa hồng dịch vụ + bắt buộc chọn NV ─────────────
    console.log('\n4) Salon — hoa hồng dịch vụ');
    const cut = await product('Cắt tóc nam', 100000, { fields: { commissionMode: 'PercentOfLine', commissionPercent: 20 } });
    const wash = await product('Gội đầu', 50000, { fields: { commissionMode: 'FixedPerUnit', commissionFixed: 15000 } });
    const so = await sale([
      { productId: cut.id, qty: 1, unitPrice: 100000, staffAssignments: [{ assignedEmployeeId: empId(emp), assignedEmployeeName: emp.name }] },
      { productId: wash.id, qty: 2, unitPrice: 50000, staffAssignments: [{ assignedEmployeeId: empId(emp2), assignedEmployeeName: emp2.name }] },
    ], { paidAmount: 200000 });
    const c2 = await call('GET', `/api/pos/reports/staff-commission?from=${today}&to=${today}`);
    const rowsAll = (c2.rows || c2.items || c2.lines || []).filter(r => r.orderNo === so.orderNo);
    ok('HH cắt tóc 20% × 100k', rowsAll.filter(r => r.productId === cut.id).reduce((s, r) => s + r.commissionAmount, 0), 20000);
    ok('HH gội 15k × 2 lần', rowsAll.filter(r => r.productId === wash.id).reduce((s, r) => s + r.commissionAmount, 0), 30000);
    // Giảm giá đơn → HH % tính trên doanh thu thực
    const sd = await sale([{ productId: cut.id, qty: 1, unitPrice: 100000, discountAmount: 20000, staffAssignments: [{ assignedEmployeeId: empId(emp) }] }], { paidAmount: 80000 });
    const c3 = await call('GET', `/api/pos/reports/staff-commission?from=${today}&to=${today}&productId=${cut.id}`);
    ok('Cắt tóc giảm 20k → HH 20% × 80k', (c3.rows || c3.items || c3.lines || []).filter(r => r.orderNo === sd.orderNo).reduce((s, r) => s + r.commissionAmount, 0), 16000);
    await call('PUT', '/api/pos/sell-settings', { ...st0, enableHourlyBilling: true, enableSessionPacks: true, enableStaffCommission: true, requireStaffOnService: true, enableResources: true });
    const noStaff = await sale([{ productId: cut.id, qty: 1, unitPrice: 100000 }], { paidAmount: 100000, __soft: true });
    yes('Bật «bắt buộc chọn NV» → bán dịch vụ không chọn NV bị chặn', !!noStaff.__err, noStaff.__err?.split('→ ')[1]);
    await call('PUT', '/api/pos/sell-settings', { ...st0, enableHourlyBilling: true, enableSessionPacks: true, enableStaffCommission: true, requireStaffOnService: false, enableResources: true });
    // Trả hàng → HH có bị trừ?
    await call('POST', `/api/pos/sales/${so.id}/return`, { lines: [{ productId: cut.id, qty: 1 }], note: tag, refundPaymentMethod: 'Tiền mặt' });
    const c4 = await call('GET', `/api/pos/reports/staff-commission?from=${today}&to=${today}&productId=${cut.id}`);
    const c4rows = (c4.rows || c4.items || c4.lines || []);
    ok('Trả lại dịch vụ cắt tóc → HH đơn đó về 0', (c4.rows || c4.items || c4.lines || []).filter(r => r.orderNo === so.orderNo).reduce((s, r) => s + r.commissionAmount, 0), 0);

    const retNo = (await call('GET', `/api/pos/sales/${so.id}`)).returns?.[0]?.returnNo
      || (await call('GET', `/api/pos/sales/${so.id}/returns`, undefined, true))?.[0]?.returnNo;
    if (retNo) {
      await call('POST', `/api/pos/sales/${so.id}/returns/cancel`, { returnNo: retNo });
      const c5 = await call('GET', `/api/pos/reports/staff-commission?from=${today}&to=${today}&productId=${cut.id}`);
      ok('Hủy phiếu trả → HH cắt tóc hồi lại 20k', (c5.lines || []).filter(r => r.orderNo === so.orderNo).reduce((s, r) => s + r.commissionAmount, 0), 20000);
    } else yes('Tìm mã phiếu trả để hủy', false);
    void c4rows;

    // ── 5. GYM: thẻ buổi + thẻ tháng + check-in ─────────────────────
    console.log('\n5) Gym — thẻ buổi / thẻ tháng / check-in');
    const g1 = await call('POST', '/api/pos/customers', { name: `Hội viên ${tag}`, phone: '0966' + tag.slice(-6) });
    const card12 = await product('Thẻ 12 buổi', 600000, { unit: 'Thẻ', fields: { serviceBillingMode: 'PerSession', sessionPackCount: 12, sessionPackValidDays: 60 } });
    await sale([{ productId: card12.id, qty: 1, unitPrice: 600000 }], { customerId: g1.id, customerName: g1.name, paidAmount: 600000 });
    const ci = await call('POST', '/api/pos/gym/check-in', { customerId: g1.id }, true);
    yes('Check-in hội viên', !ci.__err, ci.__err || `${ci.packageName} · trừ buổi=${ci.sessionDeducted} · còn ${ci.remainingSessions}`);
    if (!ci.__err) ok('Check-in trừ 1 buổi → còn 11', ci.remainingSessions, 11);
    const ci2 = await call('POST', '/api/pos/gym/check-in', { customerId: g1.id }, true);
    yes('Check-in lặp ngay lập tức bị chặn (chống quẹt 2 lần)', !!ci2.__err, ci2.__err?.split('→ ')[1]);
    const g2 = await call('POST', '/api/pos/customers', { name: `Hội viên tháng ${tag}`, phone: '0977' + tag.slice(-6) });
    const month = await product('Thẻ tháng không giới hạn', 800000, { unit: 'Thẻ', fields: { serviceBillingMode: 'PerSession', sessionPackCount: 9999, sessionPackValidDays: 30 } });
    await sale([{ productId: month.id, qty: 1, unitPrice: 800000 }], { customerId: g2.id, customerName: g2.name, paidAmount: 800000 });
    const ci3 = await call('POST', '/api/pos/gym/check-in', { customerId: g2.id }, true);
    yes('Thẻ tháng check-in không trừ buổi', !ci3.__err && ci3.unlimited, ci3.__err || `unlimited=${ci3.unlimited}, hạn ${ci3.expiresAt?.slice(0, 10)}`);

    // ── 6. NHÀ HÀNG: mở bàn → món → gửi bếp → thanh toán ───────────
    console.log('\n6) Nhà hàng — mở bàn, gửi bếp, thanh toán');
    const food = await call('POST', '/api/pos/products/quick', { name: `Phở bò ${tag}`, basePrice: 55000, costPrice: 20000, onHandQty: 0, baseUnitName: 'Tô', productType: 1, vatRate: 0, vatExempt: true });
    const tarea = await call('POST', '/api/pos/service-areas', { name: `Tầng ${tag}`, code: 'T' + tag, sortOrder: 98, areaType: 'Table', isActive: true });
    cleanup.areas.push(tarea.id);
    const table = await call('POST', '/api/pos/service-resources', { areaId: tarea.id, code: 'B' + tag.slice(-3), name: `Bàn ${tag}`, resourceKind: 'Table', capacity: 4, isActive: true });
    cleanup.resources.push(table.id);
    const ts = await call('POST', '/api/pos/resource-sessions/open', { resourceId: table.id, guestCount: 3 });
    const d0 = await call('GET', `/api/pos/sales/${ts.saleOrderId}`);
    const upd = await call('PUT', `/api/pos/sales/${ts.saleOrderId}`, { lines: [{ productId: food.id, qty: 3, unitPrice: 55000 }], discount: 0, paidAmount: 0, paymentMethod: 'Tiền mặt', customerName: null, customerId: null, note: null, complete: false }, true);
    yes('Thêm món vào bàn', !upd.__err, upd.__err || `${upd.lines?.length} dòng, tạm tính ${upd.total}`);
    const ks = await call('POST', `/api/pos/resource-sessions/${ts.sessionId}/kitchen-send`, { requestId: tag }, true);
    yes('Gửi bếp', !ks.__err, ks.__err || JSON.stringify(ks).slice(0, 80));
    const tdone = await call('POST', `/api/pos/sales/${ts.saleOrderId}/complete`, {}, true);
    if (tdone.__err) yes('Thanh toán bàn', false, tdone.__err);
    else ok('Thanh toán bàn 3 tô × 55k', tdone.total, 165000);
    const rs3 = await call('GET', '/api/pos/service-resources');
    yes('Bàn được giải phóng sau thanh toán', !(rs3.items || rs3).find(x => x.id === table.id)?.openSessionId);
    void d0;
  } catch (e) {
    fail++; console.error('LỖI', e.message);
  } finally {
    for (const id of cleanup.resources) await call('DELETE', `/api/pos/service-resources/${id}`, undefined, true);
    for (const id of cleanup.areas) await call('DELETE', `/api/pos/service-areas/${id}`, undefined, true);
    await call('PUT', '/api/pos/sell-settings', st0);
    console.log(`\n== ${pass} đạt, ${fail} lỗi`);
  }
})();
