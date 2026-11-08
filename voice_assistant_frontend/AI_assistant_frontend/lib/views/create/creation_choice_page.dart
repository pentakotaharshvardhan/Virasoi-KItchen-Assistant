import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';

class CreationChoicePage extends StatelessWidget {
  const CreationChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What would you like to do?')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose how you want to add to your kitchen.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 22),
          _ChoiceCard(
            icon: Icons.record_voice_over_rounded,
            title: 'Add an ancestor recipe',
            description:
                'Record a family recipe or upload an audio file to preserve it.',
            color: AppColors.secondary,
            onTap: () => Navigator.pushNamed(context, AppRoutes.ancestorRecipe),
          ),
          const SizedBox(height: 14),
          _ChoiceCard(
            icon: Icons.soup_kitchen_rounded,
            title: 'Start a cooking session',
            description:
                'Choose dishes, stoves, and servings, then cook with guided steps.',
            color: AppColors.primary,
            onTap: () => Navigator.pushNamed(context, AppRoutes.createRecipe),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(description,
                        style: const TextStyle(
                            color: AppColors.textSecondary, height: 1.35)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
