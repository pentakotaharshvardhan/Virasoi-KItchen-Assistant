import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../views/help/helper_assistant_page.dart';
import 'screen_capture_service.dart';

class HelperAssistantLauncher {
  HelperAssistantLauncher._();

  static Future<void> open(
    BuildContext context, {
    required String screenName,
    bool autoListen = true,
  }) async {
    await HapticFeedback.mediumImpact();
    Uint8List? screenshot;
    String? captureError;
    try {
      screenshot = await ScreenCaptureService.captureCurrentScreen();
      if (screenshot == null) {
        captureError = 'This screen could not be captured.';
      }
    } on Exception {
      captureError = 'This screen could not be captured.';
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HelperAssistantPage(
          screenName: screenName,
          initialScreenshot: screenshot,
          captureError: captureError,
          autoListen: autoListen,
        ),
      ),
    );
  }
}
