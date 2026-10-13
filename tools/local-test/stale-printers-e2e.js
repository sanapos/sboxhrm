#!/usr/bin/env node
// Kiểm thử «Dọn máy in cũ» trên API LOCAL: máy in lâu không hoạt động hiện trong danh sách,
// máy mới / máy có lệnh in thì không; tắt (không xóa) chỉ máy cũ.
//
//   SBOX_API=http://localhost:7199 node stale-printers-e2e.js
// Cần psql (PostgreSQL local) để «làm cũ» máy thử: SBOX_PSQL (mặc định PostgreSQL 16) + chuỗi kết nối
// lấy từ appsettings.Development.json, đổi CSDL theo SBOX_TEST_DB (mặc định sbox_uidemo).
'use strict';
const path = require('path');
const fs = require('fs');
const { execFileSync } = require('child_process');
const { API, login, client, Report } = require('./lib/api');

if (!/localhost|127\.0\.0\.1/.test(API)) {
  console.error(`Từ chối chạy vào ${API} — chỉ dành cho API local.`);
  process.exit(2);
}

const PSQL = process.env.SBOX_PSQL || 'C:/Program Files/PostgreSQL/16/bin/psql.exe';
function pgEnv() {
  const file = path.join(__dirname, '../../src/ZKTecoADMS.Api/appsettings.Development.json');
  const cs = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')).ConnectionStrings.DefaultConnection;
  const kv = Object.fromEntries(cs.split(';').filter(Boolean).map((p) => {
    const i = p.indexOf('=');
    return [p.slice(0, i).trim().toLowerCase(), p.slice(i + 1)];
  }));
  if (!/^(localhost|127\.0\.0\.1)$/.test(kv.host)) throw new Error('CSDL không phải localhost');
  return {
    ...process.env,
    PGHOST: kv.host, PGPORT: kv.port || '5432', PGUSER: kv.username,
    PGPASSWORD: kv.password, PGDATABASE: process.env.SBOX_TEST_DB || 'sbox_uidemo',
  };
}
const sql = (q) => execFileSync(PSQL, ['-tAc', q], { env: pgEnv(), encoding: 'utf8' }).trim();

const R = new Report('Kiểm thử dọn máy in cũ (local)');
const tag = 'STALE' + new Date().toISOString().replace(/\D/g, '').slice(4, 12);

(async () => {
  const { token } = await login();
  const api = client(token);
  const mk = async (name, host) => {
    const r = await api.post('/api/pos/printers', {
      name, connectionType: 'Lan', lanHost: host, lanPort: 9100,
      paperSize: '80mm', isActive: true,
    });
    R.must(`Tạo máy ${name}`, r);
    return r.data?.id;
  };

  R.group('Chuẩn bị');
  const oldId = await mk(`${tag} cũ`, '10.254.1.1');
  const newId = await mk(`${tag} mới`, '10.254.1.2');
  const old = new Date(Date.now() - 40 * 86400e3).toISOString();
  sql(`UPDATE "PosStorePrinters" SET "CreatedAt"='${old}', "UpdatedAt"='${old}', "LastSeenAt"=NULL WHERE "Id"='${oldId}'`);

  R.check('Hai máy khác nhau', oldId && newId && oldId !== newId);

  R.group('Xem trước');
  const pre = await api.get('/api/pos/printers/stale?days=14');
  R.must('GET stale', pre);
  const ids = (pre.data || []).map((p) => p.id);
  R.check('Máy cũ có trong danh sách', ids.includes(oldId), ids.length);
  R.check('Máy mới không có', !ids.includes(newId));
  const row = (pre.data || []).find((p) => p.id === oldId) || {};
  R.check('Có lý do + thời điểm hoạt động cuối', !!row.reason && !!row.lastActivityAt, row.reason);
  R.check('Xem trước không đổi gì',
    sql(`SELECT "IsActive" FROM "PosStorePrinters" WHERE "Id"='${oldId}'`) === 't');

  R.group('Tắt máy cũ');
  const de = await api.post('/api/pos/printers/stale/deactivate?days=14');
  R.must('POST deactivate', de);
  R.check('Số máy đã tắt ≥ 1', (de.data?.deactivated ?? 0) >= 1, de.data?.deactivated);
  R.check('Máy cũ IsActive=false (không xóa)',
    sql(`SELECT "IsActive"::text || coalesce("Deleted"::text,'') FROM "PosStorePrinters" WHERE "Id"='${oldId}'`) === 'false');
  R.check('Máy mới vẫn bật',
    sql(`SELECT "IsActive" FROM "PosStorePrinters" WHERE "Id"='${newId}'`) === 't');
  const again = await api.get('/api/pos/printers/stale?days=14');
  R.check('Chạy lại: máy cũ không còn trong danh sách', !(again.data || []).some((p) => p.id === oldId));

  R.group('Dọn dữ liệu thử');
  for (const id of [oldId, newId]) if (id) await api.del(`/api/pos/printers/${id}`);
  process.exitCode = R.summary() ? 1 : 0;
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
