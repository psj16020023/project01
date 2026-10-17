const Set<int> _retailBarcodeLengths = <int>{8, 12, 13, 14};

String normalizeRetailBarcode(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return _retailBarcodeLengths.contains(digits.length) ? digits : '';
}
