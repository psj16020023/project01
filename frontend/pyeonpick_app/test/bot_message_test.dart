import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/models/bot_message.dart';

void main() {
  test('bot conversation context survives JSON storage', () {
    final message = BotMessage(
      role: 'assistant',
      text: '추천 결과',
      createdAt: DateTime(2026, 6, 25),
      recommendedPostIds: const ['post-1'],
      resolvedBudget: 5000,
      minimumPrice: 3000,
      contextPrompt: '5천 원 있는데 아무거나',
      useAgeCalorieGuide: true,
      pendingClarification: 'budgetDirection',
      pendingAmount: 5000,
    );

    final restored = BotMessage.fromJson(message.toJson());

    expect(restored.resolvedBudget, 5000);
    expect(restored.minimumPrice, 3000);
    expect(restored.contextPrompt, '5천 원 있는데 아무거나');
    expect(restored.useAgeCalorieGuide, isTrue);
    expect(restored.pendingClarification, 'budgetDirection');
    expect(restored.pendingAmount, 5000);
  });
}
