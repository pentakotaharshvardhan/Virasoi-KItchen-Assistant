import 'package:ai_assistant_frontend/core/utils/secure_storage.dart';
import 'package:ai_assistant_frontend/view_models/voice_viewmodel.dart';
import 'package:ai_assistant_frontend/views/voice/voice_assistant_page.dart';
import 'package:ai_assistant_frontend/widgets/voice_orb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeVoiceEngine voice;
  late FakeAiService ai;
  late FakeWebSocket ws;
  late VoiceViewModel vm;

  setUp(() {
    voice = FakeVoiceEngine();
    ai = FakeAiService();
    ws = FakeWebSocket();
    vm = VoiceViewModel(
      voice: voice,
      aiService: ai,
      storage: SecureStorage.inMemory(),
      wsFactory: (url, token) => ws,
    );
  });

  Widget harness({bool helpMode = false}) =>
      ChangeNotifierProvider<VoiceViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: VoiceAssistantPage(sessionId: 'sess-ui', helpMode: helpMode),
        ),
      );

  /// The VoiceOrb animates forever, so `pumpAndSettle` can never be used here.
  Future<void> start(WidgetTester tester, {bool helpMode = false}) async {
    await tester.pumpWidget(harness(helpMode: helpMode));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> finish(WidgetTester tester) async {
    vm.stopListening();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  }

  testWidgets('renders the orb and starts listening automatically', (tester) async {
    await start(tester);

    expect(find.byType(VoiceOrb), findsOneWidget);
    expect(find.text("I'm listening..."), findsOneWidget);
    expect(voice.startCalls, greaterThanOrEqualTo(1));

    await finish(tester);
  });

  testWidgets('shows the helper title in help mode', (tester) async {
    await start(tester, helpMode: true);

    expect(find.text('Helper Assistant'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('tapping the mic while listening stops the session', (tester) async {
    await start(tester);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();

    expect(find.text('Waiting for your command...'), findsOneWidget);
    expect(voice.listening, isFalse);

    await finish(tester);
  });

  testWidgets('tapping the mic while idle starts listening again', (tester) async {
    await start(tester);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(find.text("I'm listening..."), findsOneWidget);

    await finish(tester);
  });

  testWidgets('opens the in-memory conversation sheet', (tester) async {
    await start(tester);

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Conversation (not saved)'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('renders an assistant response from the server', (tester) async {
    await start(tester);

    ws.emit({'type': 'text', 'text': 'Add the paneer now.'});
    await tester.pump();
    await tester.pump();

    expect(find.text('Add the paneer now.'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('renders a live transcript while the user speaks', (tester) async {
    await start(tester);

    voice.emitResult('I have onions');
    await tester.pump();

    expect(find.text('I have onions'), findsOneWidget);

    await finish(tester);
  });
}
