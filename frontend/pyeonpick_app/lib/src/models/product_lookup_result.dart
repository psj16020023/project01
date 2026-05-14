class ProductLookupResult {
  const ProductLookupResult({
    required this.officialName,
    required this.scannedCode,
    required this.source,
    required this.cached,
    this.brand,
    this.store,
  });

  factory ProductLookupResult.fromJson(Map<String, dynamic> json) {
    return ProductLookupResult(
      officialName: json['officialName'] as String? ?? '',
      scannedCode: json['barcode'] as String? ?? '',
      source: json['source'] as String? ?? 'unknown',
      cached: json['cached'] as bool? ?? false,
      brand: json['brand'] as String?,
      store: json['store'] as String?,
    );
  }

  final String officialName;
  final String scannedCode;
  final String source;
  final bool cached;
  final String? brand;
  final String? store;
}
