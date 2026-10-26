import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_store_printer.dart';
import 'package:zkteco_flutter_client/utils/pos_local_printers_store.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_settings.dart';

void main() {
  PosLocalPrinterProfile local(String host, int port) => PosLocalPrinterProfile(
        id: 'loc-$port',
        name: 'Bếp $port',
        connectionType: PosThermalConnectionType.lan,
        lanHost: host,
        lanPort: port,
      );
  PosStorePrinter store(String host, int port) => PosStorePrinter(
        id: 'store-$port',
        name: 'Bếp $port',
        connectionType: 'Lan',
        lanHost: host,
        lanPort: port,
      );

  test('máy LAN cùng IP cùng cổng là một máy', () {
    expect(
      PosLocalPrintersStore.matchesStorePrinter(
          local('192.168.1.89', 9100), store('192.168.1.89', 9100)),
      isTrue,
    );
  });

  test('cùng IP khác cổng (print server nhiều cổng) là hai máy khác nhau', () {
    expect(
      PosLocalPrintersStore.matchesStorePrinter(
          local('192.168.1.50', 9100), store('192.168.1.50', 9101)),
      isFalse,
    );
  });

  test('cổng 0 / chưa đặt hiểu là 9100', () {
    expect(
      PosLocalPrintersStore.matchesStorePrinter(
          local('192.168.1.89', 9100), store('192.168.1.89', 0)),
      isTrue,
    );
  });
}
