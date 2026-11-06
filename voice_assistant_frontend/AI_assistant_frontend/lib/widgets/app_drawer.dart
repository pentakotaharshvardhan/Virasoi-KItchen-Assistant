import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../view_models/auth_viewmodel.dart';
import '../view_models/home_viewmodel.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeViewModel>();
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.admin_panel_settings, color: Colors.black, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(home.userName.isEmpty ? 'Chef' : home.userName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(home.userEmail, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            _DrawerTile(icon: Icons.menu_book_outlined, label: 'My Recipes', onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.recipeList);
            }),
            _DrawerTile(icon: Icons.mic_none_rounded, label: 'Voice Assistant', onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.voiceAssistant);
            }),
            _DrawerTile(icon: Icons.settings_outlined, label: 'Settings', onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.settings);
            }),
            _DrawerTile(icon: Icons.help_outline_rounded, label: 'Help & Support', onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.help);
            }),
            const Spacer(),
            const Divider(),
            _DrawerTile(
              icon: Icons.logout_rounded,
              label: 'Log out',
              color: AppColors.error,
              onTap: () async {
                await context.read<AuthViewModel>().logout();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (r) => false);
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _DrawerTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textPrimary),
      title: Text(label, style: TextStyle(color: color ?? AppColors.textPrimary, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
