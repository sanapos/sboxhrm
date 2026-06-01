import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;

/// Excel serial (Windows 1900 date system) → DateTime.
DateTime? _dateFromExcelSerial(double serial) {
  if (serial < 1 || serial > 120000) return null;
  final epoch = DateTime(1899, 12, 30);
  return epoch.add(Duration(days: serial.floor()));
}

/// Số điện thoại / mã NV 9 chữ số (Excel bỏ số 0 đầu) → thêm 0.
String _normalizeVnNumericId(String s) {
  final t = s.trim();
  if (RegExp(r'^\d{9}$').hasMatch(t)) return '0$t';
  return t;
}

/// Đọc giá trị ô Excel (số, ngày, chữ) thành chuỗi hiển thị.
String excelCellText(excel.Data? cell) {
  if (cell == null) return '';
  final v = cell.value;
  if (v == null) return '';
  return switch (v) {
    excel.TextCellValue() => v.value.toString().trim(),
    excel.IntCellValue() => v.value.toString(),
    excel.DoubleCellValue() => () {
        final d = v.value;
        if (d.isNaN || d.isInfinite) return '';
        if (d == d.roundToDouble() && d.abs() < 1e15) {
          return d.toInt().toString();
        }
        return d.toString();
      }(),
    excel.DateCellValue() =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}',
    excel.DateTimeCellValue() =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}',
    excel.BoolCellValue() => v.value.toString(),
    _ => v.toString().trim(),
  };
}

DateTime? _parseDateText(String s) {
  if (s.isEmpty) return null;
  try {
    final parts = s.split(RegExp(r'[/\-.]'));
    if (parts.length == 3) {
      final a = int.parse(parts[0].trim());
      final b = int.parse(parts[1].trim());
      final c = int.parse(parts[2].trim());
      if (c > 31) return DateTime(c, b, a);
      if (a > 31) return DateTime(a, b, c);
      return DateTime(c, b, a);
    }
  } catch (_) {}
  return null;
}

DateTime? _sanitizeDateOfBirth(DateTime? d) {
  if (d == null) return null;
  final y = d.year;
  if (y < 1900 || y > DateTime.now().year) return null;
  return d;
}

DateTime? excelCellDate(excel.Data? cell) {
  if (cell == null) return null;
  final v = cell.value;
  if (v == null) return null;
  if (v is excel.DateCellValue) {
    return _sanitizeDateOfBirth(v.asDateTimeLocal());
  }
  if (v is excel.DateTimeCellValue) {
    return _sanitizeDateOfBirth(
        DateTime(v.year, v.month, v.day, v.hour, v.minute, v.second));
  }
  if (v is excel.DoubleCellValue) {
    return _sanitizeDateOfBirth(_dateFromExcelSerial(v.value));
  }
  if (v is excel.IntCellValue && v.value > 1000 && v.value < 120000) {
    return _sanitizeDateOfBirth(_dateFromExcelSerial(v.value.toDouble()));
  }
  return _sanitizeDateOfBirth(_parseDateText(excelCellText(cell)));
}

String? _normalizeGender(String raw) {
  final g = raw.trim().toLowerCase();
  if (g.isEmpty) return null;
  if (g == 'nam' || g == 'male' || g == 'm') return 'Nam';
  if (g == 'nu' || g == 'nữ' || g == 'female' || g == 'f') return 'Nữ';
  return raw.trim();
}

String _normHeader(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
      .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
      .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
      .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
      .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
      .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
      .replaceAll('đ', 'd')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Tách "Nguyễn Văn A" → họ / tên.
(String lastName, String firstName) splitVietnameseFullName(String full) {
  final trimmed = full.trim();
  if (trimmed.isEmpty) return ('.', '?');
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) return (parts[0], '.');
  return (parts.first, parts.sublist(1).join(' '));
}

class _ColumnMap {
  final int? code;
  final int? lastName;
  final int? firstName;
  final int? fullName;
  final int? companyEmail;
  final int? gender;
  final int? dateOfBirth;
  final int? nationalId;
  final int? hometown;
  final int? education;
  final int? marital;
  final int? phone;
  final int? personalEmail;
  final int? address;
  final int? department;
  final int? position;
  final int? level;
  final int? joinDate;
  final int? bankName;
  final int? bankAccount;
  final int? bankAccountName;

