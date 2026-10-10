// Thư viện dùng chung cho test local: đăng nhập, gọi API, ghi kết quả ĐẠT / LỖI.
// Tài khoản lấy từ biến môi trường — KHÔNG ghi mật khẩu vào repo:
//   SBOX_API          (mặc định http://localhost:7099)
//   SBOX_TEST_STORE   mã cửa hàng (vd quandemoui)
//   SBOX_TEST_USER / SBOX_TEST_PASS
//   hoặc SBOX_TEST_CRED_FILE: file chứa «email mật_khẩu» (ngoài repo).
'use strict';
const fs = require('fs');

const API = process.env.SBOX_API || 'http://localhost:7099';

function credentials() {
  let user = process.env.SBOX_TEST_USER;
  let pass = process.env.SBOX_TEST_PASS;
  const file = process.env.SBOX_TEST_CRED_FILE;
  if ((!user || !pass) && file && fs.existsSync(file)) {
    [user, pass] = fs.readFileSync(file, 'utf8').trim().split(/\s+/);
  }
  const store = process.env.SBOX_TEST_STORE;
  if (!store || !user || !pass) {
    console.error('Thiếu tài khoản test: đặt SBOX_TEST_STORE + SBOX_TEST_USER + SBOX_TEST_PASS (hoặc SBOX_TEST_CRED_FILE).');
    process.exit(2);
  }
  return { store, user, pass };
}

async function login() {
  const { store, user, pass } = credentials();
  const r = await fetch(`${API}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ storeCode: store, userName: user, password: pass }),
  });
  const j = await r.json().catch(() => ({}));
  if (!j.data?.accessToken) throw new Error(`Đăng nhập lỗi (${r.status}): ${j.message || ''}`);
  return { token: j.data.accessToken, refresh: j.data.refreshToken };
}

/** Client gọn: get/post/put/del trả { ok, status, data, message }. */
function client(token) {
  const call = async (method, path, body) => {
    const r = await fetch(API + path, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await r.text();
    let j = {};
    try { j = text ? JSON.parse(text) : {}; } catch { j = { message: text.slice(0, 300) }; }
    const ok = r.ok && j.isSuccess !== false;
    return { ok, status: r.status, data: j.data, message: j.message || (j.errors || []).join('; ') };
  };
  return {
    get: (p) => call('GET', p),
    post: (p, b) => call('POST', p, b ?? {}),
    put: (p, b) => call('PUT', p, b ?? {}),
    del: (p) => call('DELETE', p),
  };
}

/** Bảng kết quả kiểm thử. */
class Report {
  constructor(title) {
    this.title = title;
    this.rows = [];
    this.section = '';
  }
  group(name) {
    this.section = name;
    console.log(`\n── ${name} ─────────────────────────────`);
  }
  check(name, ok, detail = '') {
    this.rows.push({ section: this.section, name, ok: !!ok, detail });
    console.log(`  ${ok ? 'ĐẠT ' : 'LỖI '} ${name}${detail ? `  — ${detail}` : ''}`);
    return !!ok;
  }
  eq(name, actual, expected, tol = 0.5) {
    const ok = typeof expected === 'number'
      ? Math.abs(Number(actual) - expected) <= tol
      : actual === expected;
    return this.check(name, ok, `thực tế ${fmt(actual)} · mong đợi ${fmt(expected)}`);
  }
  must(name, res) {
    return this.check(name, res.ok, res.ok ? '' : `HTTP ${res.status}: ${res.message}`);
  }
  summary() {
    const fail = this.rows.filter((r) => !r.ok);
    console.log(`\n══ ${this.title}: ${this.rows.length - fail.length}/${this.rows.length} ĐẠT ══`);
    for (const f of fail) console.log(`  ✗ [${f.section}] ${f.name} — ${f.detail}`);
    return fail.length;
  }
  writeJson(file) {
    fs.writeFileSync(file, JSON.stringify({ title: this.title, at: new Date().toISOString(), rows: this.rows }, null, 2));
  }
}

const fmt = (v) => (typeof v === 'number' ? v.toLocaleString('vi-VN', { maximumFractionDigits: 2 }) : String(v));
const todayVn = () => new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);

module.exports = { API, login, client, Report, fmt, todayVn };
