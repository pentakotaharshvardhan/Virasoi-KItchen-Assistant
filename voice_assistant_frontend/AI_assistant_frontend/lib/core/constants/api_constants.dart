/// ============================================================================
/// API CONSTANTS
/// ============================================================================
/// I was not able to reach the Swagger UI you linked
/// (virasoi-kitchen-assistant.onrender.com/swagger-ui) from this sandbox —
/// Render free-tier services sleep and this URL isn't publicly indexed, so
/// my web tools couldn't load the live spec.
///
/// Every endpoint the app calls is declared ONLY in this file. Open your
/// Swagger UI, compare the paths/params below to the real ones, and edit
/// strings here — no other file needs to change; every service reads its
/// paths from this class.
/// ============================================================================
class ApiConstants {
  ApiConstants._();

  /// Base REST url (Swagger "servers" value).
  static const String baseUrl = 'https://virasoi-kitchen-assistant.onrender.com';

  /// Base WS url — same host, ws(s) scheme.
  static const String baseWsUrl = 'wss://virasoi-kitchen-assistant.onrender.com';

  // ---------------------------------------------------------------------
  // AUTH (auth-controller)
  // ---------------------------------------------------------------------
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';

  // ---------------------------------------------------------------------
  // RECIPES (recipe-controller)
  // ---------------------------------------------------------------------
  static const String recipes = '/api/recipes';
  static String recipeById(String id) => '/api/recipes/$id';
  static const String searchRecipes = '/api/recipes/search';
  static const String generateRecipe = '/api/recipes/generate';
  static const String findOrGenerateRecipe = '/api/recipes/find-or-generate';
  static const String ancestorRecipe = '/api/recipes/ancestor';

  // ---------------------------------------------------------------------
  // COOKING SESSIONS (cooking-session-controller)
  // ---------------------------------------------------------------------
  static const String startSession = '/api/sessions/start';
  static String sessionById(String id) => '/api/sessions/$id';
  static String sessionStatus(String id) => '/api/sessions/$id/status';
  static String sessionDishes(String id) => '/api/sessions/$id/dishes';
  static String sessionTick(String id) => '/api/sessions/$id/tick';
  static String sessionStepWait(String sessionId, String stepId) => 
      '/api/sessions/$sessionId/steps/$stepId/wait';
  static String sessionStepTimerStart(String sessionId, String stepId) => 
      '/api/sessions/$sessionId/steps/$stepId/timer/start';
  static String sessionStepComplete(String sessionId, String stepId) => 
      '/api/sessions/$sessionId/steps/$stepId/complete';
  static String sessionStoveStatus(String sessionId, int stoveIndex) => 
      '/api/sessions/$sessionId/stoves/$stoveIndex';

  // ---------------------------------------------------------------------
  // SPEECH (speech-controller)
  // ---------------------------------------------------------------------
  static const String transcribe = '/api/speech/transcribe';
  static const String synthesize = '/api/speech/synthesize';

  // ---------------------------------------------------------------------
  // AI ASSISTANT (ai-controller)
  // ---------------------------------------------------------------------
  static const String aiCommand = '/api/ai/command';
  static const String aiPersonalize = '/api/ai/personalize-instruction';
  static const String aiHelp = '/api/ai/help';
  static const String aiHelpCommands = '/api/ai/help/commands';

  // ---------------------------------------------------------------------
  // UNSPLASH (ingredient / recipe photography)
  // ---------------------------------------------------------------------
  static const String unsplashBaseUrl = 'https://api.unsplash.com';
  static const String unsplashSearchPhotos = '/search/photos';
  static const String unsplashAccessKey = 'i9I0G5k1YeBMgiX5fsBa2LKwCMmgILMSI36mrP7hcbg';

  // ---------------------------------------------------------------------
  // VOICE ASSISTANT (WebSocket)
  // ---------------------------------------------------------------------
  /// Backend expects: /ws/audio?token=<jwt>&sessionId=<uuid>
  static String wsVoiceAssistant(String token, String sessionId) => 
      '$baseWsUrl/ws/audio?token=$token&sessionId=$sessionId';

  static const Duration requestTimeout = Duration(seconds: 20);
}
