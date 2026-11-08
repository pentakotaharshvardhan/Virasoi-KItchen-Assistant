import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../view_models/create_recipe_viewmodel.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/gradient_button.dart';

class CreateRecipePage extends StatefulWidget {
  final String? initialDishName;
  const CreateRecipePage({super.key, this.initialDishName});

  @override
  State<CreateRecipePage> createState() => _CreateRecipePageState();
}

class _CreateRecipePageState extends State<CreateRecipePage> {
  final _dishController = TextEditingController();
  int _stoves = 1;
  int _servings = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<CreateRecipeViewModel>();
      vm.init().then((_) {
        if (mounted) {
          vm.beginDraft(initialDishName: widget.initialDishName);
          setState(() {
            _stoves = vm.stoves;
            _servings = vm.servings;
          });
        }
      });
    });
    _dishController.addListener(() {
      context
          .read<CreateRecipeViewModel>()
          .onDishNameChanged(_dishController.text);
    });
  }

  @override
  void dispose() {
    _dishController.dispose();
    super.dispose();
  }

  void _addDish() {
    if (_dishController.text.trim().isNotEmpty) {
      final vm = context.read<CreateRecipeViewModel>();
      if (!vm.addDish(_dishController.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(vm.errorMessage ?? 'Could not add that dish.')),
        );
        return;
      }
      _dishController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _start() async {
    final vm = context.read<CreateRecipeViewModel>();

    if (_dishController.text.trim().isNotEmpty) {
      if (!vm.addDish(_dishController.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(vm.errorMessage ?? 'Could not add that dish.')),
        );
        return;
      }
      _dishController.clear();
    }

    final ok = await vm.submit(
      stoveCount: _stoves,
      servingCount: _servings,
    );

    if (!mounted) return;
    if (ok && vm.generated.isNotEmpty) {
      // Every dish is generated individually; the items screen merges their ingredients.
      Navigator.pushNamed(
        context,
        AppRoutes.ingredients,
        arguments: vm.generated.map((r) => r.id).toList(),
      );
    } else if (vm.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(vm.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CreateRecipeViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Create a recipe')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 450),
                      builder: (context, v, child) =>
                          Opacity(opacity: v, child: child),
                      child: const Text(
                        'What are we cooking today?',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Add dishes one by one to your session.',
                        style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    AppTextField(
                      controller: _dishController,
                      label: 'Enter dish name',
                      icon: Icons.restaurant_menu_rounded,
                      suffix: IconButton(
                        icon: const Icon(Icons.add_task_rounded,
                            color: AppColors.primary),
                        onPressed: _addDish,
                      ),
                      onFieldSubmitted: (_) => _addDish(),
                    ),
                    if (vm.suggestedRecipes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCard,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recipes from your collection',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...vm.suggestedRecipes.map(
                                (recipe) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.restaurant_menu_rounded,
                                    color: AppColors.primary,
                                  ),
                                  title: Text(recipe.dishName),
                                  onTap: () {
                                    vm.selectSuggestedRecipe(recipe);
                                    _dishController.clear();
                                    FocusScope.of(context).unfocus();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (vm.selectedDishes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: vm.selectedDishes
                              .map((dish) => Chip(
                                    label: Text(dish,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                    backgroundColor: AppColors.surfaceElevated,
                                    deleteIcon: const Icon(Icons.cancel_rounded,
                                        size: 18,
                                        color: AppColors.textSecondary),
                                    onDeleted: () => vm.removeDish(dish),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    side: BorderSide(
                                        color:
                                            AppColors.divider.withOpacity(0.5)),
                                  ))
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 32),
                    const Text('Kitchen Settings',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _StepperRow(
                      label:
                          'Stoves available (max ${CreateRecipeViewModel.maxStoves})',
                      icon: Icons.local_fire_department_rounded,
                      value: _stoves,
                      onChanged: (v) => setState(() => _stoves = v),
                      maxValue: CreateRecipeViewModel.maxStoves,
                    ),
                    const SizedBox(height: 12),
                    _StepperRow(
                      label: 'Number of servings',
                      icon: Icons.people_alt_rounded,
                      value: _servings,
                      onChanged: (v) => setState(() => _servings = v),
                    ),
                    const SizedBox(height: 40),
                    GradientButton(
                      label: vm.selectedDishes.length > 1
                          ? 'Generate Recipes'
                          : 'Generate Recipe',
                      icon: Icons.auto_awesome,
                      isLoading: vm.isSubmitting,
                      onPressed: _start,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;
  final int? maxValue;

  const _StepperRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500))),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 24),
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
          ),
          Text('$value',
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
            onPressed: maxValue == null || value < maxValue!
                ? () => onChanged(value + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
