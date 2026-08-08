import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/services/bot_budget_rules.dart';

void main() {
  group('BotBudgetRules', () {
    test('understands maximum budget expressions', () {
      for (final prompt in const [
        '5천 원 있는데 추천해줘',
        '예산 5천 원',
        '5천 원 이하',
        '5천 원 안으로',
      ]) {
        final mention = BotBudgetRules.parseMention(prompt);
        expect(mention?.amount, 5000, reason: prompt);
        expect(mention?.direction, BotBudgetDirection.maximum, reason: prompt);
      }
    });

    test('asks for clarification when 이상 is used', () {
      final mention = BotBudgetRules.parseMention('5000원 이상 아무거나');
      expect(mention?.amount, 5000);
      expect(mention?.direction, BotBudgetDirection.ambiguous);
    });

    test('understands the clarification answer', () {
      expect(
        BotBudgetRules.parseClarification('최대 예산이야'),
        BotBudgetClarification.maximum,
      );
      expect(
        BotBudgetRules.parseClarification('5천 원 이상 가격이야'),
        BotBudgetClarification.minimum,
      );
    });

    test('strictly excludes missing or over-budget prices', () {
      expect(
        BotBudgetRules.allowsPrice(
          priceMin: 4900,
          priceMax: 5000,
          maximumBudget: 5000,
        ),
        isTrue,
      );
      expect(
        BotBudgetRules.allowsPrice(
          priceMin: 5000,
          priceMax: 5001,
          maximumBudget: 5000,
        ),
        isFalse,
      );
      expect(
        BotBudgetRules.allowsPrice(
          priceMin: 0,
          priceMax: 0,
          maximumBudget: 5000,
        ),
        isFalse,
      );
    });
  });
}
