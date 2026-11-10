import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/result.dart';
import '../../services/ai_service.dart';
import '../../services/voice_service.dart';

/// Temporary, in-memory helper chat shown as an overlay on top of the current screen.
///
/// Nothing here is persisted: the message list is cleared on dispose, no VoiceViewModel
/// transcript is touched, so the cooking assistant never shows helper questions or
/// ingredient-checklist chatter.
class HelperAssistantOverlay extends StatefulWidget {
  const HelperAssistantOverlay({
    super.key,
    required this.screenName,
    this.initialScreenshot,
    this.captureError,
    this.autoListen = true,
    this.aiService,
    this.voiceEngine,
  });

  final String screenName;
  final Uint8List? initialScreenshot;
  final String? captureError;
  final bool autoListen;
  final AiService? aiService;
  final VoiceEngine? voiceEngine;

  @override
  State<HelperAssistantOverlay> createState() => _HelperAssistantOverlayState();
}

class _HelperMessage {
  const _HelperMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class _HelperAssistantOverlayState extends State<HelperAssistantOverlay>
    with SingleTickerProviderStateMixin {
  static const _listenWindow = Duration(seconds: 12);
  static const _maxMessages = 30;

  static final _screenQuestion = RegExp(
    r'\b(this|current|my)\s+(screen|page|interface)\b|'
    r'\b(what|explain|describe|summari[sz]e)\b.{0,50}\b(screen|page|interface|displayed|seeing)\b|'
    r'\bwhat am i looking at\b|\bwhat is shown here\b|\bwhat does this\b|\bwhat is this\b',
    caseSensitive: false,
  );

  static final _closePhrase = RegExp(
    r"^(close|close it|close helper|close the helper|close assistant|dismiss|dismiss helper|exit|exit helper|go back|that is all|that's all|nothing else)\b",
    caseSensitive: false,
  );

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_HelperMessage> _messages = [];

  late final AiService _ai;
  late final VoiceEngine _voice;
  late final AnimationController _orbController;

  Uint8List? _screenImage;
  String? _screenSummary;
  String? _voiceError;
  String _spokenText = '';
  bool _isListening = false;
  bool _isSending = false;
  bool _isSpeaking = false;
  bool _autoListen = false;
  bool _finishingWindow = false;
  bool _intentionalStop = false;
  bool _forceScreenshot = false;
  Timer? _listenTimer;

  @override
  void initState() {
    super.initState();
    _voice = widget.voiceEngine ?? VoiceService();
    _ai = widget.aiService ?? AiService();
    _screenImage = widget.initialScreenshot;
    _autoListen = widget.autoListen;
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    if (_autoListen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
    }
  }

  @override
  void dispose() {
    _listenTimer?.cancel();
    _orbController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _messages.clear();
    _screenImage = null;
    unawaited(_voice.stopListening());
    // Never let a half-finished answer bleed into the cooking screen that resumes next.
    unawaited(_voice.stopSpeaking());
    _voice.dispose();
    super.dispose();
  }

  bool _isClosePhrase(String text) {
    final normalized = text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[.!?,]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return _closePhrase.hasMatch(normalized);
  }

  void _close() {
    _listenTimer?.cancel();
    _listenTimer = null;
    unawaited(_voice.stopListening());
    unawaited(_voice.stopSpeaking());
    if (mounted) Navigator.of(context).pop();
  }

  void _onVoiceStatus(String status) {
    if (_intentionalStop ||
        _finishingWindow ||
        !_isListening ||
        (status != 'done' && status != 'notListening')) {
      return;
    }
    _finishListenWindow();
  }

  Future<void> _startListening() async {
    if (_isListening || _isSending || _isSpeaking || !mounted) return;
    _voiceError = null;
    final granted = await _voice.requestMicPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _voiceError = 'Microphone access is off. You can type your question.';
        _autoListen = false;
      });
      return;
    }

    final ready = await _voice.initSpeech(
      onStatus: _onVoiceStatus,
      onError: (code, permanent) {
        if (!mounted) return;
        setState(() => _voiceError = permanent
            ? 'Voice input is unavailable. Type your question instead.'
            : null);
      },
    );
    if (!mounted) return;
    if (!ready) {
      setState(() {
        _voiceError = 'Voice input is unavailable. Type your question instead.';
        _autoListen = false;
      });
      return;
    }

    await HapticFeedback.lightImpact();
    setState(() {
      _isListening = true;
      _spokenText = '';
    });
    _listenTimer?.cancel();
    _listenTimer = Timer(_listenWindow, _finishListenWindow);
    try {
      await _voice.startListening(
        onResult: (text, isFinal) {
          if (!mounted || !_isListening) return;
          final recognized = text.trim();
          if (recognized.isEmpty) return;
          setState(() => _spokenText = recognized);
          if (isFinal) _finishListenWindow();
        },
      );
    } on Exception catch (error) {
      if (!mounted) return;
      _listenTimer?.cancel();
      setState(() {
        _isListening = false;
        _voiceError = 'Could not start voice input: $error';
      });
    }
  }

  Future<void> _finishListenWindow() async {
    if (!_isListening || _finishingWindow) return;
    _finishingWindow = true;
    _listenTimer?.cancel();
    _listenTimer = null;
    final spoken = _spokenText.trim();
    _intentionalStop = true;
    try {
      await _voice.stopListening();
    } finally {
      _intentionalStop = false;
      _finishingWindow = false;
    }
    if (!mounted) return;
    setState(() => _isListening = false);

    if (spoken.isEmpty) {
      if (_autoListen) _scheduleListening();
      return;
    }
    if (_isClosePhrase(spoken)) {
      _close();
      return;
    }
    await _sendQuestion(spoken, micAlreadyStopped: true);
  }

  Future<void> _stopListening({bool disableAutoListen = false}) async {
    _listenTimer?.cancel();
    _listenTimer = null;
    _intentionalStop = true;
    try {
      await _voice.stopListening();
    } finally {
      _intentionalStop = false;
    }
    if (!mounted) return;
    setState(() {
      _isListening = false;
      if (disableAutoListen) _autoListen = false;
    });
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening(disableAutoListen: true);
    } else {
      _autoListen = true;
      await _startListening();
    }
  }

  void _scheduleListening() {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted && _autoListen && !_isSending && !_isSpeaking) {
        _startListening();
      }
    }));
  }

  Future<void> _sendTypedQuestion() async {
    final question = _inputController.text.trim();
    if (question.isEmpty || _isSending) return;
    _inputController.clear();
    if (_isClosePhrase(question)) {
      _close();
      return;
    }
    await _sendQuestion(question);
  }

  Future<void> _sendQuestion(
    String question, {
    bool micAlreadyStopped = false,
  }) async {
    if (question.trim().isEmpty || _isSending) return;
    if (!micAlreadyStopped && _isListening) {
      await _stopListening();
    }
    if (!mounted) return;
    final trimmedQuestion = question.trim();
    final wantsScreenshot =
        _forceScreenshot || _screenQuestion.hasMatch(trimmedQuestion);
    final screenshot = wantsScreenshot ? _screenImage : null;
    setState(() {
      _isSending = true;
      _messages.add(_HelperMessage(text: trimmedQuestion, fromUser: true));
      _forceScreenshot = false;
      _trimMessages();
    });
    _scrollToBottom();

    final result = await _ai.askContextualHelp(
      question: trimmedQuestion,
      screenName: widget.screenName,
      screenSummary: _screenSummary,
      screenshot: screenshot,
    );
    if (!mounted) return;

    switch (result) {
      case Success(data: final answer):
        setState(() {
          _messages.add(_HelperMessage(text: answer, fromUser: false));
          if (screenshot != null) {
            _screenSummary = answer;
            _screenImage = null;
          }
          _voiceError = null;
        });
        _trimMessages();
        _scrollToBottom();
        setState(() => _isSending = false);
        await _speakAnswer(answer);
        return;
      case Failure(message: final message):
        debugPrint('Helper request failed: $message');
        setState(() {
          _messages.add(_HelperMessage(
            text: 'Sorry, I could not reach the helper right now. '
                'Please try again in a moment.',
            fromUser: false,
          ));
          _voiceError = 'Helper service unavailable. Please try again.';
          _isSending = false;
        });
        _trimMessages();
        _scrollToBottom();
        // Always answer out loud, even on failure, so the hands-free user gets a response.
        await _speakAnswer(
          'Sorry, I could not reach the helper right now. Please try again in a moment.',
        );
        return;
    }
  }

  Future<void> _speakAnswer(String answer) async {
    if (!mounted) return;
    setState(() => _isSpeaking = true);
    try {
      await _voice.synthesizeAndPlay(answer);
    } on Exception {
      // Text is already on screen; speech is a bonus.
    }
    if (!mounted) return;
    setState(() => _isSpeaking = false);
    if (_autoListen) _scheduleListening();
  }

  void _trimMessages() {
    if (_messages.length > _maxMessages) {
      _messages.removeRange(0, _messages.length - _maxMessages);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border:
                      Border.all(color: AppColors.primary.withOpacity(0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    if (_voiceError != null) _infoBanner(_voiceError!),
                    Flexible(
                      child: _messages.isEmpty
                          ? _welcomeView()
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount:
                                  _messages.length + (_isSending ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _messages.length) {
                                  return const _ThinkingBubble();
                                }
                                return _MessageBubble(
                                    message: _messages[index]);
                              },
                            ),
                    ),
                    if (_spokenText.isNotEmpty && _isListening)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 4),
                        child: Text(
                          _spokenText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    _buildComposer(),
                    _buildOrb(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                      child: Text(
                        'Temporary chat - it closes without being saved. Say "close" or tap X.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted.withOpacity(0.9),
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 10, 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.black, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Virasoi Helper',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Over ${widget.screenName}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close helper',
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _welcomeView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'How can I help?',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask about ${widget.screenName}, this app, or what you see on screen.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            if (widget.captureError != null && _screenImage == null) ...[
              const SizedBox(height: 10),
              Text(
                widget.captureError!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ],
            if (_screenImage != null) ...[
              const SizedBox(height: 10),
              const Text(
                'I can look at this screen if you ask about it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoBanner(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _buildComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendTypedQuestion(),
              decoration: InputDecoration(
                hintText: 'Ask about this app...',
                filled: true,
                fillColor: AppColors.surfaceElevated,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _forceScreenshot
                ? 'Screenshot will be attached'
                : 'Attach the screen to the next question',
            onPressed: _screenImage == null
                ? null
                : () => setState(() => _forceScreenshot = !_forceScreenshot),
            icon: Icon(
              _forceScreenshot
                  ? Icons.image_rounded
                  : Icons.add_photo_alternate_outlined,
              color: _forceScreenshot
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
          ),
          IconButton(
            tooltip: 'Send',
            onPressed: _isSending ? null : _sendTypedQuestion,
            icon: const Icon(Icons.send_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildOrb() {
    final label = _isSending
        ? 'Thinking...'
        : _isSpeaking
            ? 'Speaking...'
            : _isListening
                ? "I'm listening - say \"close\" to dismiss"
                : 'Tap to talk';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Column(
        children: [
          GestureDetector(
            onTap: _toggleListening,
            child: AnimatedBuilder(
              animation: _orbController,
              builder: (context, child) {
                final pulse =
                    _isListening ? 1 + _orbController.value * 0.06 : 1.0;
                return Transform.scale(scale: pulse, child: child);
              },
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _isListening
                      ? const LinearGradient(
                          colors: [AppColors.error, AppColors.primary])
                      : AppColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isListening ? AppColors.error : AppColors.primary)
                              .withOpacity(0.45),
                      blurRadius: 22,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening
                      ? Icons.stop_rounded
                      : _isSpeaking
                          ? Icons.volume_up_rounded
                          : Icons.mic_rounded,
                  color: Colors.black,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _isListening ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _HelperMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: fromUser
              ? AppColors.primary.withOpacity(0.18)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: fromUser
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.divider,
          ),
        ),
        child: Text(message.text, style: const TextStyle(height: 1.4)),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
