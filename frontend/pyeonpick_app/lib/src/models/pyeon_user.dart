import 'bot_message.dart';
import 'bot_conversation.dart';
import 'combination_battle.dart';

class MealCalorieRange {
  const MealCalorieRange({
    required this.ageLabel,
    required this.minCalories,
    required this.maxCalories,
  });

  final String ageLabel;
  final int minCalories;
  final int maxCalories;

  String get label => '$minCalories~$maxCalories kcal';

  static MealCalorieRange? forAge(int age) {
    if (age < 4) return null;
    if (age <= 6) {
      return const MealCalorieRange(
        ageLabel: '4~6세',
        minCalories: 450,
        maxCalories: 550,
      );
    }
    if (age <= 9) {
      return const MealCalorieRange(
        ageLabel: '7~9세',
        minCalories: 550,
        maxCalories: 650,
      );
    }
    if (age <= 12) {
      return const MealCalorieRange(
        ageLabel: '10~12세',
        minCalories: 650,
        maxCalories: 750,
      );
    }
    if (age <= 15) {
      return const MealCalorieRange(
        ageLabel: '13~15세',
        minCalories: 700,
        maxCalories: 900,
      );
    }
    if (age <= 18) {
      return const MealCalorieRange(
        ageLabel: '16~18세',
        minCalories: 700,
        maxCalories: 950,
      );
    }
    if (age <= 29) {
      return const MealCalorieRange(
        ageLabel: '19~29세',
        minCalories: 700,
        maxCalories: 900,
      );
    }
    if (age <= 49) {
      return const MealCalorieRange(
        ageLabel: '30~49세',
        minCalories: 650,
        maxCalories: 850,
      );
    }
    if (age <= 64) {
      return const MealCalorieRange(
        ageLabel: '50~64세',
        minCalories: 600,
        maxCalories: 800,
      );
    }
    return const MealCalorieRange(
      ageLabel: '65세 이상',
      minCalories: 550,
      maxCalories: 750,
    );
  }
}

class BotSetup {
  const BotSetup({
    required this.age,
    required this.gender,
    required this.tasteRatings,
    required this.priorityValues,
  });

