class BattleResultEntry {
  const BattleResultEntry({
    required this.id,
    required this.title,
    required this.endsAt,
    required this.leftTitle,
    required this.rightTitle,
    required this.leftVotes,
    required this.rightVotes,
    required this.unread,
    this.leftImageUrl,
    this.rightImageUrl,
  });

  factory BattleResultEntry.fromJson(Map<String, dynamic> json) =>
      BattleResultEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        endsAt: DateTime.parse(json['endsAt'] as String).toLocal(),
        leftTitle: json['leftTitle'] as String,
        rightTitle: json['rightTitle'] as String,
        leftVotes: (json['leftVotes'] as num).toInt(),
        rightVotes: (json['rightVotes'] as num).toInt(),
        unread: json['unread'] == true,
        leftImageUrl: json['leftImageUrl'] as String?,
        rightImageUrl: json['rightImageUrl'] as String?,
      );

  final String id;
  final String title;
  final DateTime endsAt;
  final String leftTitle;
  final String rightTitle;
  final int leftVotes;
  final int rightVotes;
  final bool unread;
  final String? leftImageUrl;
  final String? rightImageUrl;

  String get outcome {
    if (leftVotes + rightVotes == 0) return '투표 없이 종료';
    if (leftVotes == rightVotes) return '무승부';
    return '${leftVotes > rightVotes ? leftTitle : rightTitle} 승리';
  }
}

class BattleResultsPage {
  const BattleResultsPage({
    this.results = const [],
    this.refreshAfter = const Duration(seconds: 15),
  });

  factory BattleResultsPage.fromJson(Map<String, dynamic> json) =>
      BattleResultsPage(
        results: (json['results'] as List<dynamic>)
            .map(
              (item) =>
                  BattleResultEntry.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        refreshAfter: Duration(
          milliseconds: ((json['refreshAfterMs'] as num?)?.toInt() ?? 15000)
              .clamp(300, 15000),
        ),
      );

  final List<BattleResultEntry> results;
  final Duration refreshAfter;
}
