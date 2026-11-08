import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../models/recipe_model.dart';

class RecipeCard extends StatelessWidget {
  final RecipeModel recipe;
  final VoidCallback onTap;

  const RecipeCard({super.key, required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'recipe_image_${recipe.id}',
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: recipe.coverImageUrl == null
                    ? Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.surfaceElevated,
                              AppColors.surface
                            ],
                          ),
                        ),
                        child: const Icon(Icons.restaurant_rounded,
                            color: AppColors.textMuted, size: 28),
                      )
                    : CachedNetworkImage(
                        imageUrl: recipe.coverImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.surfaceElevated),
                        errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.image_not_supported,
                                color: AppColors.textMuted)),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Hero(
                      tag: 'recipe_title_${recipe.id}',
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          recipe.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${recipe.totalTimeMinutes}m',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                        const Spacer(),
                        _buildSourceBadge(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBadge() {
    final source = recipe.source.toUpperCase();
    final isAi = source == 'AI' || source == 'AI_GENERATED';
    final label = source == 'ANCESTOR'
        ? 'ANCESTOR'
        : isAi
            ? 'AI'
            : 'OWN';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            (isAi ? AppColors.secondary : AppColors.primary).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color:
              (isAi ? AppColors.secondary : AppColors.primary).withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w800,
          color: isAi ? AppColors.secondary : AppColors.primary,
        ),
      ),
    );
  }
}
