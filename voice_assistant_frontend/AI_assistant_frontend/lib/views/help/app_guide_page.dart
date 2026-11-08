import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class AppGuidePage extends StatelessWidget {
  const AppGuidePage({super.key});

  static const _sections = <(String, IconData, String)>[
    (
      'Start a cooking session',
      Icons.soup_kitchen_rounded,
      'Use the + button on Home and choose Start cooking. Enter one or more dishes, choose the number of stoves and servings, then review the merged ingredient list. Confirm what you have and say “ready” to begin.'
    ),
    (
      'Add an ancestor recipe',
      Icons.record_voice_over_rounded,
      'Choose Add an ancestor recipe from the + menu. Record a family recipe or upload a WAV recording. The app transcribes it, formats the ingredients and steps, and saves it to your recipes.'
    ),
    (
      'Voice commands',
      Icons.mic_rounded,
      'On a voice-enabled screen, say “help” to open the helper. On the ingredient list, say “remove onions and tomatoes” to remove multiple items. During cooking, say “next”, “wait”, “repeat”, “I am free”, or “stove 1 is free”.'
    ),
    (
      'How cooking steps are scheduled',
      Icons.calendar_view_week_rounded,
      'STOVE steps reserve a burner; USER_ACTION steps need your hands; STOVE_AND_USER steps reserve both at once; PASSIVE steps run in the background. “I am free” releases your hands only. A stove remains reserved until its task is completed.'
    ),
    (
      'Recipe collection',
      Icons.menu_book_rounded,
      'Home shows recipes saved for your account. Filter by ancestor or AI-generated recipes, sort by name or date, and tap a recipe to view its ingredients and steps. From a recipe detail screen, use the cooking action to start a session with that dish.'
    ),
    (
      'Limits and safety',
      Icons.rule_rounded,
      'A cooking session supports up to four dishes and four stoves. Use the named stove or dish when several tasks are active. The helper can explain the app, but it does not change a cooking session unless you use the regular session controls.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How Virasoi works')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final (title, icon, body) = _sections[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 7),
                      Text(body,
                          style: const TextStyle(
                              color: AppColors.textSecondary, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
