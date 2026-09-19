import '../services/api_service.dart';

class TingeeSupportedBank {
  const TingeeSupportedBank({
    required this.bin,
    required this.code,
    required this.name,
    required this.shortName,
  });

  final String bin;
  final String code;
  final String name;
  final String shortName;

  String get label =>
      shortName.isNotEmpty ? '$shortName ($bin)' : '$name ($bin)';
}

/// 14 ngân hàng Tingee thường mở VA — fallback khi API get-banks lỗi.
const kTingeeFallbackBanks = <TingeeSupportedBank>[
  TingeeSupportedBank(bin: '970418', code: 'BIDV', name: 'BIDV', shortName: 'BIDV'),
  TingeeSupportedBank(bin: '970436', code: 'VCB', name: 'Vietcombank', shortName: 'Vietcombank'),
  TingeeSupportedBank(bin: '970415', code: 'CTG', name: 'VietinBank', shortName: 'VietinBank'),
  TingeeSupportedBank(bin: '970422', code: 'MBB', name: 'MB Bank', shortName: 'MB Bank'),
  TingeeSupportedBank(bin: '970416', code: 'ACB', name: 'ACB', shortName: 'ACB'),
  TingeeSupportedBank(bin: '970432', code: 'VPB', name: 'VPBank', shortName: 'VPBank'),
  TingeeSupportedBank(bin: '970403', code: 'STB', name: 'Sacombank', shortName: 'Sacombank'),
  TingeeSupportedBank(bin: '970448', code: 'OCB', name: 'OCB', shortName: 'OCB'),
  TingeeSupportedBank(bin: '970430', code: 'PGB', name: 'PGBank', shortName: 'PGBank'),
  TingeeSupportedBank(bin: '970441', code: 'VIB', name: 'VIB', shortName: 'VIB'),
  TingeeSupportedBank(bin: '970423', code: 'TPB', name: 'TPBank', shortName: 'TPBank'),
  TingeeSupportedBank(bin: '970426', code: 'MSB', name: 'MSB', shortName: 'MSB'),
  TingeeSupportedBank(bin: '970407', code: 'TCB', name: 'Techcombank', shortName: 'Techcombank'),
  TingeeSupportedBank(bin: '970437', code: 'HDB', name: 'HDBank', shortName: 'HDBank'),
];

Future<List<TingeeSupportedBank>> loadTingeeSupportedBanks({
  bool admin = false,
}) async {
  final res = admin
      ? await ApiService().adminTingeeBanks()
      : await ApiService().posTingeeBanks();
  if (res['isSuccess'] == true && res['data'] is List) {
    final out = <TingeeSupportedBank>[];
    for (final raw in res['data'] as List) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final bin = (m['bin'] ?? m['Bin'] ?? '').toString().trim();
      if (bin.isEmpty) continue;
      final code = (m['code'] ?? m['Code'] ?? '').toString();
      final name = (m['name'] ?? m['Name'] ?? code).toString();
      final shortName =
          (m['shortName'] ?? m['ShortName'] ?? name).toString();
      out.add(TingeeSupportedBank(
        bin: bin,
        code: code.isEmpty ? bin : code,
        name: name,
        shortName: shortName,
      ));
    }
    if (out.isNotEmpty) return out;
  }
  return List<TingeeSupportedBank>.from(kTingeeFallbackBanks);
}
