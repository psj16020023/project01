class BotMessage {
  const BotMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.recommendedPostIds = const <String>[],
    this.resolvedBudget,
    this.minimumPrice,
    this.contextPrompt,
    this.useAgeCalorieGuide,
    this.pendingClarification,
    this.pendingAmount,
  });

  factory BotMessage.fromJson(Map<String, dynamic> json) {
    return BotMessage(
      role: json['role'] as String? ?? 'assistant',
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      recommendedPostIds:
          (json['recommendedPostIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      resolvedBudget: (json['resolvedBudget'] as num?)?.toInt(),
      minimumPrice: (json['minimumPrice'] as num?)?.toInt(),
      contextPrompt: json['contextPrompt'] as String?,
      useAgeCalorieGuide: json['useAgeCalorieGuide'] as bool?,
      pendingClarification: json['pendingClarification'] as String?,
      pendingAmount: (json['pendingAmount'] as num?)?.toInt(),
    );
  }

  final String role;
  final String text;
  final DateTime createdAt;
  final List<String> recommendedPostIds;
  final int? resolvedBudget;
  final int? minimumPrice;
  final String? contextPrompt;
  final bool? useAgeCalorieGuide;
  final String? pendingClarification;
  final int? pendingAmount;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'recommendedPostIds': recommendedPostIds,
      'resolvedBudget': resolvedBudget,
      'minimumPrice': minimumPrice,
      'contextPrompt': contextPrompt,
      'useAgeCalorieGuide': useAgeCalorieGuide,
      'pendingClarification': pendingClarification,
      'pendingAmount': pendingAmount,
    };
  }
}
