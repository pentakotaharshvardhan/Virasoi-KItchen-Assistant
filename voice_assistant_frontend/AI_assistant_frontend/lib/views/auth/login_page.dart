import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../view_models/auth_viewmodel.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/gradient_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final vm = context.read<AuthViewModel>();
    final ok = await vm.login(_username.text.trim(), _password.text);
    if (ok && mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (r) => false);
    } else if (mounted && vm.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(vm.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: FadeTransition(
                opacity: _fadeController,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 0.06), end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: _fadeController, curve: Curves.easeOutCubic)),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 40,
                            offset: const Offset(0, 20))
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Hero(
                            tag: 'app_logo',
                            child: Container(
                              height: 64,
                              width: 64,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.soup_kitchen_rounded,
                                  color: Colors.black, size: 32),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text('Welcome back',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          const Text('Sign in to your kitchen assistant',
                              style: TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 28),
                          AppTextField(
                            controller: _username,
                            label: 'Username',
                            icon: Icons.person_outline_rounded,
                            keyboardType: TextInputType.text,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter a username'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            controller: _password,
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscure,
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Min. 6 characters'
                                : null,
                            suffix: IconButton(
                              icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          const SizedBox(height: 26),
                          GradientButton(
                              label: 'Log In',
                              isLoading: vm.isLoading,
                              onPressed: _submit),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Don't have an account?",
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                              TextButton(
                                onPressed: () => Navigator.pushNamed(
                                    context, AppRoutes.register),
                                child: const Text('Register'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
