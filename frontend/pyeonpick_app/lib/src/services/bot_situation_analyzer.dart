import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_environment.dart';
import '../models/bot_message.dart';

class BotVotePreferences {
  const BotVotePreferences({
    this.sampleCount = 0,
    this.categoryWeights = const {},
  });

  factory BotVotePreferences.fromJson(Map<String, dynamic>? json) {
    return BotVotePreferences(
      sampleCount: (json?['sampleCount'] as num?)?.toInt() ?? 0,
      categoryWeights: ((json?['categoryWeights'] as Map?) ?? {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      ),
    );
  }

  final int sampleCount;
  final Map<String, double> categoryWeights;

  int score(Iterable<String> categories) {
    if (sampleCount == 0) return 0;
    final affinity = categories.toSet().fold<double>(
      0,
      (sum, category) => sum + (categoryWeights[category] ?? 0),
    );
    return (affinity * 3 * (sampleCount / 5).clamp(0, 1)).round().clamp(0, 6);
  }
}

class BotSituationContext {
  const BotSituationContext({
    required this.emotion,
    required this.lateNight,
    required this.wantedTastes,
    required this.avoidConditions,
    required this.summary,
    this.budget,
    this.timeAvailableMinutes,
    this.mealPurpose,
    this.bodyCondition,
    this.preferences = const BotVotePreferences(),
  });

  factory BotSituationContext.fromJson(Map<String, dynamic> json) {
    return BotSituationContext(
      emotion: json['emotion'] as String? ?? 'neutral',
      budget: (json['budget'] as num?)?.toInt(),
      timeAvailableMinutes: (json['timeAvailableMinutes'] as num?)?.toInt(),
      lateNight: json['lateNight'] as bool? ?? false,
      mealPurpose: json['mealPurpose'] as String?,
      bodyCondition: json['bodyCondition'] as String?,
      wantedTastes:
          (json['wantedTastes'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      avoidConditions:
          (json['avoidConditions'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      summary: json['summary'] as String? ?? '',
      preferences: BotVotePreferences.fromJson(
        json['preferences'] as Map<String, dynamic>?,
      ),
    );
  }

  final String emotion;
  final int? budget;
  final int? timeAvailableMinutes;
  final bool lateNight;
  final String? mealPurpose;
  final String? bodyCondition;
  final List<String> wantedTastes;
  final List<String> avoidConditions;
  final String summary;
  final BotVotePreferences preferences;
}

abstract final class BotSituationAnalyzer {
  static const _authTokenKey = 'pyeonpick_auth_token_v1';

  static Future<BotSituationContext?> analyze({
    required AppEnvironment environment,
    required String prompt,
    required List<String> memoryNotes,
  }) async {
    if (environment.dataMode != DataMode.remote) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_authTokenKey);
      if (token == null || token.isEmpty) return null;
      final response = await http
          .post(
            Uri.parse('${environment.apiBaseUrl}/bot/analyze'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{
              'prompt': prompt,
              'memoryNotes': memoryNotes.take(6).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return BotSituationContext.fromJson(
        payload['analysis'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> reply({
    required AppEnvironment environment,
    required String prompt,
    required List<BotMessage> history,
    required List<String> candidateIds,
    required String draft,
    int? maximumBudget,
    int? minimumPrice,
    String? pendingClarification,
  }) async {
    if (environment.dataMode != DataMode.remote) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_authTokenKey);
      if (token == null || token.isEmpty) return null;
      final response = await http
          .post(
            Uri.parse('${environment.apiBaseUrl}/bot/reply'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'prompt': prompt,
              'history': history.reversed
                  .take(10)
                  .toList()
                  .reversed
                  .map(
                    (message) => {'role': message.role, 'text': message.text},
                  )
                  .toList(),
              'candidateIds': candidateIds,
              'draft': draft,
              'maximumBudget': maximumBudget,
              'minimumPrice': minimumPrice,
              'pendingClarification': pendingClarification,
            }),
          )
          .timeout(const Duration(seconds: 22));
      if (response.statusCode != 200) return null;
      return (jsonDecode(response.body) as Map<String, dynamic>)['text']
          as String?;
    } catch (_) {
      return null;
    }
  }
}
