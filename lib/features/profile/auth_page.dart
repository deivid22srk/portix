import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_strings.dart';
import '../../app/theme.dart';
import '../../core/auth.dart';
import '../../core/auth_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/primitives.dart';

/// Login/cadastro por e-mail e login com Google.
class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _name = TextEditingController();

  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/menu');
    }
  }

  String _prettyError(Object error) {
    final String text = error.toString();
    final int start = text.indexOf('{');
    if (start >= 0) {
      try {
        final Object? body = jsonDecode(text.substring(start));
        if (body is Map) {
          final Object? msg =
              body['msg'] ?? body['message'] ?? body['error_description'];
          if (msg != null) {
            return msg.toString();
          }
        }
      } on Object {
        // mantém o texto original
        return text;
      }
    }
    return text;
  }

  Future<void> _submit() async {
    final L10n l10n = context.l10n;
    final String email = _email.text.trim();
    final String password = _password.text;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$').hasMatch(email)) {
      setState(() => _error = l10n.emailRequired);
      return;
    }
    if (password.length < 6) {
      setState(() => _error = l10n.passwordShort);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AccountController controller = ref.read(accountProvider.notifier);
      if (_signUp) {
        await controller.signUp(
          email: email,
          password: password,
          displayName: _name.text,
        );
        final bool hasSession =
            ref.read(supabaseClientProvider).auth.currentSession != null;
        if (!hasSession) {
          if (mounted) {
            setState(() => _busy = false);
            showAppSnackBar(context, message: l10n.authCheckEmail);
          }
          return;
        }
      } else {
        await controller.signIn(email: email, password: password);
      }
      if (mounted) {
        _close();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _prettyError(error);
        });
      }
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountProvider.notifier).signInWithGoogle();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _prettyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = context.l10n;
    final Set<String> providers =
        ref.watch(enabledProvidersProvider).value ?? const <String>{};
    final bool googleKnownOff =
        providers.isNotEmpty && !providers.contains('google');

    ref.listen<AccountState>(accountProvider, (
      AccountState? previous,
      AccountState next,
    ) {
      if (next.isSignedIn && context.canPop()) {
        context.pop();
      }
    });

    return Scaffold(
      backgroundColor: AppContentColors.transparent,
      body: AppBackdrop(
        child: SafeArea(
          child: AppContentMax(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.md,
                AppSpacing.screen,
                AppSpacing.xxl,
              ),
              children: <Widget>[
                GlassCircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: context.l10n.tooltipBack,
                  onTap: _close,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  l10n.authTitle,
                  style: context.texts.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.authSubtitle,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                GlassContainer(
                  radius: AppRadii.lg,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_signUp) ...<Widget>[
                        _Field(
                          controller: _name,
                          hint: l10n.yourName,
                          icon: Icons.person_rounded,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _Field(
                        controller: _email,
                        hint: l10n.email,
                        icon: Icons.alternate_email_rounded,
                        keyboard: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _Field(
                        controller: _password,
                        hint: l10n.password,
                        icon: Icons.lock_rounded,
                        obscure: true,
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _error!,
                          style: context.texts.bodySmall?.copyWith(
                            color: context.colors.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      PrimaryButton(
                        label: _signUp ? l10n.signUp : l10n.signIn,
                        icon: Icons.login_rounded,
                        isLoading: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SecondaryButton(
                        label: _signUp ? l10n.signIn : l10n.signUp,
                        icon: Icons.person_add_alt_1_rounded,
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _signUp = !_signUp;
                                _error = null;
                              }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(
                  label: l10n.continueWithGoogle,
                  icon: Icons.g_mobiledata_rounded,
                  onPressed: _busy ? null : _google,
                ),
                if (googleKnownOff) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.googleUnavailable,
                    textAlign: TextAlign.center,
                    style: context.texts.labelSmall?.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboard,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: AppRadii.md,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: context.colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboard,
              style: context.texts.bodyLarge,
              cursorColor: context.colors.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: context.texts.bodyMedium?.copyWith(
                  color: context.colors.textTertiary,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.fieldVertical,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
