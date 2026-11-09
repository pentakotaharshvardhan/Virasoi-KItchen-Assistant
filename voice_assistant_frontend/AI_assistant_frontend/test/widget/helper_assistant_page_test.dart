import 'dart:typed_data';

import 'package:ai_assistant_frontend/core/utils/result.dart';
import 'package:ai_assistant_frontend/services/ai_service.dart';
import 'package:ai_assistant_frontend/services/helper_assistant_launcher.dart';
import 'package:ai_assistant_frontend/views/help/helper_assistant_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

class _ContextualAiService extends AiService {
  final List<Uint8List?> screenshots = [];

  @override
  Future<Result<String>> askContextualHelp({
    required String question,
    required String screenName,
    String? screenSummary,
    Uint8List? screenshot,
  }) async {
    screenshots.add(screenshot);
    return const Success('Try tapping Create.');
  }
}

void main() {
  testWidgets(
      'screenshots are sent only for screen questions and chat is local',
      (tester) async {
    final ai = _ContextualAiService();
    final screenshot = Uint8List.fromList([1, 2, 3]);
    final voice = FakeVoiceEngine();

    Widget page() => MaterialApp(
          home: HelperAssistantOverlay(
            screenName: 'Home',
            initialScreenshot: screenshot,
            autoListen: false,
            aiService: ai,
            voiceEngine: voice,
          ),
        );

    await tester.pumpWidget(page());
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'How do I start cooking?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(ai.screenshots.single, isNull);
    expect(find.text('Try tapping Create.'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField), 'What does this screen show?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(ai.screenshots.last, same(screenshot));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pump();

    expect(find.text('Try tapping Create.'), findsNothing);
  });

  testWidgets('typing close dismisses the overlay and returns to the page',
      (tester) async {
    final ai = _ContextualAiService();
    final voice = FakeVoiceEngine();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => HelperAssistantLauncher.open(
                  context,
                  screenName: 'Home',
                  autoListen: false,
                  aiService: ai,
                  voiceEngine: voice,
                ),
                child: const Text('Open helper'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open helper'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HelperAssistantOverlay), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'close');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HelperAssistantOverlay), findsNothing);
    expect(find.text('Open helper'), findsOneWidget);
    expect(ai.screenshots, isEmpty,
        reason: 'closing must not send anything to the AI');
  });
}
