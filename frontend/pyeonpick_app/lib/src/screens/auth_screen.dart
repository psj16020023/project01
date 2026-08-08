import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onSignIn, required this.onSignUp});

  final Future<void> Function(String username, String password) onSignIn;
  final Future<void> Function(String nickname, String username, String password)
  onSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nicknameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _signupMode = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nicknameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nickname = _nicknameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (_signupMode && nickname.isEmpty) {
      setState(() => _error = '닉네임을 입력해 주세요.');
      return;
    }
    if (username.isEmpty) {
      setState(
        () => _error = _signupMode ? '아이디를 입력해 주세요.' : '아이디 또는 닉네임을 입력해 주세요.',
      );
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '비밀번호를 입력해 주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_signupMode) {
        await widget.onSignUp(nickname, username, password);
      } else {
        await widget.onSignIn(username, password);
      }
    } catch (error) {
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEAF8FF), Colors.white, Color(0xFFF4FBE8)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  decoration: BoxDecoration(
                    color: AppColors.receipt,
                    borderRadius: BorderRadius.circular(AppColors.radiusLarge),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 11,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8F7C8),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppColors.radiusLarge - 1),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Text(
                              'PYEONPICK MARKET',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                                fontSize: 12,
                              ),
                            ),
                            Spacer(),
                            Text(
                              '24H',
                              style: TextStyle(
                                color: AppColors.limeDeep,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        '편pick!',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 38,
                          letterSpacing: -1.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _signupMode
                            ? '닉네임, 아이디, 비밀번호를 정해서 바로 시작해요.'
                            : '로그인하고 편봇과 조합 공유를 이어서 사용해요.',
                        style: const TextStyle(
                          color: Color(0xFF698093),
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _ModeToggle(
                        signupMode: _signupMode,
                        onChanged: (value) => setState(() {
                          _signupMode = value;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6FBFF),
                          borderRadius: BorderRadius.circular(
                            AppColors.radiusSmall,
                          ),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: const Text(
                          '바로 테스트하려면 아이디 `demo` / 비밀번호 `1234` 또는 아이디 `test` / 비밀번호 `1111`로 로그인할 수 있어요.',
                          style: TextStyle(
                            color: Color(0xFF607C95),
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_signupMode) ...[
                        _AuthField(
                          key: const ValueKey('signup-nickname'),
                          controller: _nicknameController,
                          label: '닉네임',
                          hint: '중복되지 않는 닉네임',
                        ),
                        const SizedBox(height: 12),
                      ],
                      _AuthField(
                        key: ValueKey(
                          _signupMode ? 'signup-username' : 'signin-username',
                        ),
                        controller: _usernameController,
                        label: _signupMode ? '아이디' : '아이디 또는 닉네임',
                        hint: _signupMode ? '로그인에 사용할 아이디' : '아이디나 닉네임 입력',
                      ),
                      const SizedBox(height: 12),
                      _AuthField(
                        key: ValueKey(
                          _signupMode ? 'signup-password' : 'signin-password',
                        ),
                        controller: _passwordController,
                        label: '비밀번호',
                        hint: '비밀번호 입력',
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFD43D3D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.lime,
                            foregroundColor: AppColors.ink,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppColors.radiusMedium,
                              ),
                            ),
                          ),
                          child: Text(
                            _submitting
                                ? '처리 중...'
                                : _signupMode
                                ? '회원가입'
                                : '로그인',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.signupMode, required this.onChanged});

  final bool signupMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleChip(
              label: '로그인',
              active: !signupMode,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ToggleChip(
              label: '회원가입',
              active: signupMode,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.lime : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.ink : const Color(0xFF7A8EA1),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatefulWidget {
  const _AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(covariant _AuthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.obscureText) {
      _obscured = false;
    } else if (!oldWidget.obscureText && widget.obscureText) {
      _obscured = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          obscureText: widget.obscureText ? _obscured : false,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(
              color: Color(0xFFB7C0CA),
              fontWeight: FontWeight.w600,
            ),
            suffixIcon: widget.obscureText
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: const Color(0xFF8DA1B3),
                    ),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF9FCFE),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFDDE6EE)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFDDE6EE)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.lime, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
