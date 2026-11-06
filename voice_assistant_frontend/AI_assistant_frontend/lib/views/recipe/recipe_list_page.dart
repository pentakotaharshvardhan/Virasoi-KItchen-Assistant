import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../services/recipe_service.dart';
import '../../view_models/recipe_list_viewmodel.dart';
import '../../widgets/recipe_card.dart';
import '../../widgets/recipe_card_shimmer.dart';

class RecipeListPage extends StatefulWidget {
  const RecipeListPage({super.key});

  @override
  State<RecipeListPage> createState() => _RecipeListPageState();
}

class _RecipeListPageState extends State<RecipeListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<RecipeListViewModel>().load());
  }

  void _openSortSheet(BuildContext context) {
    final vm = context.read<RecipeListViewModel>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 16),
              const Text('Sort recipes by', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              _sortTile(context, 'Time added (oldest first)', RecipeSortOption.timeAsc, vm),
              _sortTile(context, 'Time added (newest first)', RecipeSortOption.timeDesc, vm),
              _sortTile(context, 'Alphabetical (A-Z)', RecipeSortOption.alphabetical, vm),
              _sortTile(context, 'Total time required', RecipeSortOption.totalTime, vm),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sortTile(BuildContext context, String label, RecipeSortOption option, RecipeListViewModel vm) {
    final selected = vm.sort == option;
    return ListTile(
      title: Text(label, style: TextStyle(color: selected ? AppColors.primary : AppColors.textPrimary, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
      onTap: () {
        vm.changeSort(option);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RecipeListViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Recipes', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: false,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              onChanged: vm.search,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search recipes...',
                                hintStyle: TextStyle(color: AppColors.textMuted.withOpacity(0.7)),
                                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.primary),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openSortSheet(context),
                          child: Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.surfaceElevated, AppColors.surfaceCard.withOpacity(0.5)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider, width: 1),
                            ),
                            child: const Icon(Icons.tune_rounded, size: 20, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildBody(vm),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(RecipeListViewModel vm) {
    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.88,
    );

    if (vm.status == ListStatus.loading) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        gridDelegate: gridDelegate,
        itemBuilder: (_, __) => const RecipeCardShimmer(),
      );
    }
    if (vm.status == ListStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 40),
            const SizedBox(height: 10),
            Text(vm.errorMessage ?? 'Something went wrong', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: vm.load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (vm.visible.isEmpty) {
      return const Center(child: Text('No recipes yet — tap Create to generate one!', style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: vm.load,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: vm.visible.length,
        gridDelegate: gridDelegate,
        itemBuilder: (_, i) {
          final recipe = vm.visible[i];
          return RecipeCard(
            recipe: recipe,
            onTap: () => Navigator.pushNamed(context, AppRoutes.recipeDetail, arguments: recipe.id),
          );
        },
      ),
    );
  }
}
