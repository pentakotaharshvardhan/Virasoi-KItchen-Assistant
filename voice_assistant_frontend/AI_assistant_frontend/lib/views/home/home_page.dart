import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../view_models/home_viewmodel.dart';
import '../../widgets/app_drawer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    context.read<HomeViewModel>().loadUser();
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeViewModel>();
    return Scaffold(
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            expandedHeight: 96,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                  child: const CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.black,
                    child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 18),
                  ),
                ),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            title: Text('Hey, ${home.userName.isEmpty ? 'Chef' : home.userName.split(' ').first} 👋'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroIntroCard(),
                  const SizedBox(height: 28),
                  const Text('What you can do', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  _FeatureTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Generate a recipe',
                    subtitle: 'Tell us the dish, we\'ll plan ingredients & steps',
                    color: AppColors.primary,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.createRecipe),
                  ),
                  const SizedBox(height: 12),
                  _FeatureTile(
                    icon: Icons.menu_book_rounded,
                    title: 'Browse your recipes',
                    subtitle: 'Everything you\'ve saved or generated so far',
                    color: AppColors.secondary,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.recipeList),
                  ),
                  const SizedBox(height: 12),
                  _FeatureTile(
                    icon: Icons.graphic_eq_rounded,
                    title: 'Talk to your assistant',
                    subtitle: 'Hands-free help while you cook',
                    color: AppColors.tertiary,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.voiceAssistant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeInOut)),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.createRecipe),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// App intro / description card.
///
/// RIVE INTEGRATION (recommended upgrade):
/// Create `assets/rive/kitchen_hero.riv` — a looping "idle kitchen" scene
/// (steam rising off a pot, a whisk gently rotating) as a single Artboard
/// with one State Machine "HeroLoop" (no inputs needed, just an ambient
/// timeline loop). Register it in pubspec assets, then swap the
/// `_AmbientSteamPainter` below for:
///   RiveAnimation.asset('assets/rive/kitchen_hero.riv', fit: BoxFit.cover)
/// The rest of this card's layout does not need to change.
class _HeroIntroCard extends StatefulWidget {
  @override
  State<_HeroIntroCard> createState() => _HeroIntroCardState();
}

class _HeroIntroCardState extends State<_HeroIntroCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.surfaceElevated, AppColors.surfaceCard]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Virasoi Kitchen Assistant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Your AI sous-chef: generate recipes from what you\'re craving, check off ingredients by talking out loud, and get guided, timed steps hands-free.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              size: const Size(72, 72),
              painter: _AmbientSteamPainter(t: _controller.value),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientSteamPainter extends CustomPainter {
  final double t;
  _AmbientSteamPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final potPaint = Paint()..color = AppColors.primary.withOpacity(0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(8, size.height - 26, size.width - 16, 20), const Radius.circular(6)),
      potPaint,
    );
    final steamPaint = Paint()
      ..color = AppColors.textSecondary.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 2; i++) {
      final baseX = size.width / 2 + (i == 0 ? -10 : 10);
      final path = Path()..moveTo(baseX, size.height - 30);
      for (double y = size.height - 30; y > 6; y -= 6) {
        final wobble = 6 * (0.5 - (((t * 2 + i * 0.5 + y / 40) % 1.0) - 0.5).abs());
        path.lineTo(baseX + wobble, y);
      }
      canvas.drawPath(path, steamPaint..color = steamPaint.color.withOpacity((1 - t).clamp(0.15, 0.5)));
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientSteamPainter oldDelegate) => true;
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _FeatureTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider.withOpacity(0.5), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}
