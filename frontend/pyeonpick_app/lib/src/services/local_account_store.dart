import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_environment.dart';
import '../models/pyeon_user.dart';
import 'battle_state_store.dart';
import 'account_string_store.dart';
import 'browser_account_string_store.dart';

class LocalAccountStore {
  LocalAccountStore._(
    this._store, {
    required this.environment,
    this.storageWarning,
  });

  static const _accountsKey = 'pyeonpick_accounts_v1';
  static const _currentUserIdKey = 'pyeonpick_current_user_id_v1';
  static const _cachedCurrentUserKey = 'pyeonpick_cached_current_user_v1';
  static const _authTokenKey = 'pyeonpick_auth_token_v1';
  static const _storageProbeKey = 'pyeonpick_account_store_probe_v1';

  final AccountStringStore _store;
  final AppEnvironment environment;
  final String? storageWarning;

  bool get _usesRemoteAuth => environment.dataMode == DataMode.remote;

  static Future<LocalAccountStore> load({
    required AppEnvironment environment,
  }) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          const Duration(seconds: 4),
        );
        final store = SharedPreferencesAccountStringStore(prefs);
        await _verifyStore(store);
        return LocalAccountStore._(store, environment: environment);
      } catch (_) {
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }

    final browserStore = await createBrowserAccountStringStore();
    if (browserStore != null) {
      try {
        await _verifyStore(browserStore);
        return LocalAccountStore._(browserStore, environment: environment);
      } catch (_) {
        // Continue to the explicit temporary store below.
      }
    }

    return LocalAccountStore._(
      MemoryAccountStringStore(),
      environment: environment,
      storageWarning:
          '브라우저 저장소를 열지 못해 이번 실행 동안만 계정이 저장돼요. 시크릿 모드나 저장소 권한을 확인하면 새로고침 후에도 유지됩니다.',
    );
  }

  static Future<void> _verifyStore(AccountStringStore store) async {
    const probeValue = 'ok';
    final written = await store.setString(_storageProbeKey, probeValue);
    final verified = written && store.getString(_storageProbeKey) == probeValue;
    await store.remove(_storageProbeKey);
    if (!verified) {
      throw const StorageUnavailableException('브라우저 저장소에 쓰기 테스트를 완료하지 못했어요.');
    }
  }

  List<PyeonUser> getAccounts() {
    final raw = _store.getString(_accountsKey);
    if ((raw == null || raw.isEmpty) && !_usesRemoteAuth) {
      return List<PyeonUser>.from(_defaultMockAccounts);
    }
    if (raw == null || raw.isEmpty) return <PyeonUser>[];
    final items = jsonDecode(raw) as List<dynamic>;
    return items
        .map((item) => PyeonUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveAccounts(List<PyeonUser> accounts) async {
    final encoded = jsonEncode(
      accounts.map((account) => account.toJson()).toList(),
    );
    await _writeAndVerify(_accountsKey, encoded);
  }

  Future<void> _cacheCurrentUser(PyeonUser user) async {
    await _writeAndVerify(_cachedCurrentUserKey, jsonEncode(user.toJson()));
    await _writeAndVerify(_currentUserIdKey, user.id);
  }

  PyeonUser? _getCachedCurrentUser() {
    final raw = _store.getString(_cachedCurrentUserKey);
    if (raw == null || raw.isEmpty) return null;
    return PyeonUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  PyeonUser _mergePassword({required PyeonUser fresh, PyeonUser? fallback}) {
    final preservedPassword = fresh.password.isNotEmpty
        ? fresh.password
        : (fallback?.password ?? _getCachedCurrentUser()?.password ?? '');
    return fresh.copyWith(password: preservedPassword);
  }

  Future<PyeonUser?> getCurrentUser() async {
    final currentUserId = _store.getString(_currentUserIdKey);
    if (currentUserId == null) return null;

    if (!_usesRemoteAuth) {
      for (final account in getAccounts()) {
        if (account.id == currentUserId) return account;
      }
      return null;
    }

    final token = _store.getString(_authTokenKey);
    if (token == null || token.isEmpty) {
      await signOut();
      return null;
    }

    final cached = _getCachedCurrentUser();
    try {
      final response = await http
          .get(
            Uri.parse('${environment.apiBaseUrl}/users/$currentUserId'),
            headers: _authorizedHeaders(),
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final user = _mergePassword(
          fresh: PyeonUser.fromJson(json['user'] as Map<String, dynamic>),
          fallback: cached,
        );
        await _cacheCurrentUser(user);
        return user;
      }
      if (response.statusCode == 404) {
        await signOut();
        return null;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        await signOut();
        return null;
      }
    } catch (_) {
      // Fall back to the locally cached session snapshot when offline.
    }
    return cached;
  }

  Future<PyeonUser> signUp({
    required String nickname,
    required String username,
    required String password,
  }) async {
    if (!_usesRemoteAuth) {
      final accounts = getAccounts();
      final normalizedNickname = nickname.trim();
      final normalizedUsername = username.trim();

      if (accounts.any((account) => account.nickname == normalizedNickname)) {
        throw StateError('이미 사용 중인 닉네임이에요.');
      }
      if (accounts.any((account) => account.username == normalizedUsername)) {
        throw StateError('이미 사용 중인 아이디예요.');
      }

      final created = PyeonUser(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        username: normalizedUsername,
        password: password,
        nickname: normalizedNickname,
      );

      await _saveAccounts([...accounts, created]);
      await _cacheCurrentUser(created);
      return created;
    }

    final response = await http
        .post(
          Uri.parse('${environment.apiBaseUrl}/auth/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'nickname': nickname.trim(),
            'username': username.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 201) {
      final message = _extractMessage(response.body, '회원가입에 실패했어요.');
      throw StateError(message);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final user = PyeonUser.fromJson(
      json['user'] as Map<String, dynamic>,
    ).copyWith(password: password);
    await _storeAuthToken(json['token'] as String?);
    await _cacheCurrentUser(user);
    return user;
  }

  Future<PyeonUser> signIn({
    required String username,
    required String password,
  }) async {
    if (!_usesRemoteAuth) {
      final accounts = getAccounts();
      final loginKey = username.trim();
      PyeonUser? account;
      for (final item in accounts) {
        if (item.username == loginKey || item.nickname == loginKey) {
          account = item;
          break;
        }
      }

      if (account == null || account.password != password) {
        throw StateError('아이디 또는 비밀번호가 맞지 않아요.');
      }

      await _cacheCurrentUser(account);
      return account;
    }

    final response = await http
        .post(
          Uri.parse('${environment.apiBaseUrl}/auth/signin'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      final message = _extractMessage(response.body, '로그인에 실패했어요.');
      throw StateError(message);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final user = PyeonUser.fromJson(
      json['user'] as Map<String, dynamic>,
    ).copyWith(password: password);
    await _storeAuthToken(json['token'] as String?);
    await _cacheCurrentUser(user);
    return user;
  }

  Future<void> saveUser(PyeonUser user) async {
    if (!_usesRemoteAuth) {
      final accounts = getAccounts();
      final next = accounts
          .map((account) => account.id == user.id ? user : account)
          .toList();
      await _saveAccounts(next);
      await _writeAndVerify(_currentUserIdKey, user.id);
      await _writeAndVerify(_cachedCurrentUserKey, jsonEncode(user.toJson()));
      return;
    }

    final response = await http
        .put(
          Uri.parse('${environment.apiBaseUrl}/users/${user.id}'),
          headers: _authorizedHeaders(contentType: true),
          body: jsonEncode({
            'nickname': user.nickname,
            'profileImageUrl': user.profileImageUrl,
            'botSetup': user.botSetup?.toJson(),
            'memoryNotes': user.memoryNotes,
            'botMessages': user.botMessages
                .map((message) => message.toJson())
                .toList(),
            'archivedConversations': user.archivedConversations
                .map((conversation) => conversation.toJson())
                .toList(),
            'likedPostIds': user.likedPostIds,
            'dislikedPostIds': user.dislikedPostIds,
            'savedPostIds': user.savedPostIds,
            'pickedAuthorIds': user.pickedAuthorIds,
            'battleState': user.battleState.toJson(),
            'profilePublic': user.profilePublic,
            'profileVisibility': user.profileVisibility.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        await signOut();
        throw StateError('로그인이 만료됐어요. 다시 로그인해 주세요.');
      }
      final message = _extractMessage(response.body, '사용자 정보를 저장하지 못했어요.');
      throw StateError(message);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final saved = _mergePassword(
      fresh: PyeonUser.fromJson(json['user'] as Map<String, dynamic>),
      fallback: user,
    );
    await _cacheCurrentUser(saved);
  }

  Future<void> signOut() async {
    await _store.remove(_currentUserIdKey);
    await _store.remove(_cachedCurrentUserKey);
    await _store.remove(_authTokenKey);
  }

  Future<void> deleteAccount({
    required PyeonUser user,
    required String password,
  }) async {
    if (password.isEmpty) throw StateError('비밀번호를 입력해 주세요.');

    if (!_usesRemoteAuth) {
      if (user.password != password) {
        throw StateError('비밀번호가 맞지 않아요.');
      }
      await _saveAccounts(
        getAccounts().where((account) => account.id != user.id).toList(),
      );
    } else {
      final response = await http
          .delete(
            Uri.parse('${environment.apiBaseUrl}/users/${user.id}'),
            headers: _authorizedHeaders(contentType: true),
            body: jsonEncode(<String, dynamic>{'password': password}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        final message = _extractMessage(response.body, '계정을 삭제하지 못했어요.');
        throw StateError(message);
      }
    }

    await BattleStateStore.removeUser(user.id);
    await signOut();
  }

  Future<void> _storeAuthToken(String? token) async {
    if (token == null || token.isEmpty) {
      throw StateError('서버에서 로그인 토큰을 받지 못했어요.');
    }
    await _writeAndVerify(_authTokenKey, token);
  }

  Map<String, String> _authorizedHeaders({bool contentType = false}) {
    final token = _store.getString(_authTokenKey);
    return <String, String>{
      if (contentType) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _writeAndVerify(String key, String value) async {
    final written = await _store.setString(key, value);
    if (!written || _store.getString(key) != value) {
      throw StorageUnavailableException(
        '계정 정보를 기기에 저장하지 못했어요. 브라우저 저장 공간과 개인정보 보호 설정을 확인해 주세요.',
      );
    }
  }

  String _extractMessage(String body, String fallback) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final message = json['message'] as String?;
      return message == null || message.isEmpty ? fallback : message;
    } catch (_) {
      return fallback;
    }
  }
}

class StorageUnavailableException implements Exception {
  const StorageUnavailableException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final List<PyeonUser> _defaultMockAccounts = <PyeonUser>[
  const PyeonUser(
    id: 'demo-user-1',
    username: 'demo',
    password: '1234',
    nickname: '체험용계정',
  ),
  const PyeonUser(
    id: 'demo-user-2',
    username: 'test',
    password: '1111',
    nickname: '테스트유저',
  ),
];
