import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'core/app_colors.dart';
import 'core/app_environment.dart';
import 'models/pyeon_user.dart';
import 'repositories/post_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/local_account_store.dart';

class PyeonPickApp extends StatefulWidget {
  const PyeonPickApp({super.key});

  @override
  State<PyeonPickApp> createState() => _PyeonPickAppState();
}

class _PyeonPickAppState extends State<PyeonPickApp> {
  late final AppEnvironment _environment;
  late final PostRepository _repository;
  LocalAccountStore? _accountStore;
  PyeonUser? _currentUser;
  String? _storageError;
  String? _storageWarning;

  @override
  void initState() {
    super.initState();
    _environment = AppEnvironment.fromDefines();
    _repository = createPostRepository(_environment);
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final store = await LocalAccountStore.load(environment: _environment);
      final user = await store.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _accountStore = store;
        _currentUser = user;
        _storageError = null;
        _storageWarning = store.storageWarning;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _storageError = error.toString());
    }
  }

  Future<void> _handleSignIn(String username, String password) async {
    final store = _accountStore!;
    final user = await store.signIn(username: username, password: password);
    if (!mounted) return;
    setState(() => _currentUser = user);
  }

  Future<void> _handleSignUp(
    String nickname,
    String username,
    String password,
  ) async {
    final store = _accountStore!;
    final user = await store.signUp(
      nickname: nickname,
      username: username,
      password: password,
    );
    if (!mounted) return;
    setState(() => _currentUser = user);
  }

  Future<void> _handleUserChanged(PyeonUser user) async {
    final store = _accountStore!;
    final previousUser = _currentUser;
    setState(() => _currentUser = user);
    try {
      await store.saveUser(user);
    } catch (_) {
      if (!mounted) return;
      setState(() => _currentUser = previousUser ?? user);
      rethrow;
    }
  }

  Future<void> _handleLogout() async {
    final store = _accountStore!;
    await store.signOut();
    if (!mounted) return;
    setState(() => _currentUser = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '편pick!',
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: const <PointerDeviceKind>{
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.trackpad,
        },
      ),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.lime,
          primary: AppColors.lime,
          secondary: AppColors.navy,
          surface: AppColors.receipt,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.receipt,
          foregroundColor: AppColors.ink,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: AppColors.receipt,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            side: const BorderSide(color: AppColors.line),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.receipt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final warning = _storageWarning;
        if (warning == null || _storageError != null) return content;
        return Stack(
          children: [
            content,
            Positioned(
              left: 12,
              right: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              child: _StorageWarningBanner(
                message: warning,
                onClose: () => setState(() => _storageWarning = null),
              ),
            ),
          ],
        );
      },
      home: _storageError != null
          ? _StorageErrorScreen(
              message: _storageError!,
              onRetry: () {
                setState(() => _storageError = null);
                _loadSession();
              },
            )
          : _accountStore == null
          ? const _SplashScreen()
          : _currentUser == null
          ? AuthScreen(onSignIn: _handleSignIn, onSignUp: _handleSignUp)
          : HomeScreen(
              repository: _repository,
              environment: _environment,
              currentUser: _currentUser!,
              onUserChanged: _handleUserChanged,
              onLogout: _handleLogout,
            ),
    );
  }
}

class _StorageWarningBanner extends StatelessWidget {
  const _StorageWarningBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7DB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE4C75F)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.navy,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: '닫기',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageErrorScreen extends StatelessWidget {
  const _StorageErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storage_rounded,
                  size: 44,
                  color: AppColors.navy,
                ),
                const SizedBox(height: 16),
                const Text(
                  '계정 저장소를 준비하지 못했어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF63788A),
                    fontWeight: FontWeight.w600,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.limeDeep)),
    );
  }
}
