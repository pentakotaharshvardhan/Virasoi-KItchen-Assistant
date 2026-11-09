import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../view_models/home_viewmodel.dart';
import '../../view_models/recipe_list_viewmodel.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/recipe_card.dart';
import '../../services/recipe_service.dart';
import '../../services/helper_assistant_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    context.read<HomeViewModel>().loadUser();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RecipeListViewModel>().load();
    });
    _fabController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _openCreationChoices() async {
    await Navigator.pushNamed(context, AppRoutes.creationChoices);
    if (!mounted) return;
    await context.read<RecipeListViewModel>().load();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeViewModel>();
    final recipes = context.watch<RecipeListViewModel>();
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
                  decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle),
                  child: const CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.black,
                    child: Icon(Icons.admin_panel_settings,
                        color: Colors.white, size: 18),
                  ),
                ),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            title: Text(
                'Hey, ${home.userName.isEmpty ? 'Chef' : home.userName.split(' ').first} 👋'),
            actions: [
              IconButton(
                tooltip: 'Open helper assistant',
                icon: const Icon(Icons.support_agent_rounded),
                onPressed: () => HelperAssistantLauncher.open(
                  context,
                  screenName: 'Home',
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HeroIntroCard(),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your Recipes',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800),
                        ),
                      ),
                      PopupMenuButton<RecipeSortOption>(
                        tooltip: 'Sort recipes',
                        icon: const Icon(Icons.sort_rounded),
                        onSelected: recipes.changeSort,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: RecipeSortOption.timeDesc,
                            child: Text('Date: newest first'),
                          ),
                          PopupMenuItem(
                            value: RecipeSortOption.timeAsc,
                            child: Text('Date: oldest first'),
                          ),
                          PopupMenuItem(
                            value: RecipeSortOption.alphabetical,
                            child: Text('Name: A-Z'),
                          ),
                          PopupMenuItem(
                            value: RecipeSortOption.alphabeticalDesc,
                            child: Text('Name: Z-A'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _originFilter(
                            recipes, RecipeOriginFilter.all, 'All recipes'),
                        _originFilter(
                            recipes, RecipeOriginFilter.ancestor, 'Ancestor'),
                        _originFilter(
                            recipes, RecipeOriginFilter.aiGenerated, 'AI'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRecipeList(recipes),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: _fabController, curve: Curves.easeInOut)),
        child: FloatingActionButton(
          onPressed: _openCreationChoices,
          tooltip: 'Add a recipe or start cooking',
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          shape: const CircleBorder(),
          child: const Icon(Icons.add_rounded, size: 30),
        ),
      ),
    );
  }

  Widget _originFilter(
    RecipeListViewModel vm,
    RecipeOriginFilter filter,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: vm.originFilter == filter,
        onSelected: (_) => vm.changeOriginFilter(filter),
      ),
    );
  }

  Widget _buildRecipeList(RecipeListViewModel vm) {
    if (vm.status == ListStatus.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (vm.status == ListStatus.error) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              vm.errorMessage ?? 'Could not load your recipes.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            TextButton.icon(
              onPressed: vm.load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (vm.visible.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'No recipes in this collection yet. Add an ancestor recipe or start a cooking session.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: vm.visible.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (context, index) {
        final recipe = vm.visible[index];
        return RecipeCard(
          recipe: recipe,
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.recipeDetail,
            arguments: recipe.id,
          ),
        );
      },
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
  const _HeroIntroCard();

  @override
  State<_HeroIntroCard> createState() => _HeroIntroCardState();
}

class _HeroIntroCardState extends State<_HeroIntroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat();
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
        gradient: const LinearGradient(
            colors: [AppColors.surfaceElevated, AppColors.surfaceCard]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Virasoi Kitchen Assistant',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Your AI sous-chef: generate recipes from what you\'re craving, check off ingredients by talking out loud, and get guided, timed steps hands-free.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                      fontSize: 13),
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
      RRect.fromRectAndRadius(
          Rect.fromLTWH(8, size.height - 26, size.width - 16, 20),
          const Radius.circular(6)),
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
        final wobble =
            6 * (0.5 - (((t * 2 + i * 0.5 + y / 40) % 1.0) - 0.5).abs());
        path.lineTo(baseX + wobble, y);
      }
      canvas.drawPath(
          path,
          steamPaint
            ..color = steamPaint.color.withOpacity((1 - t).clamp(0.15, 0.5)));
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientSteamPainter oldDelegate) => true;
}
