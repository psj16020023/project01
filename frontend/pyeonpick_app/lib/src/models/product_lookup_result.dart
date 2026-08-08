class ProductLookupResult {
  const ProductLookupResult({
    required this.officialName,
    required this.scannedCode,
    required this.source,
    required this.cached,
    required this.tentative,
    this.brand,
    this.store,
    this.imageUrl,
    this.price,
    this.calories,
    this.warning,
  });

  factory ProductLookupResult.fromJson(Map<String, dynamic> json) {
    return ProductLookupResult(
      officialName: json['officialName'] as String? ?? '',
      scannedCode: json['barcode'] as String? ?? '',
      source: json['source'] as String? ?? 'unknown',
      cached: json['cached'] as bool? ?? false,
      tentative: json['tentative'] as bool? ?? false,
      brand: json['brand'] as String?,
      store: json['store'] as String?,
      imageUrl:
          (json['images'] as Map<String, dynamic>?)?['product'] as String?,
      price: (json['price'] as num?)?.round(),
      calories: (json['calories'] as num?)?.round(),
      warning: json['warning'] as String?,
    );
  }

  final String officialName;
  final String scannedCode;
  final String source;
  final bool cached;
  final bool tentative;
  final String? brand;
  final String? store;
  final String? imageUrl;
  final int? price;
  final int? calories;
  final String? warning;
}
