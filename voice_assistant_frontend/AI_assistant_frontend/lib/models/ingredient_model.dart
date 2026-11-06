class IngredientModel {
  final String id;
  final String name;
  final double quantityPerServe;
  final String unit; // e.g. "g", "pcs", "ml"
  String? imageUrl;
  bool isConfirmedAvailable;

  IngredientModel({
    required this.id,
    required this.name,
    required this.quantityPerServe,
    required this.unit,
    this.imageUrl,
    this.isConfirmedAvailable = false,
  });

  String get quantityLabel {
    final q = quantityPerServe == quantityPerServe.roundToDouble() ? quantityPerServe.toInt().toString() : quantityPerServe.toString();
    return '$q $unit';
  }

  static int _fallbackCounter = 0;

  factory IngredientModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['name'];
    final id = (rawId == null || rawId.toString().isEmpty)
        ? 'ingredient_${_fallbackCounter++}_${DateTime.now().microsecondsSinceEpoch}'
        : rawId.toString();
    return IngredientModel(
      id: id,
      name: (json['name'] ?? '').toString(),
      quantityPerServe: (json['quantityPerServe'] as num? ?? json['quantity'] as num? ?? 0).toDouble(),
      unit: (json['unit'] ?? 'pcs').toString(),
      imageUrl: json['imageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantityPerServe': quantityPerServe,
        'unit': unit,
      };
}
