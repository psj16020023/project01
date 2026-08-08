enum BotBudgetDirection { maximum, minimum, ambiguous }

enum BotBudgetClarification { maximum, minimum, unknown }

class BotBudgetMention {
  const BotBudgetMention({required this.amount, required this.direction});

  final int amount;
  final BotBudgetDirection direction;
}

class BotBudgetRules {
  const BotBudgetRules._();

  static BotBudgetMention? parseMention(String prompt) {
    final normalized = prompt.toLowerCase().replaceAll(',', '');
    final amount = _extractAmount(normalized);
    if (amount == null) return null;

    if (_containsAny(normalized, const ['최소 ', '최저 ', '보다 비싼', '넘는 가격'])) {
      return BotBudgetMention(
        amount: amount,
        direction: BotBudgetDirection.minimum,
      );
    }
    if (normalized.contains('이상')) {
      return BotBudgetMention(
        amount: amount,
        direction: BotBudgetDirection.ambiguous,
      );
    }
    return BotBudgetMention(
      amount: amount,
      direction: BotBudgetDirection.maximum,
    );
  }

  static BotBudgetClarification parseClarification(String prompt) {
    final normalized = prompt.toLowerCase().replaceAll(' ', '');
    if (_containsAny(normalized, const [
      '최대',
      '예산',
      '안넘',
      '넘지',
      '이하',
      '안으로',
      '내로',
      '첫번째',
      '1번',
    ])) {
      return BotBudgetClarification.maximum;
    }
    if (_containsAny(normalized, const [
      '최소',
      '이상가격',
      '비싼거',
      '비싼것',
      '두번째',
      '2번',
    ])) {
      return BotBudgetClarification.minimum;
    }
    return BotBudgetClarification.unknown;
  }

  static bool allowsPrice({
    required int priceMin,
    required int priceMax,
    int? maximumBudget,
    int? minimumPrice,
  }) {
    if (maximumBudget != null && (priceMax <= 0 || priceMax > maximumBudget)) {
      return false;
    }
    if (minimumPrice != null && (priceMin <= 0 || priceMin < minimumPrice)) {
      return false;
    }
    return true;
  }

  static int? _extractAmount(String prompt) {
    final compoundWon = RegExp(
      r'(\d+)\s*만\s*(\d+)\s*천\s*원?',
    ).firstMatch(prompt);
    if (compoundWon != null) {
      return (int.parse(compoundWon.group(1)!) * 10000) +
          (int.parse(compoundWon.group(2)!) * 1000);
    }
    final manWon = RegExp(r'(\d+(?:\.\d+)?)\s*만\s*원?').firstMatch(prompt);
    if (manWon != null) {
      return (double.parse(manWon.group(1)!) * 10000).round();
    }
    final thousandWon = RegExp(r'(\d+(?:\.\d+)?)\s*천\s*원?').firstMatch(prompt);
    if (thousandWon != null) {
      return (double.parse(thousandWon.group(1)!) * 1000).round();
    }
    final won = RegExp(r'(\d{3,7})\s*원').firstMatch(prompt);
    return won == null ? null : int.tryParse(won.group(1)!);
  }

  static bool _containsAny(String source, List<String> needles) {
    return needles.any(source.contains);
  }
}