  const _ColumnMap({
    this.code,
    this.lastName,
    this.firstName,
    this.fullName,
    this.companyEmail,
    this.gender,
    this.dateOfBirth,
    this.nationalId,
    this.hometown,
    this.education,
    this.marital,
    this.phone,
    this.personalEmail,
    this.address,
    this.department,
    this.position,
    this.level,
    this.joinDate,
    this.bankName,
    this.bankAccount,
    this.bankAccountName,
  });

  bool get isValid =>
      code != null &&
      ((lastName != null && firstName != null) || fullName != null);
}

_ColumnMap _mapHeaders(List<excel.Data?> headerRow) {
  int? code,
      lastName,
      firstName,
      fullName,
      companyEmail,
      gender,
      dateOfBirth,
      nationalId,
      hometown,
      education,
      marital,
      phone,
      personalEmail,
      address,
      department,
      position,
      level,
      joinDate,
      bankName,
      bankAccount,
      bankAccountName;

  for (var i = 0; i < headerRow.length; i++) {
    final h = _normHeader(excelCellText(headerRow[i]));
    if (h.isEmpty) continue;
    if (h == 'stt' || h == 'tt') continue;

    if (code == null &&
        (h.contains('manv') ||
            h.contains('manhanvien') ||
            h == 'ma' ||
            h.contains('employeeid'))) {
      code = i;
    } else if (fullName == null &&
        (h.contains('hovaten') || h.contains('hoten'))) {
      fullName = i;
    } else if (lastName == null && (h == 'ho' || h.contains('holot'))) {
      lastName = i;
    } else if (firstName == null &&
        (h == 'ten' || h.contains('tendem') || h.contains('tennv'))) {
      firstName = i;
    } else if (companyEmail == null &&
        (h.contains('emailcongty') || h.contains('emailct') || h == 'email')) {
      companyEmail = i;
    } else if (gender == null && h.contains('gioitinh')) {
      gender = i;
    } else if (dateOfBirth == null &&
        (h.contains('ngaysinh') || h == 'sinhnhat')) {
      dateOfBirth = i;
    } else if (nationalId == null &&
        (h.contains('cccd') || h.contains('cmnd') || h.contains('socmnd'))) {
      nationalId = i;
    } else if (hometown == null && h.contains('quequan')) {
      hometown = i;
    } else if (education == null &&
        (h.contains('trinhdo') || h.contains('hocvan'))) {
      education = i;
    } else if (marital == null &&
        (h.contains('hơnnhan') || h.contains('tinhtranghn'))) {
      marital = i;
    } else if (phone == null &&
        (h.contains('sdt') || h.contains('dienthoai') || h.contains('phone'))) {
      phone = i;
    } else if (personalEmail == null && h.contains('emailcanhan')) {
      personalEmail = i;
    } else if (address == null &&
        (h.contains('diachi') || h.contains('thuongtru'))) {
      address = i;
    } else if (department == null &&
        (h.contains('phơngban') || h.contains('bophan'))) {
      department = i;
    } else if (position == null &&
        (h.contains('chucvu') || h.contains('vitri'))) {
      position = i;
    } else if (level == null &&
        (h.contains('capbac') || h.contains('bac') || h == 'cap')) {
      level = i;
    } else if (joinDate == null &&
        (h.contains('ngayvaolam') ||
            h.contains('ngaybatdau') ||
            h.contains('ngayvao'))) {
      joinDate = i;
    } else if (bankName == null && h.contains('nganhang')) {
      bankName = i;
    } else if (bankAccount == null &&
        (h.contains('sotaikhoan') || h.contains('sotk') || h == 'stk')) {
      bankAccount = i;
    } else if (bankAccountName == null && h.contains('tentaikhoan')) {
      bankAccountName = i;
    }
  }

  return _ColumnMap(
    code: code,
    lastName: lastName,
    firstName: firstName,
    fullName: fullName,
    companyEmail: companyEmail,
    gender: gender,
    dateOfBirth: dateOfBirth,
    nationalId: nationalId,
    hometown: hometown,
    education: education,
    marital: marital,
    phone: phone,
    personalEmail: personalEmail,
    address: address,
    department: department,
    position: position,
    level: level,
    joinDate: joinDate,
    bankName: bankName,
    bankAccount: bankAccount,
    bankAccountName: bankAccountName,
  );
}

