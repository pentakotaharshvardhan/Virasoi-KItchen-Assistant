import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../views/help/helper_assistant_overlay.dart';
import 'ai_service.dart';
import 'screen_capture_service.dart';
import 'voice_service.dart';

class HelperAssistantLauncher {
  HelperAssistantLauncher._();

  /// Opens the helper as a temporary overlay on top of the current screen (blurred backdrop,
  /// no navigation), so the user keeps their place. The screenshot is captured before the
  /// overlay is shown; nothing about the conversation is saved.
  static Future<void> open(
    BuildContext context, {
    required String screenName,
    bool autoListen = true,
    AiService? aiService,
    VoiceEngine? voiceEngine,
  }) async {
    // Fire-and-forget: haptics are a nicety and some platforms never reply.
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    Uint8List? screenshot;
    String? captureError;
    try {
      screenshot = await ScreenCaptureService.captureCurrentScreen()
          .timeout(const Duration(seconds: 2));
      if (screenshot == null) {
        captureError = 'This screen could not be captured.';
      }
    } on Exception {
      captureError = 'This screen could not be captured.';
    }

    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Helper assistant',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: Container(color: Colors.black.withOpacity(0.5)),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: HelperAssistantOverlay(
                screenName: screenName,
                initialScreenshot: screenshot,
                captureError: captureError,
                autoListen: autoListen,
                aiService: aiService,
                voiceEngine: voiceEngine,
              ),
            ),
          ],
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
