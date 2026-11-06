import 'package:ai_assistant_frontend/models/chat_message_model.dart';
import 'package:ai_assistant_frontend/models/ingredient_model.dart';
import 'package:ai_assistant_frontend/models/recipe_model.dart';
import 'package:ai_assistant_frontend/models/recipe_step_model.dart';
import 'package:ai_assistant_frontend/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

void main() {
  group('RecipeModel', () {
    test('parses the full backend shape', () {
      final recipe = RecipeModel.fromJson(
        recipeJson(
          ingredients: [
            ingredientJson(id: 'i1', name: 'Paneer', quantityPerServe: 250, unit: 'g'),
          ],
          steps: [
            stepJson(id: 's1', instruction: 'Fry the paneer', baseTimerSeconds: 120),
          ],
        ),
      );

      expect(recipe.id, 'recipe-1');
      expect(recipe.dishName, 'Paneer Butter Masala');
      expect(recipe.title, 'Paneer Butter Masala');
      expect(recipe.source, 'ai');
      expect(recipe.baseServes, 2);
      expect(recipe.ingredients.single.name, 'Paneer');
      expect(recipe.steps.single.instruction, 'Fry the paneer');
      expect(recipe.createdAt.toUtc(), DateTime.utc(2026, 1, 10, 10));
    });

    test('uses safe fallbacks for a sparse payload', () {
      final recipe = RecipeModel.fromJson({});

      expect(recipe.dishName, 'Untitled recipe');
      expect(recipe.description, '');
      expect(recipe.baseServes, 1);
      expect(recipe.source, 'user');
      expect(recipe.ingredients, isEmpty);
      expect(recipe.steps, isEmpty);
      expect(recipe.coverImageUrl, isNull);
    });

    test('totalTimeMinutes sums step timers and rounds up', () {
      final recipe = sampleRecipe(steps: [
        stepJson(baseTimerSeconds: 31),
        stepJson(baseTimerSeconds: 30),
      ]);

      expect(recipe.totalTimeMinutes, 2);
    });

    test('totalTimeMinutes is zero when no step declares a timer', () {
      expect(sampleRecipe(steps: [stepJson()]).totalTimeMinutes, 0);
    });
  });

  group('RecipeStepModel', () {
    test('durationLabel formats seconds', () {
      expect(RecipeStepModel.fromJson(stepJson(baseTimerSeconds: 45)).durationLabel, '45s');
    });

    test('durationLabel formats whole minutes', () {
      expect(RecipeStepModel.fromJson(stepJson(baseTimerSeconds: 180)).durationLabel, '3 min');
    });

    test('durationLabel formats mixed minutes and seconds', () {
      expect(RecipeStepModel.fromJson(stepJson(baseTimerSeconds: 125)).durationLabel, '2m 5s');
    });

    test('durationLabel is empty when there is no timer', () {
      expect(RecipeStepModel.fromJson(stepJson()).durationLabel, '');
    });

    test('keeps optional ingredientName and flags', () {
      final step = RecipeStepModel.fromJson(stepJson(
        stepType: 'cook',
        requiresTimer: true,
        scalesWithServes: true,
        ingredientName: 'Rice',
      ));

      expect(step.stepType, 'cook');
      expect(step.requiresTimer, isTrue);
      expect(step.scalesWithServes, isTrue);
      expect(step.ingredientName, 'Rice');
    });
  });

  group('IngredientModel', () {
    test('quantityLabel renders whole numbers without decimals', () {
      final ingredient = IngredientModel.fromJson(
        ingredientJson(quantityPerServe: 3, unit: 'pcs'),
      );
      expect(ingredient.quantityLabel, '3 pcs');
    });

    test('quantityLabel keeps decimal quantities', () {
      final ingredient = IngredientModel.fromJson(
        ingredientJson(quantityPerServe: 1.5, unit: 'kg'),
      );
      expect(ingredient.quantityLabel, '1.5 kg');
    });

    test('accepts quantity alias and defaults unit', () {
      final ingredient = IngredientModel.fromJson({
        'name': 'Salt',
        'quantity': 2,
      });

      expect(ingredient.name, 'Salt');
      expect(ingredient.quantityPerServe, 2);
      expect(ingredient.unit, 'pcs');
      expect(ingredient.isConfirmedAvailable, isFalse);
    });

    test('generates unique fallback ids when id is absent', () {
      final first = IngredientModel.fromJson({'name': 'Salt'});
      final second = IngredientModel.fromJson({'name': 'Sugar'});

      expect(first.id, isNotEmpty);
      expect(second.id, isNotEmpty);
      expect(first.id, isNot(second.id));
    });

    test('falls back to name when id is an empty string', () {
      final ingredient = IngredientModel.fromJson({'id': '', 'name': 'Chili'});
      expect(ingredient.id, isNotEmpty);
    });

    test('toJson round-trips the mutable fields', () {
      final ingredient = IngredientModel.fromJson(ingredientJson());
      final json = ingredient.toJson();

      expect(json['id'], 'ing-1');
      expect(json['name'], 'Onion');
      expect(json['quantityPerServe'], 2);
      expect(json['unit'], 'pcs');
    });
  });

  group('UserModel', () {
    test('parses userId and username', () {
      final user = UserModel.fromJson({
        'userId': 'u-9',
        'username': 'chef',
      });

      expect(user.id, 'u-9');
      expect(user.name, 'chef');
      expect(user.username, 'chef');
    });

    test('accepts id/name aliases', () {
      final user = UserModel.fromJson({'id': 'u-1', 'name': 'Harsh'});
      expect(user.id, 'u-1');
      expect(user.name, 'Harsh');
    });

    test('uses defaults when payload is empty', () {
      final user = UserModel.fromJson({});
      expect(user.name, 'User');
      expect(user.id, '');
      expect(user.username, '');
    });
  });

  group('ChatMessageModel', () {
    test('defaults the timestamp to now', () {
      final before = DateTime.now();
      final message = ChatMessageModel(text: 'hi', sender: ChatSender.user);

      expect(message.text, 'hi');
      expect(message.sender, ChatSender.user);
      expect(message.timestamp.isBefore(before), isFalse);
    });
  });
}