/// Cột mặc định file Export từ API (hàng header "Mã NV" ở cột B).
const _exportDefaultMap = _ColumnMap(
  code: 1,
  fullName: 2,
  gender: 3,
  dateOfBirth: 4,
  nationalId: 5,
  hometown: 6,
  education: 7,
  phone: 8,
  companyEmail: 9,
  department: 10,
  position: 11,
  joinDate: 13,
  bankName: 15,
  bankAccount: 16,
);

/// Cột mặc định file mẫu Import (A–S).
const _importDefaultMap = _ColumnMap(
  code: 0,
  fullName: 1,
  companyEmail: 2,
  gender: 3,
  dateOfBirth: 4,
  nationalId: 5,
  hometown: 6,
  education: 7,
  marital: 8,
  phone: 9,
  personalEmail: 10,
  address: 11,
  department: 12,
  position: 13,
  level: 14,
  joinDate: 15,
  bankName: 16,
  bankAccount: 17,
  bankAccountName: 18,
);

int? _findHeaderRowIndex(excel.Sheet sheet) {
  final maxScan = sheet.rows.length < 25 ? sheet.rows.length : 25;
  for (var i = 0; i < maxScan; i++) {
    final row = sheet.rows[i];
    for (var c = 0; c < row.length && c < 25; c++) {
      final h = _normHeader(excelCellText(row[c]));
      if (h.contains('manv') ||
          h.contains('manhanvien') ||
          h.contains('hovaten') ||
          h == 'ho') {
        return i;
      }
    }
  }
  return null;
}

String _pick(List<excel.Data?> row, int? col) {
  if (col == null || col < 0 || col >= row.length) return '';
  return excelCellText(row[col]);
}

DateTime? _pickDate(List<excel.Data?> row, int? col) {
  if (col == null || col < 0 || col >= row.length) return null;
  return excelCellDate(row[col]);
}

Map<String, dynamic>? _rowToRecord(List<excel.Data?> row, _ColumnMap cols) {
  var code = _normalizeVnNumericId(_pick(row, cols.code));
  if (code.isEmpty) return null;

  // Bỏ dòng ghi chú / tiêu đề phụ.
  final lowerCode = code.toLowerCase();
  if (lowerCode.contains('xuat ngay') ||
      lowerCode.contains('danh sach') ||
      lowerCode == 'ma nv') {
    return null;
  }

  String lastName;
  String firstName;
  if (cols.fullName != null) {
    final full = _pick(row, cols.fullName);
    if (full.isEmpty) return null;
    (lastName, firstName) = splitVietnameseFullName(full);
  } else {
    lastName = _pick(row, cols.lastName);
    firstName = _pick(row, cols.firstName);
    if (lastName.isEmpty && firstName.isEmpty) return null;
    if (lastName.isEmpty) lastName = '.';
    if (firstName.isEmpty) firstName = '.';
  }

  final email = _pick(row, cols.companyEmail);
  final dob = _pickDate(row, cols.dateOfBirth);
  final join = _pickDate(row, cols.joinDate);

  return {
    'employeeCode': code,
    'lastName': lastName,
    'firstName': firstName,
    'companyEmail': email.isNotEmpty ? email : '$code@company.com',
    'gender': _normalizeGender(_pick(row, cols.gender)),
    'dateOfBirth': dob?.toIso8601String(),
    'nationalIdNumber':
        _pick(row, cols.nationalId).isNotEmpty ? _pick(row, cols.nationalId) : null,
    'hometown': _pick(row, cols.hometown).isNotEmpty ? _pick(row, cols.hometown) : null,
    'educationLevel':
        _pick(row, cols.education).isNotEmpty ? _pick(row, cols.education) : null,
    'maritalStatus':
        _pick(row, cols.marital).isNotEmpty ? _pick(row, cols.marital) : null,
    'phoneNumber': _pick(row, cols.phone).isNotEmpty ? _pick(row, cols.phone) : null,
    'personalEmail': _pick(row, cols.personalEmail).isNotEmpty
        ? _pick(row, cols.personalEmail)
        : null,
    'permanentAddress':
        _pick(row, cols.address).isNotEmpty ? _pick(row, cols.address) : null,
    'department':
        _pick(row, cols.department).isNotEmpty ? _pick(row, cols.department) : null,
    'position':
        _pick(row, cols.position).isNotEmpty ? _pick(row, cols.position) : null,
    'level': _pick(row, cols.level).isNotEmpty ? _pick(row, cols.level) : null,
    'joinDate': join?.toIso8601String(),
    'bankName':
        _pick(row, cols.bankName).isNotEmpty ? _pick(row, cols.bankName) : null,
    'bankAccountNumber': _pick(row, cols.bankAccount).isNotEmpty
        ? _pick(row, cols.bankAccount)
        : null,
    'bankAccountName': _pick(row, cols.bankAccountName).isNotEmpty
        ? _pick(row, cols.bankAccountName)
        : null,
    'employmentType': 0,
    'workStatus': 0,
  };
}

