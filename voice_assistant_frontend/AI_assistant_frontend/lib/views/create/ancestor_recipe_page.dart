import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../core/utils/result.dart';
import '../../core/utils/secure_storage.dart';
import '../../services/recipe_service.dart';
import '../../services/speech_service.dart';
import '../../view_models/recipe_list_viewmodel.dart';

class AncestorRecipePage extends StatefulWidget {
  const AncestorRecipePage({super.key});

  @override
  State<AncestorRecipePage> createState() => _AncestorRecipePageState();
}

class _AncestorRecipePageState extends State<AncestorRecipePage>
    with SingleTickerProviderStateMixin {
  static const _maxRecordingDuration = Duration(seconds: 55);
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _dishController = TextEditingController();
  final TextEditingController _contributorController = TextEditingController();
  final SpeechService _speechService = SpeechService();
  final RecipeService _recipeService = RecipeService();
  late final AnimationController _pulseController;

  Timer? _recordingTimer;
  String? _audioPath;
  bool _ownsAudioFile = false;
  bool _isRecording = false;
  bool _isUploading = false;
  Duration _recordedDuration = Duration.zero;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _pulseController.dispose();
    _dishController.dispose();
    _contributorController.dispose();
    if (_isRecording) {
      unawaited(_recorder.stop().then(_deleteIfOwned));
    }
    unawaited(_recorder.dispose());
    unawaited(_deleteOwnedAudio());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    unawaited(HapticFeedback.mediumImpact());
    if (_isUploading) return;
    if (_isRecording) {
      await _stopRecording();
      return;
    }

    final permissionGranted = await _recorder.hasPermission();
    if (!permissionGranted) {
      _showError('Allow microphone access to record an ancestor recipe.');
      return;
    }
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}${Platform.pathSeparator}'
        'ancestor_${DateTime.now().microsecondsSinceEpoch}.wav';
    try {
      await _deleteOwnedAudio();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _audioPath = path;
        _ownsAudioFile = true;
        _recordedDuration = Duration.zero;
        _errorMessage = null;
        _isRecording = true;
      });
      _pulseController.repeat(reverse: true);
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _recordedDuration += const Duration(seconds: 1);
        });
        if (_recordedDuration >= _maxRecordingDuration) {
          _stopRecording();
        }
      });
    } on Exception catch (error) {
      _showError('Could not start recording: $error');
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _audioPath = path ?? _audioPath;
        _isRecording = false;
      });
      _pulseController.stop();
      _pulseController.value = 0;
    } on Exception catch (error) {
      _showError('Could not finish the recording: $error');
    }
  }

  Future<void> _pickRecording() async {
    if (_isRecording || _isUploading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      _showError('The selected recording has no accessible file path.');
      return;
    }
    await _deleteOwnedAudio();
    if (!mounted) return;
    setState(() {
      _audioPath = path;
      _ownsAudioFile = false;
      _recordedDuration = Duration.zero;
      _errorMessage = null;
    });
  }

  Future<void> _saveAncestorRecipe() async {
    final path = _audioPath;
    if (path == null) {
      _showError('Record a recipe or choose a WAV file first.');
      return;
    }
    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final transcript = await _speechService.transcribeWav(File(path));
      if (!mounted) return;
      switch (transcript) {
        case Failure(message: final message):
          _showError(message);
          return;
        case Success(data: final text):
          final userId = await SecureStorage.instance.userId;
          if (userId == null || userId.isEmpty) {
            _showError(
                'Your account could not be identified. Please sign in again.');
            return;
          }
          final result = await _recipeService.uploadAncestorRecipe(
            transcriptText: text,
            dishNameHint: _dishController.text.trim(),
            createdBy: _contributorController.text.trim(),
            userId: userId,
          );
          if (!mounted) return;
          switch (result) {
            case Failure(message: final message):
              _showError(message);
              return;
            case Success(data: final recipe):
              await context.read<RecipeListViewModel>().load();
              if (!mounted) return;
              if (_ownsAudioFile) await _deleteOwnedAudio();
              if (!mounted) return;
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.recipeDetail,
                arguments: recipe.id,
              );
          }
      }
    } on Exception catch (error) {
      _showError('Could not save this ancestor recipe: $error');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteOwnedAudio() async {
    final path = _audioPath;
    if (!_ownsAudioFile || path == null) return;
    await _deletePath(path);
    _audioPath = null;
    _ownsAudioFile = false;
  }

  Future<void> _deleteIfOwned(String? path) async {
    if (_ownsAudioFile && path != null) await _deletePath(path);
  }

  Future<void> _deletePath(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  String get _durationLabel {
    final minutes = _recordedDuration.inMinutes.toString().padLeft(2, '0');
    final seconds =
        (_recordedDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _audioPath == null
        ? null
        : _audioPath!.split(Platform.pathSeparator).last;
    return Scaffold(
      appBar: AppBar(title: const Text('Add an ancestor recipe')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Preserve a family recipe',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Record the recipe or upload a WAV audio file. We transcribe it and turn it into a saved recipe with ingredients and steps.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _toggleRecording,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale =
                          _isRecording ? 1 + 0.1 * _pulseController.value : 1.0;
                      return Transform.scale(
                        scale: scale,
                        child: SizedBox(
                          width: 148,
                          height: 148,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_isRecording)
                                CustomPaint(
                                  size: const Size(148, 148),
                                  painter: _CircularWaveformPainter(
                                    progress: _pulseController.value,
                                    color: AppColors.primary,
                                  ),
                                ),
                              child!,
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 124,
                      height: 124,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording
                                    ? AppColors.error
                                    : AppColors.primary)
                                .withOpacity(0.35),
                            blurRadius: 28,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.black,
                        size: 48,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _isRecording
                      ? 'Recording · $_durationLabel'
                      : 'Tap to record',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  _isRecording
                      ? 'Tap the circle to stop'
                      : 'Recording stops automatically after 55 seconds',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: _isRecording || _isUploading ? null : _pickRecording,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Upload WAV recording'),
          ),
          if (fileName != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.audio_file_rounded,
                      color: AppColors.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(fileName,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Remove recording',
                    onPressed: _isUploading
                        ? null
                        : () async {
                            await _deleteOwnedAudio();
                            if (mounted) {
                              setState(() {
                                _audioPath = null;
                                _ownsAudioFile = false;
                              });
                            }
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _dishController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Dish name (optional)',
              prefixIcon: Icon(Icons.restaurant_menu_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contributorController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Recipe contributor (optional)',
              hintText: 'For example, Grandma Meena',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error, height: 1.35),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed:
                _isRecording || _isUploading ? null : _saveAncestorRecipe,
            icon: _isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_isUploading
                ? 'Transcribing and saving...'
                : 'Transcribe and save recipe'),
          ),
        ],
      ),
    );
  }
}

class _CircularWaveformPainter extends CustomPainter {
  const _CircularWaveformPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < 24; index++) {
      final angle = 2 * math.pi * index / 24;
      final wave = (math.sin(progress * 2 * math.pi + index * 0.65) + 1) / 2;
      final innerRadius = size.width * 0.42;
      final outerRadius = innerRadius + 3 + wave * 7;
      canvas.drawLine(
        center +
            Offset(
                math.cos(angle) * innerRadius, math.sin(angle) * innerRadius),
        center +
            Offset(
                math.cos(angle) * outerRadius, math.sin(angle) * outerRadius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularWaveformPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
