// In qua Print Agent: máy in cửa hàng, tuyến chứng từ, gán món → máy in, hàng đợi lệnh in giữa nhiều máy.
// Chạy: SBOX_TOKEN=<JWT cửa hàng test> [SBOX_API=http://localhost:7099] node scripts/e2e-pos-print.js
// Chỉ chạy trên DB test — tạo máy in / Agent / lệnh in thử rồi xóa máy in khi xong.
const t = process.env.SBOX_TOKEN;
if (!t) { console.error('Thiếu SBOX_TOKEN'); process.exit(1); }
const B = process.env.SBOX_API || 'http://localhost:7099', H = { Authorization: 'Bearer ' + t, 'Content-Type': 'application/json' };
const tag = 'PR' + Date.now().toString().slice(-5);
let pass = 0, fail = 0;
async function call(m, p, b, soft) {
  const r = await fetch(B + p, { method: m, headers: H, body: b === undefined ? undefined : JSON.stringify(b) });
  const x = await r.text(); let j; try { j = JSON.parse(x); } catch { j = { raw: x }; }
  if (!r.ok || j.isSuccess === false) { const e = `${m} ${p} → ${r.status} ${j.message || x.slice(0, 200)}`; if (soft) return { __err: e }; throw new Error(e); }
  return j.data;
}
const yes = (n, c, extra = '') => { c ? pass++ : fail++; console.log(`  ${c ? '✅' : '❌'} ${n}${extra ? ' — ' + extra : ''}`); };
const printer = (name, conn, extra = {}) => call('POST', '/api/pos/printers', {
  name: `${name} ${tag}`, connectionType: conn, printerBrand: 'Xprinter', paperSize: 'K80', textMode: null,
  bluetoothAddress: null, bluetoothName: null, lanHost: conn === 'Lan' ? (extra.ip || `10.${tag.slice(-5,-3)|0}.${tag.slice(-3)%250}.10`) : null, lanPort: 9100,
  usbDeviceName: conn === 'Usb' ? 'XP-80' : null, feedBeforeCut: 8, partialCut: true, isDefault: false, sortOrder: 90, isActive: true, ...extra, ip: undefined,
});
const job = (printerId, rid, docType = 'KitchenSlip') => call('POST', '/api/pos/print-jobs', {
  documentType: docType, payloadFormat: 'KitchenSlipJson',
  payload: JSON.stringify({ table: 'Bàn 5', rid, lines: [{ name: 'Phở bò ' + tag, qty: 2 }] }), copies: 1,
  referenceNo: 'HD-' + tag, referenceId: null, printerId, clientRequestId: rid,
}).then(d => ({ ...d, id: d.id || d.jobId }));
(async () => {
  const created = [];
  try {
    console.log('1) Máy in cửa hàng');
    const kitchen = await printer('Bếp', 'Lan'); created.push(kitchen.id);
    const bar = await printer('Quầy bar', 'Lan', { ip: `10.${tag.slice(-5,-3)|0}.${tag.slice(-3)%250}.11` }); created.push(bar.id);
    const label = await printer('Tem ly', 'Usb', { paperSize: '50x30' }); created.push(label.id);
    yes('Tạo máy in bếp / bar / tem', !!(kitchen.id && bar.id && label.id), `cần Agent: bếp=${kitchen.requiresAgent} tem=${label.requiresAgent}`);
    const dupRes = await (await fetch(B + '/api/pos/printers', { method: 'POST', headers: H, body: JSON.stringify({
      name: `Bếp 2 ${tag}`, connectionType: 'Lan', printerBrand: 'Xprinter', paperSize: 'K80', textMode: null, bluetoothAddress: null, bluetoothName: null,
      lanHost: `10.${tag.slice(-5,-3)|0}.${tag.slice(-3)%250}.10`, lanPort: 9100, usbDeviceName: null, feedBeforeCut: 8, partialCut: true, isDefault: false, sortOrder: 91, isActive: true }) })).json();
    yes('Tạo máy trùng IP với «Bếp» → cập nhật máy cũ + báo rõ', dupRes.data?.id === kitchen.id && /Trùng địa chỉ/.test(dupRes.message || ''), dupRes.message);
    await call('PUT', `/api/pos/printers/${kitchen.id}`, { ...dupRes.data, name: `Bếp ${tag}`, connectionType: 'Lan' }, true);

    console.log('2) Agent đăng ký (máy A phục vụ bếp + tem, máy B phục vụ bếp)');
    const a = await call('POST', '/api/pos/print-jobs/agents/register', { deviceId: 'dev-A-' + tag, deviceName: 'Máy thu ngân A', employeeName: 'Test', printerIds: [kitchen.id, label.id], appVersion: 'test' });
    const b = await call('POST', '/api/pos/print-jobs/agents/register', { deviceId: 'dev-B-' + tag, deviceName: 'Máy bếp B', employeeName: 'Test', printerIds: [kitchen.id], appVersion: 'test' });
    yes('2 Agent đăng ký', !!(a.agentId && b.agentId));
    const agents = await call('GET', '/api/pos/print-jobs/agents');
    console.log('     xung đột máy in:', agents.hasPrinterConflict, 'nhiều agent:', agents.multiAgent, 'online:', agents.onlineCount);
    const mine = (agents.agents || []).filter(x => String(x.deviceId || '').includes(tag));
    yes('Danh sách Agent hiện 2 máy online', mine.length === 2 && mine.every(x => x.isOnline !== false), JSON.stringify(mine.map(x => [x.deviceName, x.isOnline, (x.printerIds || x.assignedPrinterIds || []).length])));

    console.log('3) Máy bán gửi lệnh in bếp');
    const j1 = await job(kitchen.id, 'rid-1-' + tag);
    const j1b = await job(kitchen.id, 'rid-1-' + tag);
    yes('Gửi lại cùng mã chống trùng → đúng lệnh cũ (không in 2 lần)', j1.id === j1b.id, j1.status);
    const c1 = await call('POST', `/api/pos/print-jobs/agents/${a.agentId}/claim`, {});
    const c2 = await call('POST', `/api/pos/print-jobs/agents/${b.agentId}/claim`, {});
    const got = [c1, c2].filter(x => x && x.jobId);
    yes('Hai Agent cùng nhận → chỉ 1 máy nhận được lệnh', got.length === 1, `A=${!!(c1 && c1.jobId)} B=${!!(c2 && c2.jobId)}`);
    const winner = c1 && c1.jobId ? a.agentId : b.agentId;
    const jid = (c1?.jobId || c2?.jobId);
    await call('POST', `/api/pos/print-jobs/${jid}/printing?agentId=${winner}`, {});
    await call('POST', `/api/pos/print-jobs/${jid}/complete?agentId=${winner}`, {});
    const s1 = await call('GET', `/api/pos/print-jobs/${jid}`);
    yes('Máy gửi thấy lệnh «Đã in»', /Completed/.test(s1.status), `${s1.status} bởi agent ${s1.agentId === winner ? 'đúng' : s1.agentId}`);

    console.log('4) Agent nhận nhầm (USB chưa cắm) → nhả lệnh cho máy khác');
    const j2 = await job(kitchen.id, 'rid-2-' + tag);
    const ca = await call('POST', `/api/pos/print-jobs/agents/${a.agentId}/claim`, {}, true);
    const caAlt = ca;
    const rel = await call('POST', `/api/pos/print-jobs/${j2.id}/release?agentId=${a.agentId}`, { errorCode: 'USB_MISSING', errorMessage: 'USB chưa cắm' }, true);
    const s2 = await call('GET', `/api/pos/print-jobs/${j2.id}`);
    yes('Nhả lệnh → về «Chờ in»', /Queued/.test(s2.status), rel.__err || s2.status);
    const cb2 = await call('POST', `/api/pos/print-jobs/agents/${b.agentId}/claim`, {});
    yes('Máy B nhận lại lệnh đã nhả', cb2?.jobId === j2.id);
    void caAlt;

    console.log('5) Lỗi in');
    await call('POST', `/api/pos/print-jobs/${j2.id}/fail?agentId=${b.agentId}`, { errorCode: 'PAPER_OUT', errorMessage: 'Hết giấy' });
    const s3 = await call('GET', `/api/pos/print-jobs/${j2.id}`);
    yes('Lệnh lỗi hiện «Lỗi · Hết giấy»', /Failed/.test(s3.status) && /giấy/.test(s3.errorMessage || ''), `${s3.status} ${s3.errorMessage}`);
    const pr = await call('GET', `/api/pos/printers/${kitchen.id}`);
    console.log(`     trạng thái máy in bếp sau lỗi: ${pr.healthStatus} ${pr.lastErrorMessage || ''}`);

    console.log('6) Máy in không có Agent nào phục vụ (quầy bar) → lệnh treo');
    const j3 = await job(bar.id, 'rid-3-' + tag);
    const ca3 = await call('POST', `/api/pos/print-jobs/agents/${a.agentId}/claim`, {});
    yes('Agent không phục vụ máy bar không nhận lệnh bar', !(ca3 && (ca3.jobId === j3.id)));
    const list = await call('GET', `/api/pos/print-jobs?status=Queued&pageSize=50`, undefined, true);
    const items = list.__err ? [] : (list.items || list);
    yes('Danh sách lệnh chờ in có lệnh bar (để hiện «phiếu treo»)', items.some(x => x.id === j3.id), list.__err || `${items.length} lệnh chờ`);

    console.log('6b) Hàng đợi in toàn cửa hàng');
    const qd = await call('GET', '/api/pos/print-jobs/queue');
    const qBar = qd.items.find(x => x.id === j3.id);
    yes('Hàng đợi thấy lệnh bar gửi từ máy khác, báo «Không có Agent»', qBar?.problem === 'no_agent', `${qBar?.problem} · ${qBar?.printerName}`);
    const qFail = qd.items.find(x => x.id === j2.id);
    yes('Hàng đợi thấy lệnh lỗi «Hết giấy»', qFail?.problem === 'failed');
    const pBar = qd.printers.find(p => p.id === bar.id);
    yes('Tình trạng máy bar: chưa có Agent, 1 lệnh cần xử lý', pBar && pBar.agents.length === 0 && pBar.problems >= 1, JSON.stringify(pBar && { agents: pBar.agents, problems: pBar.problems, waiting: pBar.waiting }));
    const mv = await call('POST', `/api/pos/print-jobs/${j3.id}/retry`, { printerId: kitchen.id });
    yes('Chuyển lệnh bar sang máy bếp (có Agent)', mv.printerId === kitchen.id && mv.status === 'Queued');
    const cmv = await call('POST', `/api/pos/print-jobs/agents/${b.agentId}/claim`, {});
    yes('Agent bếp nhận lệnh vừa chuyển', cmv?.jobId === j3.id);
    if (cmv?.jobId) await call('POST', `/api/pos/print-jobs/${cmv.jobId}/complete?agentId=${b.agentId}`, {});
    const rf = await call('POST', `/api/pos/print-jobs/${j2.id}/retry`, {});
    yes('In lại lệnh lỗi → về «Chờ in»', rf.status === 'Queued');
    const cc = await call('POST', `/api/pos/print-jobs/${j2.id}/cancel`, {});
    yes('Hủy lệnh trên hàng đợi', cc.status === 'Cancelled');
    const qd2 = await call('GET', '/api/pos/print-jobs/queue');
    yes('Lệnh đã hủy biến khỏi «Cần xử lý»', !qd2.items.some(x => x.id === j2.id && x.problem && x.problem !== 'cancelled'));

    console.log('7) Agent tắt khi đang giữ lệnh → lệnh không kẹt mãi');
    const j4 = await job(kitchen.id, 'rid-4-' + tag);
    const ca4 = await call('POST', `/api/pos/print-jobs/agents/${a.agentId}/claim`, {});
    const held = ca4?.jobId;
    await call('POST', '/api/pos/print-jobs/agents/offline', { deviceId: 'dev-A-' + tag, forceStop: true });
    const s4 = await call('GET', `/api/pos/print-jobs/${held || j4.id}`);
    yes('Agent A tắt → lệnh A đang giữ trả về «Chờ in» cho máy khác', /Queued/.test(s4.status), `${s4.status}`);
    const cb4 = await call('POST', `/api/pos/print-jobs/agents/${b.agentId}/claim`, {});
    yes('Máy B in tiếp lệnh đó', cb4?.jobId === (held || j4.id));
    if (cb4?.jobId) await call('POST', `/api/pos/print-jobs/${cb4.jobId}/complete?agentId=${b.agentId}`, {});

    console.log('8) Gán món → máy in (in bếp theo món)');
    const food = await call('POST', '/api/pos/products/quick', { name: `Phở bò ${tag}`, basePrice: 55000, costPrice: 20000, onHandQty: 0, baseUnitName: 'Tô', productType: 1, vatRate: 0, vatExempt: true });
    const drink = await call('POST', '/api/pos/products/quick', { name: `Trà đá ${tag}`, basePrice: 5000, costPrice: 1000, onHandQty: 0, baseUnitName: 'Ly', productType: 1, vatRate: 0, vatExempt: true });
    const as1 = await call('POST', `/api/pos/printers/product-assignment/printers/${kitchen.id}/assign`, { productIds: [food.id] }, true);
    const as2 = await call('POST', `/api/pos/printers/product-assignment/printers/${bar.id}/assign`, { productIds: [drink.id] }, true);
    yes('Gán Phở → bếp, Trà đá → bar', !as1.__err && !as2.__err, as1.__err || as2.__err || '');
    const map = await call('GET', '/api/pos/printers/product-assignment/map');
    const m = map.items || map.products || map;
    const flat = JSON.stringify(m);
    yes('Bản đồ món → máy in trả đúng', flat.includes(food.id) && flat.includes(drink.id), flat.length > 300 ? `${flat.length} ký tự` : flat);
  } catch (e) { fail++; console.error('LỖI', e.message); }
  finally {
    for (const id of created) await call('DELETE', `/api/pos/printers/${id}`, undefined, true);
    await call('POST', '/api/pos/print-jobs/agents/offline', { deviceId: 'dev-B-' + tag, forceStop: true }, true);
    console.log(`\n== ${pass} đạt, ${fail} lỗi`);
  }
})();
