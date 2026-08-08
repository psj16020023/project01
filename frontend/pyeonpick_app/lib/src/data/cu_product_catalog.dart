import 'package:flutter/material.dart';

enum CuProductLabel { newProduct, pbProduct }

class CuProductSignal {
  const CuProductSignal({
    required this.store,
    required this.productName,
    required this.labels,
    this.barcode,
    this.aliases = const <String>[],
  });

  final String store;
  final String productName;
  final Set<CuProductLabel> labels;
  final String? barcode;
  final List<String> aliases;
}

class CuProductMatch {
  const CuProductMatch({
    required this.store,
    required this.productName,
    required this.labels,
    this.aliases = const <String>[],
  });

  final String store;
  final String productName;
  final Set<CuProductLabel> labels;
  final List<String> aliases;

  Color get color => switch (store) {
    'CU' => const Color(0xFF652F8F),
    'emart24' => const Color(0xFFF05A28),
    'GS25' => const Color(0xFF1C75BC),
    '7-Eleven' => const Color(0xFF008061),
    _ => const Color(0xFF273342),
  };
}

class CuProductCatalog {
  const CuProductCatalog._();

  // Seeded from confirmed crawler output. The backend keeps the full MongoDB
  // catalog; this lightweight cache lets posts render labels immediately.
  static const List<CuProductSignal> signals = <CuProductSignal>[
    CuProductSignal(
      store: 'CU',
      productName: 'PBICK)매실에이드제로P410',
      barcode: '8809125068214',
      aliases: <String>['매실 에이드 제로', '매실에이드제로'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: 'PBICK땅콩버터진미채',
      barcode: '8809885251536',
      aliases: <String>['땅콩버터 진미채', '땅콩버터진미채'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '겟모닝)어니언크림베이글',
      barcode: '8801068943085',
      aliases: <String>['어니언 크림 베이글', '어니언크림베이글'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '햄)양념통치킨버거',
      barcode: '8801771305040',
      aliases: <String>['양념 통치킨 버거', '양념통치킨버거'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '햄)불닭마요통치킨버거',
      barcode: '8801771304951',
      aliases: <String>['불닭마요 통치킨버거', '불닭마요통치킨버거'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '26del)아샷추230',
      barcode: '8800297740694',
      aliases: <String>['아샷추'],
      labels: <CuProductLabel>{},
    ),
    CuProductSignal(
      store: 'CU',
      productName: '26del)스위트아메리230',
      barcode: '8800297740670',
      aliases: <String>['스위트 아메리', '스위트아메리'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '김)쿵야김치볶음참치마요',
      barcode: '8800387750350',
      aliases: <String>['쿵야 김치볶음밥 참치마요', '쿵야김치볶음참치마요'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '도)쿵야반반닭강정팩',
      barcode: '8809655892563',
      aliases: <String>['반반 닭강정팩', '반반닭강정팩'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '도)별미골뱅이비빔면',
      barcode: '8809655892525',
      aliases: <String>['골뱅이 비빔면', '골뱅이비빔면'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '겟모닝)트러플머쉬룸버거',
      barcode: '8800348942251',
      aliases: <String>['트러플 머쉬룸 버거', '트러플머쉬룸버거'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '샐)저당발사믹샐러드',
      barcode: '8809954752063',
      aliases: <String>['저당 발사믹 샐러드', '저당발사믹샐러드'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '샌)대만식옥수수크림샌드',
      barcode: '8809895792159',
      aliases: <String>['대만식 옥수수 크림샌드', '대만식옥수수크림샌드'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '햄)보양삼계버거',
      barcode: '8800387750695',
      aliases: <String>['보양 삼계버거', '보양삼계버거'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '도)보양장어삼계밥',
      barcode: '8800271906368',
      aliases: <String>['보양 장어 삼계밥', '보양장어삼계밥'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '도)매콤아삭이고추비빔밥',
      barcode: '8800387750824',
      aliases: <String>['매콤 아삭이고추 비빔밥', '매콤아삭이고추비빔밥'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '면)베이컨크림스파게티',
      barcode: '8800281969957',
      aliases: <String>['베이컨 크림 스파게티', '베이컨크림스파게티'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '김)밥도둑묵은지참치',
      barcode: '8800271905231',
      aliases: <String>['밥도둑 묵은지 참치', '밥도둑묵은지참치'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: 'PBICK)더블감자베이컨피자',
      barcode: '8800296373572',
      aliases: <String>['더블 감자 베이컨 피자', '더블감자베이컨피자'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '햄)통새우치즈버거',
      barcode: '8800336395588',
      aliases: <String>['통새우 치즈버거', '통새우치즈버거'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '빅삼)콘참치마요제주',
      barcode: '8800387750978',
      aliases: <String>['콘참치마요 제주', '콘참치마요제주'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '샌)햄치즈토마토샌드',
      barcode: '8809895793149',
      aliases: <String>['햄치즈 토마토 샌드', '햄치즈토마토샌드'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'CU',
      productName: '샌)잠봉치즈크루아상샌드',
      barcode: '8800348942879',
      aliases: <String>['잠봉치즈 크루아상 샌드', '잠봉치즈크루아상샌드'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'emart24',
      productName: '포차24)매콤껍데기200g',
      barcode: '8804985166643',
      aliases: <String>['매콤 껍데기', '매콤껍데기'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'emart24',
      productName: '응급실)치즈쏘옥떡볶이300g',
      barcode: '8805489005711',
      aliases: <String>['치즈쏘옥 떡볶이', '치즈쏘옥떡볶이'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'emart24',
      productName: '옐로우)백미밥180g',
      barcode: '8809778499700',
      aliases: <String>['백미밥', '옐로우 백미밥'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: 'emart24',
      productName: '성수310)망고우유300ml',
      barcode: '8809117022590',
      aliases: <String>['망고 우유', '망고우유'],
      labels: <CuProductLabel>{CuProductLabel.pbProduct},
    ),
    CuProductSignal(
      store: 'emart24',
      productName: '더빅 치폴레치킨마요삼각김밥',
      barcode: '8800398700016',
      labels: <CuProductLabel>{CuProductLabel.pbProduct},
    ),
    CuProductSignal(
      store: 'emart24',
      productName: '포차24)머릿고기165g',
      barcode: '8804985177755',
      aliases: <String>['머릿고기', '포차24 머릿고기'],
      labels: <CuProductLabel>{
        CuProductLabel.newProduct,
        CuProductLabel.pbProduct,
      },
    ),
    CuProductSignal(
      store: '7-Eleven',
      productName: 'PB)오구딸기타임200ml',
      aliases: <String>['오구 딸기타임', '오구딸기타임'],
      labels: <CuProductLabel>{CuProductLabel.pbProduct},
    ),
    CuProductSignal(
      store: '7-Eleven',
      productName: 'PB)오구초코타임200ml',
      aliases: <String>['오구 초코타임', '오구초코타임'],
      labels: <CuProductLabel>{CuProductLabel.pbProduct},
    ),
    CuProductSignal(
      store: 'GS25',
      productName: '삼양)1963우지파개장(대컵)',
      barcode: '8801073217270',
      labels: <CuProductLabel>{},
    ),
  ];

  static Set<CuProductLabel> labelsForText(String text) {
    return matchesForText(text).fold(<CuProductLabel>{}, (labels, match) {
      labels.addAll(match.labels);
      return labels;
    });
  }

  static List<CuProductMatch> matchesForText(String text) {
    final normalizedText = _normalize(text);
    if (normalizedText.isEmpty) return const <CuProductMatch>[];

    final matches = <String, CuProductMatch>{};
    _addCrawlerPostMatch(text, matches);

    for (final signal in signals) {
      final candidates = <String>{signal.productName, ...signal.aliases};
      final hasMatch = candidates.any((candidate) {
        final normalizedName = _normalize(candidate);
        return normalizedName.isNotEmpty &&
            normalizedText.contains(normalizedName);
      });
      if (hasMatch && signal.labels.isNotEmpty) {
        matches['${signal.store}|${signal.productName}'] = CuProductMatch(
          store: signal.store,
          productName: signal.productName,
          labels: signal.labels,
          aliases: signal.aliases,
        );
      }
    }
    return matches.values.toList();
  }

  static void _addCrawlerPostMatch(
    String text,
    Map<String, CuProductMatch> matches,
  ) {
    for (final store in const <String>['CU', 'emart24', 'GS25', '7-Eleven']) {
      final marker = store == 'CU' ? 'CU 크롤링 데이터' : '$store 공개 상품 데이터';
      final markerIndex = text.indexOf(marker);
      if (markerIndex < 0) continue;

      final beforeMarker = text.substring(0, markerIndex).trim();
      final nameParts = beforeMarker
          .split(RegExp(r'\s{2,}|\n'))
          .where((item) => item.trim().isNotEmpty)
          .toList();
      final productName = nameParts.isEmpty ? null : nameParts.last.trim();
      final labels = <CuProductLabel>{};
      if (text.contains('신상품')) labels.add(CuProductLabel.newProduct);
      if (text.toLowerCase().contains('pb')) {
        labels.add(CuProductLabel.pbProduct);
      }
      if (labels.isEmpty) continue;

      final safeName = productName == null || productName.isEmpty
          ? '$store 감지 상품'
          : productName;
      matches['$store|$safeName'] = CuProductMatch(
        store: store,
        productName: safeName,
        labels: labels,
        aliases: <String>[_cleanCrawlerProductName(safeName)],
      );
    }
  }

  static String labelText(CuProductLabel label) {
    return switch (label) {
      CuProductLabel.newProduct => '신상',
      CuProductLabel.pbProduct => 'PB',
    };
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-z가-힣]'), '').trim();
  }

  static String _cleanCrawlerProductName(String value) {
    return value
        .replaceAll(RegExp(r'\d+(g|ml|p|입|개)$', caseSensitive: false), '')
        .trim();
  }
}
