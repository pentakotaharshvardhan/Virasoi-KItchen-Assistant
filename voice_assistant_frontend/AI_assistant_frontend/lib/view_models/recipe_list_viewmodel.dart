import 'package:flutter/material.dart';
import '../core/utils/result.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';

enum ListStatus { loading, loaded, error }

class RecipeListViewModel extends ChangeNotifier {
  RecipeListViewModel({RecipeService? service}) : _service = service ?? RecipeService();

  final RecipeService _service;

  ListStatus status = ListStatus.loading;
  String? errorMessage;
  List<RecipeModel> _all = [];
  List<RecipeModel> visible = [];

  String searchQuery = '';
  RecipeSortOption sort = RecipeSortOption.timeAsc;

  Future<void> load() async {
    status = ListStatus.loading;
    notifyListeners();
    final result = await _service.getRecipes();
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
    var list = _all.where((r) => r.title.toLowerCase().contains(searchQuery.toLowerCase())).toList();
    switch (sort) {
      case RecipeSortOption.timeAsc:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case RecipeSortOption.timeDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case RecipeSortOption.alphabetical:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case RecipeSortOption.totalTime:
        list.sort((a, b) => a.totalTimeMinutes.compareTo(b.totalTimeMinutes));
        break;
    }
    visible = list;
    notifyListeners();
  }
}
