import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _faqs = [
    ('How do I generate a recipe?', 'Tap Create on the home screen, list the dishes you want (comma separated), pick your stove count and servings, then hit Start.'),
    ('How does the voice assistant work?', 'Tap the mic on the Voice Assistant screen and speak naturally — say what ingredients you have, and ask questions about the current step.'),
    ('Is my conversation saved?', 'No — voice conversations are kept only in memory for the current session and are never written to a database.'),
    ('How do step timers work?', 'Tap the play icon next to any timed step to start a countdown; you\'ll get an alert when it finishes.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _faqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final (q, a) = _faqs[i];
          return Container(
            decoration: BoxDecoration(color: AppColors.surfaceCard, borderRadius: BorderRadius.circular(16)),
            child: ExpansionTile(
              title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              iconColor: AppColors.primary,
              collapsedIconColor: AppColors.textSecondary,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [Align(alignment: Alignment.centerLeft, child: Text(a, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)))],
            ),
          );
        },
      ),
    );
  }
}
