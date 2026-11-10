import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ScreenCaptureService {
  ScreenCaptureService._();

  static final GlobalKey boundaryKey = GlobalKey();

  static Future<Uint8List?> captureCurrentScreen() async {
    // `endOfFrame` never completes while the app is idle and no frame is scheduled
    // (e.g. tapping the helper icon on a static screen can otherwise hang the launcher
    // forever). Nudge a frame and cap the wait so the helper always opens.
    final binding = WidgetsBinding.instance;
    binding.scheduleFrame();
    await binding.endOfFrame
        .timeout(const Duration(milliseconds: 200), onTimeout: () {});
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || renderObject.size.isEmpty) {
      return null;
    }

    final ratio = (1024 / renderObject.size.width).clamp(0.1, 1.0).toDouble();
    final image = await renderObject.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