excel.Sheet? _pickEmployeeImportSheet(excel.Excel book) {
  if (book.tables.containsKey('Import')) return book.tables['Import'];
  for (final sheet in book.tables.values) {
    if (_findHeaderRowIndex(sheet) != null) return sheet;
  }
  return book.tables.values.isEmpty ? null : book.tables.values.first;
}

/// Parse sheet nhân viên — hỗ trợ file mẫu Import và file Export từ hệ thống.
List<Map<String, dynamic>> parseEmployeeExcelBytes(Uint8List bytes) {
  final book = excel.Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) return [];

  final sheet = _pickEmployeeImportSheet(book);
  if (sheet == null) return [];
  if (sheet.rows.length < 2) return [];

  final headerIdx = _findHeaderRowIndex(sheet);
  final dataStart = headerIdx != null ? headerIdx + 1 : 1;

  _ColumnMap cols;
  if (headerIdx != null) {
    final mapped = _mapHeaders(sheet.rows[headerIdx]);
    if (mapped.isValid) {
      cols = mapped;
    } else if (mapped.fullName != null && mapped.code != null) {
      cols = mapped;
    } else {
      // Header có "Mã NV" ở cột 1 → export
      final h1 = _normHeader(excelCellText(sheet.rows[headerIdx][1]));
      cols = h1.contains('manv') ? _exportDefaultMap : _importDefaultMap;
    }
  } else {
    cols = _importDefaultMap;
  }

  final records = <Map<String, dynamic>>[];
  for (var i = dataStart; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    if (row.isEmpty) continue;
    final rec = _rowToRecord(row, cols);
    if (rec != null) records.add(rec);
  }
  return records;
}

/// Tạo file mẫu .xlsx để import nhân viên (chỉ sheet Import).
Uint8List buildEmployeeImportTemplateBytes() {
  final book = excel.Excel.createExcel();
  final sheet = book['Import'];
  if (book.sheets.containsKey('Sheet1')) {
    book.delete('Sheet1');
  }
  final headers = [
    'Mã NV',
    'Họ và tên',
    'Email công ty',
    'Giới tính',
    'Ngày sinh (dd/MM/yyyy)',
    'CCCD',
    'Quê quán',
    'Trình độ HV',
    'Tình trạng HN',
    'SĐT',
    'Email cá nhân',
    'Địa chỉ thường trú',
    'Phòng ban',
    'Chức vụ',
    'Cấp bậc',
    'Ngày vào làm (dd/MM/yyyy)',
    'Ngân hàng',
    'Số TK',
    'Tên TK ngân hàng',
  ];
  for (var c = 0; c < headers.length; c++) {
    sheet
        .cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
        .value = excel.TextCellValue(headers[c]);
  }
  sheet
      .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
      .value = excel.TextCellValue('NV001');
  sheet
      .cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
      .value = excel.TextCellValue('Nguyễn Văn A');
  sheet
      .cell(excel.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1))
      .value = excel.TextCellValue('nv001@company.com');
  return Uint8List.fromList(book.encode()!);
}
