class IngredientModel {
  final String id;
  final String name;

  /// Amount needed per serve. When several dishes need the same item, the view model
  /// merges them into ONE card holding the combined total instead of duplicates.
  double quantityPerServe;

  final String unit; // e.g. "g", "pcs", "ml"
  String? imageUrl;
  bool isConfirmedAvailable;

  /// Which dishes of the current meal need this item (e.g. ["Paneer Masala", "Dal"]).
  final List<String> dishNames;

  IngredientModel({
    required this.id,
    required this.name,
    required this.quantityPerServe,
    required this.unit,
    this.imageUrl,
    this.isConfirmedAvailable = false,
    List<String>? dishNames,
  }) : dishNames = dishNames ?? [];

  String get quantityLabel {
    final q = quantityPerServe == quantityPerServe.roundToDouble()
        ? quantityPerServe.toInt().toString()
        : quantityPerServe.toString();
    return '$q $unit';
  }

  /// "Paneer Masala, Dal" - shown on the card so the cook knows who needs what.
  String get dishNamesLabel => dishNames.join(', ');

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
      dishNames: (json['dishNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantityPerServe': quantityPerServe,
        'unit': unit,
        'dishNames': dishNames,
      };
}
