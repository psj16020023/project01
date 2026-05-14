class ProductLookupResult {
  const ProductLookupResult({
    required this.productName,
    required this.scannedCode,
    required this.matchedFromCatalog,
  });

  final String productName;
  final String scannedCode;
  final bool matchedFromCatalog;
}

class ProductCatalog {
  static const Map<String, String> _barcodeToProductName = {
    '8801069410713': '코카콜라 250ml',
    '8801094202000': '삼각김밥 참치마요',
    '8801105907023': '빙그레 바나나맛우유 240ml',
    '8801115112905': '불닭볶음면 컵',
    '8801161720123': '쿠크다스 화이트토르테',
    '8801223002012': '딸기우유 300ml',
    '8809300660361': '프레첼 오리지널',
  };

  static ProductLookupResult resolve(String rawValue) {
    final normalized = rawValue.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final productName = _barcodeToProductName[normalized];

    if (productName != null) {
      return ProductLookupResult(
        productName: productName,
        scannedCode: normalized,
        matchedFromCatalog: true,
      );
    }

    return ProductLookupResult(
      productName: '상품명 확인 필요 ($normalized)',
      scannedCode: normalized,
      matchedFromCatalog: false,
    );
  }
}
