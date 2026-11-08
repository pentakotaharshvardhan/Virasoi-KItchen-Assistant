import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../view_models/recipe_detail_viewmodel.dart';

class RecipeDetailPage extends StatefulWidget {
  final String recipeId;
  const RecipeDetailPage({super.key, required this.recipeId});

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<RecipeDetailViewModel>().load(widget.recipeId));
  }

  void _zoomImage(BuildContext context, String url, String heroTag) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(imageUrl: url)),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RecipeDetailViewModel>();
    if (vm.status == DetailStatus.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (vm.status == DetailStatus.error || vm.recipe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
            child: Text(vm.errorMessage ?? 'Recipe not found',
                style: const TextStyle(color: AppColors.textSecondary))),
      );
    }
    final recipe = vm.recipe!;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.background,
            automaticallyImplyLeading: false,
            leadingWidth: 100,
            leading: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: 'Cook this recipe',
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.createRecipe,
                    arguments: recipe.dishName,
                  ),
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'recipe_image_${recipe.id}',
                child: recipe.coverImageUrl == null
                    ? Container(color: AppColors.surfaceElevated)
                    : CachedNetworkImage(
                        imageUrl: recipe.coverImageUrl!, fit: BoxFit.cover),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'recipe_title_${recipe.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(recipe.title,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _InfoChip(
                          icon: Icons.schedule,
                          label: '${recipe.totalTimeMinutes} min'),
                      const SizedBox(width: 8),
                      _InfoChip(
                          icon: Icons.restaurant_rounded,
                          label: '${recipe.baseServes} servings'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(recipe.description,
                      style: const TextStyle(
                          color: AppColors.textSecondary, height: 1.5)),
                  const SizedBox(height: 28),
                  const Text('Ingredients',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ...recipe.ingredients.map((ing) {
                    final heroTag = 'zoom_${ing.id}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: ing.imageUrl == null
                                ? null
                                : () =>
                                    _zoomImage(context, ing.imageUrl!, heroTag),
                            child: Hero(
                              tag: heroTag,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ing.imageUrl == null
                                    ? Container(
                                        width: 52,
                                        height: 52,
                                        color: AppColors.surfaceElevated,
                                        child: const Icon(Icons.set_meal,
                                            size: 20,
                                            color: AppColors.textMuted))
                                    : CachedNetworkImage(
                                        imageUrl: ing.imageUrl!,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Text(ing.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                          Text(ing.quantityLabel,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 28),
                  const Text('Steps',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ...List.generate(recipe.steps.length, (i) {
                    final step = recipe.steps[i];
                    return _StepTile(
                      index: i,
                      number: step.stepNumber,
                      instruction: step.instruction,
                      durationLabel: step.durationLabel,
                      onStartTimer: step.baseTimerSeconds > 0
                          ? () => vm.startStepTimer(i)
                          : null,
                    );
                  }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final int number;
  final String instruction;
  final String durationLabel;
  final VoidCallback? onStartTimer;

  const _StepTile(
      {required this.index,
      required this.number,
      required this.instruction,
      required this.durationLabel,
      this.onStartTimer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.primary.withOpacity(0.18),
              child: Text('$number',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5))),
          const SizedBox(width: 12),
          Expanded(
              child: Text(instruction, style: const TextStyle(height: 1.4))),
          if (durationLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                children: [
                  Text(durationLabel,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary)),
                  IconButton(
                    icon: const Icon(Icons.play_circle_fill_rounded,
                        color: AppColors.primary),
                    onPressed: onStartTimer,
                    tooltip: 'Start timer',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
