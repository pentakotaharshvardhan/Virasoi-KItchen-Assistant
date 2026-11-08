import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/result.dart';
import '../../services/ai_service.dart';
import '../../services/voice_service.dart';

class HelperAssistantPage extends StatefulWidget {
  const HelperAssistantPage({
    super.key,
    required this.screenName,
    this.initialScreenshot,
    this.captureError,
    this.autoListen = false,
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
  State<HelperAssistantPage> createState() => _HelperAssistantPageState();
}

class _HelperMessage {
  const _HelperMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class _HelperAssistantPageState extends State<HelperAssistantPage>
    with SingleTickerProviderStateMixin {
  static const _listenWindow = Duration(seconds: 12);
  static const _maxMessages = 40;
  static final _screenQuestion = RegExp(
    r'\b(this|current|my)\s+(screen|page|interface)\b|'
    r'\b(what|explain|describe|summari[sz]e)\b.{0,50}\b(screen|page|interface|displayed|seeing)\b|'
    r'\bwhat am i looking at\b|\bwhat is shown here\b|\bwhat does this\b|\bwhat is this\b',
    caseSensitive: false,
  );

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AiService _ai;
  final List<_HelperMessage> _messages = [];

  late final VoiceEngine _voice;
  late final AnimationController _orbController;
  Uint8List? _screenImage;
  String? _screenSummary;
  String? _voiceError;
  String _spokenText = '';
  bool _isListening = false;
  bool _isSending = false;
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
    _voice.dispose();
    super.dispose();
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
    if (_isListening || _isSending || !mounted) return;
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
    if (spoken.isNotEmpty) {
      await _sendQuestion(spoken, micAlreadyStopped: true);
    } else if (_autoListen) {
      _scheduleListening();
    }
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
      if (mounted && _autoListen && !_isSending) _startListening();
    }));
  }

  Future<void> _sendTypedQuestion() async {
    final question = _inputController.text.trim();
    if (question.isEmpty || _isSending) return;
    _inputController.clear();
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
      case Failure(message: final message):
        setState(() => _messages.add(_HelperMessage(
              text: 'I could not get an answer: $message',
              fromUser: false,
            )));
    }
    setState(() => _isSending = false);
    _trimMessages();
    _scrollToBottom();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Virasoi Helper'),
        actions: [
          IconButton(
            tooltip: _screenImage == null
                ? 'No screen screenshot available'
                : 'Attach screenshot to the next question',
            onPressed: _screenImage == null
                ? null
                : () => setState(() => _forceScreenshot = !_forceScreenshot),
            icon: Icon(
              _forceScreenshot
                  ? Icons.image_rounded
                  : Icons.add_photo_alternate_outlined,
              color: _forceScreenshot ? AppColors.primary : null,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.captureError != null && _screenImage == null)
            _infoBanner(widget.captureError!),
          if (_voiceError != null) _infoBanner(_voiceError!),
          Expanded(
            child: _messages.isEmpty
                ? _welcomeView()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _ThinkingBubble();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          if (_spokenText.isNotEmpty && _isListening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text(
                _spokenText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          _buildComposer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
            child: Text(
              'Chat is temporary and cleared when you close this screen. Questions are sent to Gemini for answers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.9), fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcomeView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _orbController,
              builder: (context, child) => Transform.scale(
                scale: 0.96 + _orbController.value * 0.08,
                child: child,
              ),
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.black, size: 38),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'How can I help?',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask about ${widget.screenName}, a recipe, voice commands, or how cooking works.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            if (_screenImage != null) ...[
              const SizedBox(height: 14),
              const Text(
                'I can inspect this screen if you ask about what you see.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendTypedQuestion(),
                decoration: InputDecoration(
                  hintText: 'Ask about this app...',
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Send',
              onPressed: _isSending ? null : _sendTypedQuestion,
              icon: const Icon(Icons.send_rounded, color: AppColors.primary),
            ),
            GestureDetector(
              onTap: _toggleListening,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? AppColors.error : AppColors.primary,
                ),
                child: Icon(
                  _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: fromUser
              ? AppColors.primary.withOpacity(0.18)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(18),
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
        padding: EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
