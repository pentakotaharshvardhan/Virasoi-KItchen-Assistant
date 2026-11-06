import 'dart:math';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../services/voice_service.dart';

/// The big circular indicator on the Voice Assistant screen.
///
/// RIVE INTEGRATION (recommended upgrade):
/// Create a single .riv file named `assets/rive/voice_orb.riv` with a
/// State Machine called "OrbStateMachine" that exposes ONE number input
/// named "state" with 4 values this widget will drive:
///   0 = idle       -> a slow ambient breathing loop
///   1 = listening   -> ring pulses outward in teal, reacting like a
///                       waveform (loop, driven purely by the state machine
///                       time, no audio-level input needed)
///   2 = thinking    -> a rotating "processing" ring / dot orbit, amber
///   3 = speaking    -> a punchier pulse in warm orange, slightly faster
/// Nest 4 timeline animations (Idle, Listening, Thinking, Speaking) as
/// states in the state machine, bound to that "state" number input, with
/// 200ms cross-fade transitions between each. Export at 400x400 canvas.
///
/// Until that .riv asset is dropped in, this widget renders a hand-built
/// Flutter equivalent below (same 4 states) so the screen is fully
/// functional without Rive assets present.
class VoiceOrb extends StatefulWidget {
  final VoiceState state;
  final double size;
  const VoiceOrb({super.key, required this.state, this.size = 220});

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.state) {
        VoiceState.idle => AppColors.textMuted,
        VoiceState.listening => AppColors.secondary,
        VoiceState.thinking => AppColors.warning,
        VoiceState.speaking => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _OrbPainter(state: widget.state, t: t, color: _color),
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  final VoiceState state;
  final double t; // 0..1 looping
  final Color color;
  _OrbPainter({required this.state, required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;

    // Ambient rings
    final ringCount = state == VoiceState.idle ? 1 : 3;
    for (int i = 0; i < ringCount; i++) {
      final phase = (t + i / ringCount) % 1.0;
      final radius = maxR * 0.42 + (maxR * 0.5) * phase;
      final opacity = (1 - phase).clamp(0.0, 1.0) * (state == VoiceState.idle ? 0.15 : 0.35);
      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      canvas.drawCircle(center, radius, paint);
    }

    // Core
    final coreRadius = maxR * 0.42 + (state == VoiceState.speaking ? sin(t * 2 * pi) * 6 : 0);
    final corePaint = Paint()
      ..shader = RadialGradient(colors: [color.withOpacity(0.9), color.withOpacity(0.35)])
          .createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    // Thinking: orbiting dot
    if (state == VoiceState.thinking) {
      final angle = t * 2 * pi;
      final dotCenter = center + Offset(cos(angle), sin(angle)) * (coreRadius + 14);
      canvas.drawCircle(dotCenter, 5, Paint()..color = color);
    }

    // Center icon-ish glyph
    final iconPaint = Paint()..color = Colors.black.withOpacity(0.75);
    if (state == VoiceState.listening) {
      // simple mic bars
      for (int i = -1; i <= 1; i++) {
        final h = coreRadius * (0.35 + 0.15 * sin(t * 2 * pi + i));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center + Offset(i * 10, 0), width: 6, height: h),
            const Radius.circular(3),
          ),
          iconPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) => true;
}
