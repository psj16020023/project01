import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/services/retail_barcode.dart';

void main() {
  test('accepts supported retail barcode lengths', () {
    expect(normalizeRetailBarcode('880-1234-567890'), '8801234567890');
    expect(normalizeRetailBarcode('12345678'), '12345678');
    expect(normalizeRetailBarcode('123456789012'), '123456789012');
    expect(normalizeRetailBarcode('12345678901234'), '12345678901234');
  });

  test('rejects incomplete and non-retail values', () {
    expect(normalizeRetailBarcode(null), isEmpty);
    expect(normalizeRetailBarcode('1234567'), isEmpty);
    expect(normalizeRetailBarcode('hello'), isEmpty);
  });
}
