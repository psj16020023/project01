import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/core/app_environment.dart';
import 'package:pyeonpick_app/src/models/pyeon_user.dart';
import 'package:pyeonpick_app/src/services/local_account_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const environment = AppEnvironment(
    dataMode: DataMode.mock,
    apiBaseUrl: 'http://127.0.0.1:4173/api',
    mapTilerApiKey: '',
    mapTilerMapId: 'streets-v2',
  );

  test('mock signup survives store reload and supports sign in', () async {
    SharedPreferences.setMockInitialValues({});
    final firstStore = await LocalAccountStore.load(environment: environment);

    final created = await firstStore.signUp(
      nickname: '저장테스트',
      username: 'persist-user',
      password: 'safe-password',
    );
    expect((await firstStore.getCurrentUser())?.id, created.id);

    await firstStore.signOut();
    final reloadedStore = await LocalAccountStore.load(
      environment: environment,
    );
    final signedIn = await reloadedStore.signIn(
      username: 'persist-user',
      password: 'safe-password',
    );

    expect(signedIn.id, created.id);
    expect((await reloadedStore.getCurrentUser())?.nickname, '저장테스트');
  });

  test('mock 계정은 비밀번호 확인 후 완전히 삭제된다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalAccountStore.load(environment: environment);
    final created = await store.signUp(
      nickname: '삭제테스트',
      username: 'delete-user',
      password: 'safe-password',
    );

    await expectLater(
      store.deleteAccount(user: created, password: 'wrong-password'),
      throwsA(isA<StateError>()),
    );
    await store.deleteAccount(user: created, password: 'safe-password');

    expect(await store.getCurrentUser(), isNull);
    expect(store.getAccounts().where((user) => user.id == created.id), isEmpty);
  });

  test('age maps to the supplied one-meal calorie ranges', () {
    expect(MealCalorieRange.forAge(4)?.label, '450~550 kcal');
    expect(MealCalorieRange.forAge(8)?.label, '550~650 kcal');
    expect(MealCalorieRange.forAge(11)?.label, '650~750 kcal');
    expect(MealCalorieRange.forAge(14)?.label, '700~900 kcal');
    expect(MealCalorieRange.forAge(17)?.label, '700~950 kcal');
    expect(MealCalorieRange.forAge(25)?.label, '700~900 kcal');
    expect(MealCalorieRange.forAge(40)?.label, '650~850 kcal');
    expect(MealCalorieRange.forAge(60)?.label, '600~800 kcal');
    expect(MealCalorieRange.forAge(70)?.label, '550~750 kcal');
    expect(MealCalorieRange.forAge(3), isNull);
  });

  test('bot setup ignores legacy budget safely', () {
    final setup = BotSetup.fromJson({
      'age': 24,
      'budget': 6500,
      'tasteRatings': {'달달': 3, '매콤': 4, '새콤': 2, '짭짤': 5},
      'priorityValues': ['가성비', '시간절약'],
    });
    expect(setup.toJson().containsKey('budget'), isFalse);
  });

  test('legacy accounts without a stored gender repeat initial setup', () {
    final user = PyeonUser.fromJson({
      'id': 'legacy-user',
      'username': 'legacy-user',
      'nickname': '기존사용자',
      'botSetup': {
        'age': 24,
        'tasteRatings': {'달달': 3, '매콤': 4, '새콤': 2, '짭짤': 5},
        'priorityValues': ['가성비'],
      },
    });

    expect(user.botSetup, isNull);
  });
}
