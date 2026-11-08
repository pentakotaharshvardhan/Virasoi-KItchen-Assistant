import 'package:flutter/material.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';

enum ListStatus { loading, loaded, error }

enum RecipeOriginFilter { all, ancestor, aiGenerated }

class RecipeListViewModel extends ChangeNotifier {
  RecipeListViewModel({RecipeService? service, SecureStorage? storage})
      : _service = service ?? RecipeService(),
        _storage = storage ?? SecureStorage.instance;

  final RecipeService _service;
  final SecureStorage _storage;

  ListStatus status = ListStatus.loading;
  String? errorMessage;
  List<RecipeModel> _all = [];
  List<RecipeModel> visible = [];

  String searchQuery = '';
  RecipeSortOption sort = RecipeSortOption.timeAsc;
  RecipeOriginFilter originFilter = RecipeOriginFilter.all;

  Future<void> load() async {
    status = ListStatus.loading;
    errorMessage = null;
    notifyListeners();
    final userId = await _storage.userId;
    if (userId == null || userId.isEmpty) {
      _all = [];
      status = ListStatus.loaded;
      _applyFilters();
      return;
    }
    final result = await _service.getRecipesByUserId(userId);
    switch (result) {
      case Success(data: final recipes):
        _all = recipes;
        status = ListStatus.loaded;
        _applyFilters();
        break;
      case Failure(message: final m):
        errorMessage = m;
        status = ListStatus.error;
        notifyListeners();
        break;
    }
  }

  void search(String query) {
    searchQuery = query;
    _applyFilters();
  }

  void changeSort(RecipeSortOption option) {
    sort = option;
    _applyFilters();
  }

  void _applyFilters() {
    var list = _all
        .where((r) =>
            r.title.toLowerCase().contains(searchQuery.toLowerCase()) &&
            _matchesOrigin(r))
        .toList();
    switch (sort) {
      case RecipeSortOption.timeAsc:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case RecipeSortOption.timeDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case RecipeSortOption.alphabetical:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case RecipeSortOption.alphabeticalDesc:
        list.sort(
            (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case RecipeSortOption.totalTime:
        list.sort((a, b) => a.totalTimeMinutes.compareTo(b.totalTimeMinutes));
        break;
    }
    visible = list;
    notifyListeners();
  }

  void changeOriginFilter(RecipeOriginFilter filter) {
    originFilter = filter;
    _applyFilters();
  }

  bool _matchesOrigin(RecipeModel recipe) {
    final source = recipe.source.toUpperCase();
    return switch (originFilter) {
      RecipeOriginFilter.all => true,
      RecipeOriginFilter.ancestor => source == 'ANCESTOR',
      RecipeOriginFilter.aiGenerated =>
        source == 'AI_GENERATED' || source == 'AI',
    };
  }
}
