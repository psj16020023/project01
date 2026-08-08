import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_environment.dart';

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
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return BotSituationContext.fromJson(
        payload['analysis'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
