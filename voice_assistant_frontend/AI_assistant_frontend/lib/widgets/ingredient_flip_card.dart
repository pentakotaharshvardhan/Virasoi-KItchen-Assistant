import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../models/ingredient_model.dart';
import '../view_models/ingredient_viewmodel.dart';

/// Ingredient grid card (screen 6). Tap -> flips (Y-axis rotation) and
/// expands into an overlay sized to 75% of the screen showing a larger
/// image + quantity, then flips back closed on dismiss.
class IngredientFlipCard extends StatelessWidget {
  final IngredientModel ingredient;

  /// In a multi-dish meal the card also says which dishes need this item.
  final bool showDishNames;

  const IngredientFlipCard({
    super.key,
    required this.ingredient,
    this.showDishNames = false,
  });

  void _openExpanded(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, anim, __) => _ExpandedIngredientView(
        ingredient: ingredient,
        animation: anim,
        showDishNames: showDishNames,
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openExpanded(context),
      onLongPress: () {
        // Option to manually remove on long press
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove Ingredient?'),
            content: Text('Are you sure you want to remove ${ingredient.name}?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  context.read<IngredientViewModel>().removeIngredient(ingredient.id);
                  Navigator.pop(ctx);
                },
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      child: Hero(
        tag: 'ingredient_${ingredient.id}',
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider.withOpacity(0.4), width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: ingredient.imageUrl == null
                    ? Container(
                        width: double.infinity,
                        color: AppColors.surfaceElevated,
                        child: const Icon(Icons.restaurant_rounded, color: AppColors.textMuted, size: 20),
                      )
                    : CachedNetworkImage(
                        imageUrl: ingredient.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Column(
                  children: [
                    Text(
                      ingredient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      ingredient.quantityLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                    ),
                    if (showDishNames && ingredient.dishNames.isNotEmpty)
                      Text(
                        ingredient.dishNamesLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedIngredientView extends StatelessWidget {
  final IngredientModel ingredient;
  final Animation<double> animation;
  final bool showDishNames;
  const _ExpandedIngredientView({
    required this.ingredient,
    required this.animation,
    this.showDishNames = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              // Flip on Y axis while scaling up to 75% of screen.
              final angle = (1 - animation.value) * pi / 2;
              return Opacity(
                opacity: animation.value,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(angle),
                  child: child,
                ),
              );
            },
            child: Hero(
              tag: 'ingredient_${ingredient.id}',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: screenSize.width * 0.75,
                  height: screenSize.height * 0.6,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: ingredient.imageUrl == null
                            ? Container(color: AppColors.surfaceElevated, child: const Icon(Icons.set_meal, size: 56, color: AppColors.textMuted))
                            : CachedNetworkImage(imageUrl: ingredient.imageUrl!, fit: BoxFit.cover, width: double.infinity),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            Text(ingredient.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('Needed: ${ingredient.quantityLabel}', style: const TextStyle(color: AppColors.textSecondary)),
                            if (showDishNames && ingredient.dishNames.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'For: ${ingredient.dishNamesLabel}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                            ],
                          ],
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
