import '../data/combination_category_rules.dart';

class CategoryClassificationResult {
  const CategoryClassificationResult({
    required this.category,
    required this.confidence,
    required this.reason,
  });

  final String category;
  final double confidence;
  final String reason;
}

class CombinationCategoryClassifier {
  static CategoryClassificationResult classify(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty) {
      return const CategoryClassificationResult(
        category: '기타',
        confidence: 0.0,
        reason: '빈 입력',
      );
    }

    for (final category in combinationFoodCategories) {
      if (category == '기타') continue;
      if (normalized == _normalize(category)) {
        return CategoryClassificationResult(
          category: category,
          confidence: 0.99,
          reason: '무료 AI 카테고리 직접 매칭',
        );
      }
    }

    final scores = <String, int>{};
    for (final entry in _keywords.entries) {
      var score = 0;
      for (final keyword in entry.value) {
        if (normalized.contains(keyword)) {
          score += keyword.length >= 3 ? 3 : 2;
        }
      }
      if (score > 0) {
        scores[entry.key] = score;
      }
    }

    if (scores.isEmpty) {
      return const CategoryClassificationResult(
        category: '기타',
        confidence: 0.3,
        reason: '규칙 미일치',
      );
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winner = ranked.first;
    final runnerUp = ranked.length > 1 ? ranked[1].value : 0;
    final confidence = ((winner.value - runnerUp) / (winner.value + 1)).clamp(
      0.35,
      0.98,
    );

    return CategoryClassificationResult(
      category: winner.key,
      confidence: confidence,
      reason: '무료 AI 키워드 분류',
    );
  }

  static String _normalize(String input) {
    return input.toLowerCase().replaceAll(' ', '');
  }
}

const Map<String, List<String>> _keywords = <String, List<String>>{
  '매운 컵라면': <String>['불닭', '마라', '틈새', '매운', '열라면', '신라면더레드', '핵', '매콤컵'],
  '국물 컵라면': <String>[
    '국물',
    '육개장',
    '사리곰탕',
    '신라면',
    '너구리',
    '튀김우동',
    '짬뽕',
    '우동',
    '컵누들',
    '잔치국수',
  ],
  '일반 컵라면': <String>['컵라면', '라면', '왕뚜껑', '진라면', '참깨라면', '새우탕', '컵면'],
  '볶음면': <String>['볶음면', '짜파게티', '비빔면', '까르보', '로제', '파스타', '볶음', '짜장면'],
  '삼각김밥': <String>['삼각김밥', '삼김', '주먹밥'],
  '김밥': <String>['김밥', '줄김밥', '꼬마김밥'],
  '도시락': <String>['도시락', '백반', '정식', '덮밥', '비빔밥'],
  '햄버거': <String>['햄버거', '버거'],
  '샌드위치': <String>['샌드위치', '샌드', '토스트', '베이글샌드'],
  '핫바': <String>['핫바', '어묵바', '게맛살바', '핫도그', '꼬치어묵'],
  '소시지': <String>['소시지', '후랑크', '프랑크', '비엔나'],
  '치즈': <String>['치즈', '스트링', '모짜렐라', '체다'],
  '계란': <String>['계란', '달걀', '반숙란', '구운계란', '훈제란', '반숙'],
  '우유': <String>['우유', '바나나우유', '초코우유', '딸기우유', '프로틴우유', '라떼우유', '흰우유'],
  '탄산음료': <String>['콜라', '사이다', '탄산', '환타', '스프라이트', '제로콜라', '쿨피스'],
  '에너지드링크': <String>['에너지드링크', '핫식스', '몬스터', '레드불', '에너지'],
  '커피': <String>['커피', '아메리카노', '라떼', '캔커피', '콜드브루'],
  '디저트': <String>[
    '디저트',
    '케이크',
    '푸딩',
    '도넛',
    '빵',
    '카스테라',
    '마카롱',
    '요거트',
    '컵과일',
    '과일컵',
  ],
  '과자': <String>['과자', '칩', '쿠키', '프레첼', '스낵', '크래커'],
  '샐러드': <String>['샐러드'],
  '닭가슴살': <String>['닭가슴살', '닭가슴살볼', '치킨브레스트'],
  '아이스크림': <String>['아이스크림', '빙과', '하드', '바닐라콘', '메로나', '콘아이스크림'],
  '기타': <String>[],
};

int satietyForCategory(String category) {
  return switch (category) {
    '매운 컵라면' => 34,
    '국물 컵라면' => 30,
    '일반 컵라면' => 28,
    '볶음면' => 32,
    '삼각김밥' => 18,
    '김밥' => 24,
    '도시락' => 38,
    '햄버거' => 28,
    '샌드위치' => 22,
    '핫바' => 18,
    '소시지' => 15,
    '치즈' => 8,
    '계란' => 11,
    '우유' => 10,
    '탄산음료' => 4,
    '에너지드링크' => 4,
    '커피' => 3,
    '디저트' => 12,
    '과자' => 9,
    '샐러드' => 20,
    '닭가슴살' => 23,
    '아이스크림' => 7,
    _ => 10,
  };
}

int? caloriesForCategory(String category) {
  return switch (category) {
    '매운 컵라면' => 530,
    '국물 컵라면' => 430,
    '일반 컵라면' => 420,
    '볶음면' => 520,
    '삼각김밥' => 220,
    '김밥' => 360,
    '도시락' => 700,
    '햄버거' => 420,
    '샌드위치' => 340,
    '핫바' => 180,
    '소시지' => 170,
    '치즈' => 85,
    '계란' => 70,
    '우유' => 180,
    '탄산음료' => 150,
    '에너지드링크' => 120,
    '커피' => 20,
    '디저트' => 280,
    '과자' => 250,
    '샐러드' => 210,
    '닭가슴살' => 180,
    '아이스크림' => 180,
    _ => null,
  };
}

List<String> defaultRecommendationCategoriesFor(String category) {
  return defaultRecommendationMap[category] ?? defaultRecommendationMap['기타']!;
}

bool isKnownCombinationCategory(String category) {
  return combinationFoodCategories.contains(category);
}