  factory BotSetup.fromJson(Map<String, dynamic> json) {
    final legacyTastes =
        (json['favoriteTastes'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toSet();
    final rawRatings = json['tasteRatings'] as Map<String, dynamic>?;
    final legacyReasons =
        (json['reasons'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .map((item) {
              if (item == '건강') return '저칼로리';
              if (item == '절약(가성비)') return '가성비';
              if (item == '맛') return '호불호';
              return item;
            })
            .toList();
    return BotSetup(
      age: json['age'] as int? ?? 20,
      gender: json['gender'] as String? ?? '여자',
      tasteRatings: <String, int>{
        for (final taste in const <String>['달달', '매콤', '새콤', '짭짤'])
          taste:
              (rawRatings?[taste] as num?)?.toInt().clamp(1, 5) ??
              (legacyTastes.contains(taste) ||
                      (taste == '새콤' && legacyTastes.contains('신'))
                  ? 5
                  : 3),
      },
      priorityValues:
          (json['priorityValues'] as List<dynamic>? ?? legacyReasons)
              .map((item) => item.toString())
              .where(
                const <String>['저칼로리', '가성비', '시간절약', '호불호', '트렌드'].contains,
              )
              .take(2)
              .toList(),
    );
  }

  final int age;
  final String gender;
  final Map<String, int> tasteRatings;
  final List<String> priorityValues;

  List<String> get favoriteTastes => tasteRatings.entries
      .where((entry) => entry.value >= 4)
      .map((entry) => entry.key)
      .toList();

  List<String> get reasons => priorityValues;
  MealCalorieRange? get mealCalorieRange => MealCalorieRange.forAge(age);

  int tasteLevel(String taste) => tasteRatings[taste] ?? 3;

  Map<String, dynamic> toJson() {
    return {
      'age': age,
      'gender': gender,
      'tasteRatings': tasteRatings,
      'priorityValues': priorityValues,
    };
  }
}

class ProfileVisibility {
  const ProfileVisibility({
    this.username = false,
    this.likes = true,
    this.dislikes = false,
    this.saved = false,
    this.myPosts = true,
    this.picks = true,
    this.pickedBy = true,
  });

  factory ProfileVisibility.fromJson(Map<String, dynamic>? json) {
    return ProfileVisibility(
      username: json?['username'] as bool? ?? false,
      likes: json?['likes'] as bool? ?? true,
      dislikes: json?['dislikes'] as bool? ?? false,
      saved: json?['saved'] as bool? ?? false,
      myPosts: json?['myPosts'] as bool? ?? true,
      picks: json?['picks'] as bool? ?? true,
      pickedBy: json?['pickedBy'] as bool? ?? true,
    );
  }

  final bool username;
  final bool likes;
  final bool dislikes;
  final bool saved;
  final bool myPosts;
  final bool picks;
  final bool pickedBy;

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'likes': likes,
      'dislikes': dislikes,
      'saved': saved,
      'myPosts': myPosts,
      'picks': picks,
      'pickedBy': pickedBy,
    };
  }

  ProfileVisibility copyWith({
    bool? username,
    bool? likes,
    bool? dislikes,
    bool? saved,
    bool? myPosts,
    bool? picks,
    bool? pickedBy,
  }) {
    return ProfileVisibility(
      username: username ?? this.username,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      saved: saved ?? this.saved,
      myPosts: myPosts ?? this.myPosts,
      picks: picks ?? this.picks,
      pickedBy: pickedBy ?? this.pickedBy,
    );
  }
}

class PyeonUser {
  const PyeonUser({
    required this.id,
    required this.username,
    required this.password,
    required this.nickname,
    this.profileImageUrl,
    this.botSetup,
    this.memoryNotes = const <String>[],
    this.botMessages = const <BotMessage>[],
    this.archivedConversations = const <BotConversation>[],
    this.likedPostIds = const <String>[],
    this.dislikedPostIds = const <String>[],
    this.savedPostIds = const <String>[],
    this.pickedAuthorIds = const <String>[],
    this.battleState = const CombinationBattleState(),
    this.selectedCommunityTitleKey,
    this.profilePublic = true,
    this.profileVisibility = const ProfileVisibility(),
    this.pickedByCount = 0,
  });

  factory PyeonUser.fromJson(Map<String, dynamic> json) {
    final botSetupJson = json['botSetup'] as Map<String, dynamic>?;
    final storedGender = botSetupJson?['gender'] as String?;
    final hasValidGender = storedGender == '남자' || storedGender == '여자';
    return PyeonUser(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      profileImageUrl: json['profileImageUrl'] as String?,
      botSetup: botSetupJson == null || !hasValidGender
          ? null
          : BotSetup.fromJson(botSetupJson),
      memoryNotes: (json['memoryNotes'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      botMessages: (json['botMessages'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => BotMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
      archivedConversations:
          (json['archivedConversations'] as List<dynamic>? ?? const <dynamic>[])
              .map(
                (item) =>
                    BotConversation.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      likedPostIds:
          (json['likedPostIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      dislikedPostIds:
          (json['dislikedPostIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      savedPostIds:
          (json['savedPostIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      pickedAuthorIds:
          (json['pickedAuthorIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      battleState: CombinationBattleState.fromJson(
        json['battleState'] as Map<String, dynamic>?,
      ),
      selectedCommunityTitleKey: json['selectedCommunityTitleKey'] as String?,
      profilePublic: json['profilePublic'] as bool? ?? true,
      profileVisibility: ProfileVisibility.fromJson(
        json['profileVisibility'] as Map<String, dynamic>?,
      ),
      pickedByCount: json['pickedByCount'] as int? ?? 0,
    );
  }

  final String id;
  final String username;
  final String password;
  final String nickname;
  final String? profileImageUrl;
  final BotSetup? botSetup;
  final List<String> memoryNotes;
  final List<BotMessage> botMessages;
  final List<BotConversation> archivedConversations;
  final List<String> likedPostIds;
  final List<String> dislikedPostIds;
  final List<String> savedPostIds;
  final List<String> pickedAuthorIds;
  final CombinationBattleState battleState;
  final String? selectedCommunityTitleKey;
  final bool profilePublic;
  final ProfileVisibility profileVisibility;
  final int pickedByCount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'nickname': nickname,
      'profileImageUrl': profileImageUrl,
      'botSetup': botSetup?.toJson(),
      'memoryNotes': memoryNotes,
      'botMessages': botMessages.map((message) => message.toJson()).toList(),
      'archivedConversations': archivedConversations
          .map((conversation) => conversation.toJson())
          .toList(),
      'likedPostIds': likedPostIds,
      'dislikedPostIds': dislikedPostIds,
      'savedPostIds': savedPostIds,
      'pickedAuthorIds': pickedAuthorIds,
      'battleState': battleState.toJson(),
      'selectedCommunityTitleKey': selectedCommunityTitleKey,
      'profilePublic': profilePublic,
      'profileVisibility': profileVisibility.toJson(),
      'pickedByCount': pickedByCount,
    };
  }

  PyeonUser copyWith({
    String? id,
    String? username,
    String? password,
    String? nickname,
    String? profileImageUrl,
    bool clearProfileImage = false,
    BotSetup? botSetup,
    bool clearBotSetup = false,
    List<String>? memoryNotes,
    List<BotMessage>? botMessages,
    List<BotConversation>? archivedConversations,
    List<String>? likedPostIds,
    List<String>? dislikedPostIds,
    List<String>? savedPostIds,
    List<String>? pickedAuthorIds,
    CombinationBattleState? battleState,
    String? selectedCommunityTitleKey,
    bool clearSelectedCommunityTitleKey = false,
    bool? profilePublic,
    ProfileVisibility? profileVisibility,
    int? pickedByCount,
  }) {
    return PyeonUser(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      nickname: nickname ?? this.nickname,
      profileImageUrl: clearProfileImage
          ? null
          : (profileImageUrl ?? this.profileImageUrl),
      botSetup: clearBotSetup ? null : (botSetup ?? this.botSetup),
      memoryNotes: memoryNotes ?? this.memoryNotes,
      botMessages: botMessages ?? this.botMessages,
      archivedConversations:
          archivedConversations ?? this.archivedConversations,
      likedPostIds: likedPostIds ?? this.likedPostIds,
      dislikedPostIds: dislikedPostIds ?? this.dislikedPostIds,
      savedPostIds: savedPostIds ?? this.savedPostIds,
      pickedAuthorIds: pickedAuthorIds ?? this.pickedAuthorIds,
      battleState: battleState ?? this.battleState,
      selectedCommunityTitleKey: clearSelectedCommunityTitleKey
          ? null
          : (selectedCommunityTitleKey ?? this.selectedCommunityTitleKey),
      profilePublic: profilePublic ?? this.profilePublic,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      pickedByCount: pickedByCount ?? this.pickedByCount,
    );
  }
}
