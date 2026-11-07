import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/secure_storage.dart';

import 'view_models/auth_viewmodel.dart';
import 'view_models/home_viewmodel.dart';
import 'view_models/recipe_list_viewmodel.dart';
import 'view_models/recipe_detail_viewmodel.dart';
import 'view_models/create_recipe_viewmodel.dart';
import 'view_models/ingredient_viewmodel.dart';
import 'view_models/voice_viewmodel.dart';

import 'views/auth/login_page.dart';
import 'views/auth/register_page.dart';
import 'views/home/home_page.dart';
import 'views/recipe/recipe_list_page.dart';
import 'views/recipe/recipe_detail_page.dart';
import 'views/create/create_recipe_page.dart';
import 'views/ingredient/ingredient_page.dart';
import 'views/voice/voice_assistant_page.dart';
import 'views/settings/settings_page.dart';
import 'views/help/help_page.dart';

void main() {
  runApp(const AiAssistantApp());
}

class AiAssistantApp extends StatelessWidget {
  const AiAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => HomeViewModel()),
        ChangeNotifierProvider(create: (_) => RecipeListViewModel()),
        ChangeNotifierProvider(create: (_) => RecipeDetailViewModel()),
        ChangeNotifierProvider(create: (_) => CreateRecipeViewModel()),
        ChangeNotifierProvider(create: (_) => IngredientViewModel()),
        ChangeNotifierProvider(create: (_) => VoiceViewModel()),
      ],
      child: MaterialApp(
        title: 'Virasoi Kitchen Assistant',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const _StartupGate(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case AppRoutes.login:
              return MaterialPageRoute(builder: (_) => const LoginPage());
            case AppRoutes.register:
              return MaterialPageRoute(builder: (_) => const RegisterPage());
            case AppRoutes.home:
              return MaterialPageRoute(builder: (_) => const HomePage());
            case AppRoutes.recipeList:
              return MaterialPageRoute(builder: (_) => const RecipeListPage());
            case AppRoutes.recipeDetail:
              final id = settings.arguments as String;
              return MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: id));
            case AppRoutes.createRecipe:
              return MaterialPageRoute(builder: (_) => const CreateRecipePage());
            case AppRoutes.ingredients:
              final id = settings.arguments as String;
              return MaterialPageRoute(builder: (_) => IngredientPage(recipeId: id));
            case AppRoutes.voiceAssistant:
              final args = settings.arguments;
              String? sid;
              bool help = false;
              bool awaitingReady = false;
              String? recipeId;
              if (args is String) sid = args;
              if (args is Map) {
                sid = args['sessionId'] as String?;
                help = args['helpMode'] as bool? ?? false;
                awaitingReady = args['awaitingReady'] as bool? ?? false;
                recipeId = args['recipeId'] as String?;
              }
              return MaterialPageRoute(
                builder: (_) => VoiceAssistantPage(
                  sessionId: sid,
                  helpMode: help,
                  awaitingReady: awaitingReady,
                  recipeId: recipeId,
                ),
              );
            case AppRoutes.settings:
              return MaterialPageRoute(builder: (_) => const SettingsPage());
            case AppRoutes.help:
              return MaterialPageRoute(builder: (_) => const HelpPage());
            default:
              return MaterialPageRoute(builder: (_) => const LoginPage());
          }
        },
      ),
    );
  }
}

/// Decides whether to land on Login or Home based on a stored token.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    SecureStorage.instance.accessToken.then((token) {
      if (mounted) setState(() => _loggedIn = (token != null && token.isNotEmpty));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn! ? const HomePage() : const LoginPage();
  }
}
