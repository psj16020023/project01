import 'package:intl/intl.dart';

enum BattleVoteSide { left, right }

class BattleMatchEntry {
  const BattleMatchEntry({
    required this.id,
    required this.title,
    required this.authorId,
    required this.authorNickname,
    required this.leftPostId,
    required this.rightPostId,
    required this.createdAt,
    required this.leftColorValue,
    required this.rightColorValue,
    this.endsAt,
    this.requiredTitleKey,
    this.leftCustomTitle,
    this.rightCustomTitle,
    this.leftCustomImageUrl,
    this.rightCustomImageUrl,
    this.leftVoterIds = const <String>[],
    this.rightVoterIds = const <String>[],
    this.leftVoteCount,
    this.rightVoteCount,
    this.viewerVoteSide,
  });

  factory BattleMatchEntry.fromJson(Map<String, dynamic> json) {
    return BattleMatchEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '제목 없는 조합 대결',
      authorId: json['authorId'] as String? ?? '',
      authorNickname: json['authorNickname'] as String? ?? '익명',
      leftPostId: json['leftPostId'] as String? ?? '',
      rightPostId: json['rightPostId'] as String? ?? '',
      leftColorValue: json['leftColorValue'] as int? ?? 0xFFC91F2D,
      rightColorValue: json['rightColorValue'] as int? ?? 0xFF2E68D3,
      endsAt: DateTime.tryParse(json['endsAt'] as String? ?? ''),
      requiredTitleKey: json['requiredTitleKey'] as String?,
      leftCustomTitle: json['leftCustomTitle'] as String?,
      rightCustomTitle: json['rightCustomTitle'] as String?,
      leftCustomImageUrl: json['leftCustomImageUrl'] as String?,
      rightCustomImageUrl: json['rightCustomImageUrl'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      leftVoterIds:
          (json['leftVoterIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      rightVoterIds:
          (json['rightVoterIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      leftVoteCount: json['leftVotes'] as int?,
      rightVoteCount: json['rightVotes'] as int?,
      viewerVoteSide: switch (json['viewerVoteSide']) {
        'left' => BattleVoteSide.left,
        'right' => BattleVoteSide.right,
        _ => null,
      },
    );
  }

  final String id;
  final String title;
  final String authorId;
  final String authorNickname;
  final String leftPostId;
  final String rightPostId;
  final int leftColorValue;
  final int rightColorValue;
  final DateTime? endsAt;
  final String? requiredTitleKey;
  final String? leftCustomTitle;
  final String? rightCustomTitle;
  final String? leftCustomImageUrl;
  final String? rightCustomImageUrl;
  final DateTime createdAt;
  final List<String> leftVoterIds;
  final List<String> rightVoterIds;
  final int? leftVoteCount;
  final int? rightVoteCount;
  final BattleVoteSide? viewerVoteSide;

  int get leftVotes => leftVoteCount ?? leftVoterIds.length;
  int get rightVotes => rightVoteCount ?? rightVoterIds.length;
  int get totalVotes => leftVotes + rightVotes;
  String get createdAtLabel => DateFormat('yyyy.MM.dd').format(createdAt);
  String get endsAtLabel => endsAt == null
      ? '시간 제한 없음'
      : DateFormat('yyyy.MM.dd HH:mm').format(endsAt!);
  bool get isExpired => endsAt != null && !endsAt!.isAfter(DateTime.now());
  bool get usesCustomLeft => (leftCustomTitle?.trim().isNotEmpty ?? false);
  bool get usesCustomRight => (rightCustomTitle?.trim().isNotEmpty ?? false);

  BattleVoteSide? get winnerSide {
    if (leftVotes == rightVotes) return null;
    return leftVotes > rightVotes ? BattleVoteSide.left : BattleVoteSide.right;
  }

  BattleVoteSide? voteSideOf(String userId) {
    if (viewerVoteSide != null) return viewerVoteSide;
    if (leftVoterIds.contains(userId)) return BattleVoteSide.left;
    if (rightVoterIds.contains(userId)) return BattleVoteSide.right;
    return null;
  }

  BattleMatchEntry castVote(String userId, BattleVoteSide side) {
    if (userId.isEmpty || isExpired || voteSideOf(userId) != null) return this;

    final left = leftVoterIds.toSet();
    final right = rightVoterIds.toSet();
    if (side == BattleVoteSide.left) {
      left.add(userId);
    } else {
      right.add(userId);
    }
    return copyWith(
      leftVoterIds: left.toList(),
      rightVoterIds: right.toList(),
      leftVoteCount: side == BattleVoteSide.left ? leftVotes + 1 : leftVotes,
      rightVoteCount: side == BattleVoteSide.right
          ? rightVotes + 1
          : rightVotes,
      viewerVoteSide: side,
    );
  }

  BattleMatchEntry copyWith({
    String? title,
    int? leftColorValue,
    int? rightColorValue,
    DateTime? endsAt,
    String? requiredTitleKey,
    String? leftCustomTitle,
    String? rightCustomTitle,
    String? leftCustomImageUrl,
    String? rightCustomImageUrl,
    bool clearRequiredTitleKey = false,
    List<String>? leftVoterIds,
    List<String>? rightVoterIds,
    int? leftVoteCount,
    int? rightVoteCount,
    BattleVoteSide? viewerVoteSide,
  }) {
    return BattleMatchEntry(
      id: id,
      title: title ?? this.title,
      authorId: authorId,
      authorNickname: authorNickname,
      leftPostId: leftPostId,
      rightPostId: rightPostId,
      leftColorValue: leftColorValue ?? this.leftColorValue,
      rightColorValue: rightColorValue ?? this.rightColorValue,
      endsAt: endsAt ?? this.endsAt,
      requiredTitleKey: clearRequiredTitleKey
          ? null
          : (requiredTitleKey ?? this.requiredTitleKey),
      leftCustomTitle: leftCustomTitle ?? this.leftCustomTitle,
      rightCustomTitle: rightCustomTitle ?? this.rightCustomTitle,
      leftCustomImageUrl: leftCustomImageUrl ?? this.leftCustomImageUrl,
      rightCustomImageUrl: rightCustomImageUrl ?? this.rightCustomImageUrl,
      createdAt: createdAt,
      leftVoterIds: leftVoterIds ?? this.leftVoterIds,
      rightVoterIds: rightVoterIds ?? this.rightVoterIds,
      leftVoteCount: leftVoteCount ?? this.leftVoteCount,
      rightVoteCount: rightVoteCount ?? this.rightVoteCount,
      viewerVoteSide: viewerVoteSide ?? this.viewerVoteSide,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'authorId': authorId,
    'authorNickname': authorNickname,
    'leftPostId': leftPostId,
    'rightPostId': rightPostId,
    'leftColorValue': leftColorValue,
    'rightColorValue': rightColorValue,
    'endsAt': endsAt?.toIso8601String(),
    'requiredTitleKey': requiredTitleKey,
    'leftCustomTitle': leftCustomTitle,
    'rightCustomTitle': rightCustomTitle,
    'leftCustomImageUrl': leftCustomImageUrl,
    'rightCustomImageUrl': rightCustomImageUrl,
    'createdAt': createdAt.toIso8601String(),
    'leftVoterIds': leftVoterIds,
    'rightVoterIds': rightVoterIds,
    'leftVotes': leftVotes,
    'rightVotes': rightVotes,
    'viewerVoteSide': viewerVoteSide?.name,
  };
}

class CombinationBattleState {
  const CombinationBattleState({
    this.matches = const <BattleMatchEntry>[],
    this.notifiedExpiredMatchIds = const <String>[],
    this.todayEndedSummarySeenMatchIds = const <String>[],
  });

  factory CombinationBattleState.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CombinationBattleState();
    return CombinationBattleState(
      matches: (json['matches'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (item) => BattleMatchEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      notifiedExpiredMatchIds:
          (json['notifiedExpiredMatchIds'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      todayEndedSummarySeenMatchIds:
          (json['todayEndedSummarySeenMatchIds'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
    );
  }

  final List<BattleMatchEntry> matches;
  final List<String> notifiedExpiredMatchIds;
  final List<String> todayEndedSummarySeenMatchIds;

  bool get isEmpty => matches.isEmpty;

  CombinationBattleState copyWith({
    List<BattleMatchEntry>? matches,
    List<String>? notifiedExpiredMatchIds,
    List<String>? todayEndedSummarySeenMatchIds,
  }) {
    return CombinationBattleState(
      matches: matches ?? this.matches,
      notifiedExpiredMatchIds:
          notifiedExpiredMatchIds ?? this.notifiedExpiredMatchIds,
      todayEndedSummarySeenMatchIds:
          todayEndedSummarySeenMatchIds ?? this.todayEndedSummarySeenMatchIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'matches': matches.map((match) => match.toJson()).toList(),
    'notifiedExpiredMatchIds': notifiedExpiredMatchIds,
    'todayEndedSummarySeenMatchIds': todayEndedSummarySeenMatchIds,
  };
}
