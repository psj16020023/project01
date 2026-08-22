import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/combination_battle.dart';

class BattleStateStore {
  static const sharedBattleStateKey = 'pyeonpick_shared_battle_state_v5';
  static const _legacySharedBattleStateKey = 'pyeonpick_shared_battle_state_v4';

  static Future<CombinationBattleState> load({
    CombinationBattleState fallback = const CombinationBattleState(),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(sharedBattleStateKey) ??
        prefs.getString(_legacySharedBattleStateKey);
    if (raw == null || raw.isEmpty) return fallback;
    return CombinationBattleState.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  static Future<void> save(CombinationBattleState state) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(state.toJson());
    await prefs.setString(sharedBattleStateKey, encoded);
    await prefs.remove(_legacySharedBattleStateKey);
  }

  static Future<void> removeUser(String userId) async {
    final current = await load();
    final nextMatches = current.matches
        .where((match) => match.authorId != userId)
        .map((match) {
          return match.copyWith(
            leftVoterIds: match.leftVoterIds
                .where((id) => id != userId)
                .toList(),
            rightVoterIds: match.rightVoterIds
                .where((id) => id != userId)
                .toList(),
          );
        })
        .toList();
    await save(
      current.copyWith(
        matches: nextMatches,
        notifiedExpiredMatchIds: current.notifiedExpiredMatchIds
            .where(nextMatches.map((match) => match.id).toSet().contains)
            .toList(),
        todayEndedSummarySeenMatchIds: current.todayEndedSummarySeenMatchIds
            .where(nextMatches.map((match) => match.id).toSet().contains)
            .toList(),
      ),
    );
  }
}
