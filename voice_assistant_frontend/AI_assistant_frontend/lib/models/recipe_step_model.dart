class RecipeStepModel {
  final String id;
  final int stepNumber;
  final String instruction;
  final String stepType;
  final bool requiresTimer;
  final int baseTimerSeconds;
  final bool scalesWithServes;
  final String? ingredientName;

  RecipeStepModel({
    required this.id,
    required this.stepNumber,
    required this.instruction,
    required this.stepType,
    required this.requiresTimer,
    required this.baseTimerSeconds,
    required this.scalesWithServes,
    this.ingredientName,
  });

  factory RecipeStepModel.fromJson(Map<String, dynamic> json) => RecipeStepModel(
        id: (json['id'] ?? '').toString(),
        stepNumber: (json['stepNumber'] ?? 0) as int,
        instruction: (json['instruction'] ?? '').toString(),
        stepType: (json['stepType'] ?? 'manual').toString(),
        requiresTimer: (json['requiresTimer'] ?? false) as bool,
        baseTimerSeconds: (json['baseTimerSeconds'] ?? 0) as int,
        scalesWithServes: (json['scalesWithServes'] ?? false) as bool,
        ingredientName: json['ingredientName']?.toString(),
      );

  String get durationLabel {
    if (baseTimerSeconds <= 0) return '';
    final m = baseTimerSeconds ~/ 60;
    final s = baseTimerSeconds % 60;
    if (m == 0) return '${s}s';
    if (s == 0) return '$m min';
    return '${m}m ${s}s';
  }
}
