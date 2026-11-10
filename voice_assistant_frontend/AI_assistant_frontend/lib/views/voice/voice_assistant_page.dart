import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/result.dart';
import '../../models/chat_message_model.dart';
import '../../services/session_service.dart';
import '../../services/helper_assistant_launcher.dart';
import '../../services/voice_service.dart';
import '../../view_models/ingredient_viewmodel.dart';
import '../../view_models/voice_viewmodel.dart';

class VoiceAssistantPage extends StatefulWidget {
  final String? sessionId;
  final bool helpMode;

  /// True when the user just finished gathering ingredients: the cooking screen must first ask
  /// "are you ready?" and only add the dish (starting the scheduler) after a yes.
  final bool awaitingReady;

  /// Recipe id used to render the expandable steps panel with per-step progress.
  final String? recipeId;

  const VoiceAssistantPage({
    super.key,
    this.sessionId,
    this.helpMode = false,
    this.awaitingReady = false,
    this.recipeId,
  });

  @override
  State<VoiceAssistantPage> createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final VoiceViewModel _vm;
  IngredientViewModel? _ing;

  bool _showSteps = false;
  bool _isCancellingSession = false;
  int _selectedDish = 0;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vm = context.read<VoiceViewModel>();
    if (!widget.helpMode) {
      _vm.onHelpRequested = _openHelperAssistant;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _vm.init(widget.sessionId, helpMode: widget.helpMode);
      if (!mounted) return;

      if (widget.awaitingReady) {
        _ing = context.read<IngredientViewModel>();
        await _vm.beginReadyCheck(onReady: _handleUserReady);
      } else if (!widget.helpMode) {
        // Ask for the current state so the first cooking instruction is spoken immediately.
        _vm.requestStatus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _vm.pauseSessionHeartbeat();
    } else if (state == AppLifecycleState.resumed) {
      _vm.resumeSessionHeartbeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _textController.dispose();
    _scrollController.dispose();
    if (!widget.helpMode) _vm.onHelpRequested = null;
    _vm.detach();
    super.dispose();
  }

  /// Called by the voice view model when the user says "yes" to the ready question.
  Future<void> _handleUserReady() async {
    final ing = _ing;
    if (ing == null) {
      _vm.speakText('Sorry, the kitchen session is no longer available.');
      return;
    }
    final ok = await ing.startCooking();
    if (!mounted) return;

    if (ok) {
      _vm.requestStatus();
    } else {
      // Re-arm the question so the user can simply say "ready" again after the error.
      await _vm.beginReadyCheck(onReady: _handleUserReady, announce: false);
      _vm.speakText(ing.errorMessage ??
          "Sorry, I couldn't start cooking. Please try again.");
    }
  }

  void _sendTyped() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    _vm.sendTypedText(text);
  }

  Future<void> _confirmCancelSession() async {
    final sessionId = widget.sessionId;
    if (sessionId == null || widget.helpMode || _isCancellingSession) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End cooking session?'),
        content: const Text(
          'This will stop the session and clear its active timers and resource reservations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep cooking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancellingSession = true);
    await _vm.pause();
    final result = await SessionService().cancelSession(sessionId);
    if (!mounted) return;

    switch (result) {
      case Success():
        await _vm.detach();
        if (mounted) Navigator.of(context).pop();
        break;
      case Failure(message: final message):
        setState(() => _isCancellingSession = false);
        await _vm.startListening();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not end the session: $message')),
        );
        break;
    }
  }

  void _toggleMic() {
    if (_vm.mealComplete) return;
    if (_vm.state == VoiceState.listening) {
      _vm.stopListening();
    } else {
      _vm.startListening();
    }
  }

  Future<void> _openHelperAssistant() async {
    await _vm.pause();
    if (!mounted) return;
    await HelperAssistantLauncher.open(
      context,
      screenName: 'Cooking Assistant',
    );
    if (mounted && !widget.helpMode) {
      await _vm.startListening();
      // Catch up on anything the kitchen did while the helper overlay was open.
      _vm.requestStatus();
    }
  }

  String get _statusText {
    if (_vm.mealComplete) return 'Meal complete - happy meal!';
    return switch (_vm.state) {
          VoiceState.idle => 'Waiting for your command...',
          VoiceState.listening => "I'm listening...",
          VoiceState.thinking => 'Processing...',
          VoiceState.speaking => 'Speaking...',
        };
  }

  /// Connection / permission banner above the conversation (help mode never has a session
  /// socket to lose, so it only reports a denied microphone there too).
  Widget _buildNoticeBanner() {
    if (!widget.helpMode && !_vm.wsConnected) {
      return _noticeBanner(Icons.wifi_off_rounded,
          'Connection lost - reconnecting...', AppColors.error);
    }
    if (_vm.micPermissionDenied) {
      return _noticeBanner(
          Icons.mic_off_rounded,
          'Microphone access is off - enable it in settings to talk, or type your command below.',
          AppColors.warning);
    }
    return const SizedBox.shrink();
  }

  Widget _noticeBanner(IconData icon, String text, Color color) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.helpMode ? 'Helper Assistant' : 'Cooking Assistant'),
        actions: [
          if (!widget.helpMode)
            if (widget.sessionId != null)
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined),
                tooltip: 'End cooking session',
                onPressed: _isCancellingSession ? null : _confirmCancelSession,
              ),
          if (!widget.helpMode)
            IconButton(
              icon: Icon(
                _showSteps ? Icons.close_rounded : Icons.menu_book_rounded,
                color: _showSteps ? AppColors.primary : null,
              ),
              tooltip: 'Recipe steps',
              onPressed: () => setState(() => _showSteps = !_showSteps),
            ),
          if (!widget.helpMode)
            IconButton(
              icon: const Icon(Icons.support_agent_rounded),
              tooltip: 'Open helper',
              onPressed: _openHelperAssistant,
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _vm,
        builder: (context, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController
                  .jumpTo(_scrollController.position.maxScrollExtent);
            }
          });

          return Column(
            children: [
              // Expandable recipe-steps panel (top-right button toggles it).
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _showSteps
                    ? _buildStepsPanel()
                    : const SizedBox(width: double.infinity),
              ),

              // Connection / microphone notices, so a dead socket or a denied permission
              // never looks like the assistant is simply ignoring the user.
              _buildNoticeBanner(),

              // Conversation.
              Expanded(child: _buildChatList()),

              // Listening indicator ("symbol") above the input field.
              _buildStatusRow(),

              // WhatsApp-style input field with send + mic buttons.
              _buildInputRow(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChatList() {
    final items = _vm.transcript;

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.helpMode
                ? 'Ask me anything about how the app works.'
                : 'Say a command or type below to get started.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.4),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: items.length,
      itemBuilder: (_, i) => _ChatBubble(message: items[i]),
    );
  }

  Widget _buildStatusRow() {
    Widget icon;
    if (_vm.mealComplete) {
      icon = const Icon(Icons.check_circle_rounded,
          color: AppColors.primary, size: 20);
    } else {
      switch (_vm.state) {
      case VoiceState.listening:
        icon = ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.25).animate(_pulse),
          child: const Icon(Icons.graphic_eq_rounded,
              color: AppColors.primary, size: 20),
        );
      case VoiceState.thinking:
        icon = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.secondary),
        );
      case VoiceState.speaking:
        icon = const Icon(Icons.volume_up_rounded,
            color: AppColors.secondary, size: 18);
      case VoiceState.idle:
        icon = const Icon(Icons.mic_none_rounded,
            color: AppColors.textSecondary, size: 18);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 8),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _vm.mealComplete || _vm.state == VoiceState.listening
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow() {
    final live = _vm.liveTranscript;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border:
            Border(top: BorderSide(color: AppColors.divider.withOpacity(0.4))),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: live.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        child: Row(
                          children: [
                            const Icon(Icons.hearing_rounded,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                live,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : TextField(
                        controller: _textController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendTyped(),
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Type a command...',
                          hintStyle: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 15),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _sendTyped,
              tooltip: 'Send',
              icon: const Icon(Icons.send_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: _vm.mealComplete ? null : _toggleMic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _vm.state == VoiceState.listening
                      ? AppColors.error
                      : AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: (_vm.state == VoiceState.listening
                              ? AppColors.error
                              : AppColors.primary)
                          .withOpacity(0.35),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _vm.mealComplete
                      ? Icons.check_rounded
                      : _vm.state == VoiceState.listening
                          ? Icons.stop_rounded
                          : Icons.mic_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Recipe steps panel (one tab per dish, up to 4 dishes)
  // ---------------------------------------------------------------------

  List<Map<String, dynamic>> get _dishes {
    final raw = _vm.lastSnapshot?['dishes'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((dish) => Map<String, dynamic>.from(dish))
          .toList();
    }
    return const [];
  }

  static String _dishStatusLabel(String status) => switch (status) {
        'COMPLETED' => 'Done',
        'IN_PROGRESS' => 'Cooking',
        'CANCELLED' => 'Stopped',
        _ => 'Queued',
      };

  static Color _dishStatusColor(String status) => switch (status) {
        'COMPLETED' => AppColors.success,
        'IN_PROGRESS' => AppColors.primary,
        'CANCELLED' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  Widget _buildStepsPanel() {
    final dishes = _dishes;
    if (_selectedDish >= dishes.length) {
      _selectedDish = dishes.isEmpty ? 0 : dishes.length - 1;
    }
    final selected = dishes.isEmpty ? null : dishes[_selectedDish];
    final steps = (selected?['steps'] as List?)
            ?.whereType<Map>()
            .map((step) => Map<String, dynamic>.from(step))
            .toList() ??
        const <Map<String, dynamic>>[];
    final status = selected?['status']?.toString() ?? 'PENDING';
    final total = (selected?['totalSteps'] as num?)?.toInt() ?? steps.length;
    final done = (selected?['completedSteps'] as num?)?.toInt() ?? 0;
    final currentTask = _vm.lastSnapshot?['currentUserTask'];
    final currentInstruction =
        currentTask is Map ? currentTask['instruction']?.toString() : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.surfaceElevated, AppColors.surfaceCard],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.divider.withOpacity(0.6)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 18, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dishes.isEmpty
                      ? 'Recipe steps'
                      : 'Recipe steps · ${dishes.length} ${dishes.length == 1 ? 'dish' : 'dishes'}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (selected != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _dishStatusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _dishStatusLabel(status),
                    style: TextStyle(
                      color: _dishStatusColor(status),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (dishes.length > 1) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < dishes.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: i == _selectedDish,
                        onSelected: (_) => setState(() => _selectedDish = i),
                        avatar: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _dishStatusColor(
                                dishes[i]['status']?.toString() ?? 'PENDING'),
                          ),
                        ),
                        label: Text(
                          dishes[i]['dishName']?.toString() ?? 'Dish ${i + 1}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: total == 0 ? 0 : done / total,
                      backgroundColor: AppColors.surface,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  total == 0 || status == 'COMPLETED'
                      ? 'All $total steps done'
                      : 'Step ${(done + 1).clamp(1, total)} of $total',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (currentInstruction != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.restaurant_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentInstruction,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (dishes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Waiting for the first instruction...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: steps.length,
                itemBuilder: (_, i) => _StepTile(step: steps[i]),
              ),
            ),
        ],
      ),
    );
  }
}

String _stepClockLabel(Map<String, dynamic> step) {
  final remaining = step['secondsRemaining'];
  if (remaining is num) {
    final total = remaining.toInt();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
  if (step['status'] == 'TIMER_COMPLETED_AWAITING_USER') return 'Timer done';
  final seconds = step['timerSeconds'];
  if (seconds is num) return '${seconds.toInt()}s';
  return '';
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final Map<String, dynamic> step;

  @override
  Widget build(BuildContext context) {
    final status = step['status']?.toString() ?? 'PENDING';
    final done = status == 'COMPLETED';
    final cancelled = status == 'CANCELLED';
    final current = status == 'IN_PROGRESS' ||
        status == 'TIMER_RUNNING' ||
        status == 'TIMER_COMPLETED_AWAITING_USER';
    final timerRunning = status == 'TIMER_RUNNING';
    final stove = step['assignedStoveIndex'];
    final clock = _stepClockLabel(step);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            current ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              done
                  ? Icons.check_circle_rounded
                  : cancelled
                      ? Icons.cancel_rounded
                      : current
                          ? (timerRunning
                              ? Icons.timer_rounded
                              : Icons.radio_button_checked)
                          : Icons.radio_button_unchecked,
              size: 18,
              color: done
                  ? AppColors.success
                  : cancelled
                      ? AppColors.error
                      : current
                          ? AppColors.primary
                          : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step['instruction']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color:
                        done ? AppColors.textSecondary : AppColors.textPrimary,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (stove != null || clock.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 10,
                      children: [
                        if (stove != null)
                          Text(
                            'Stove $stove',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        if (clock.isNotEmpty)
                          Text(
                            clock,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: timerRunning
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: timerRunning
                                  ? AppColors.warning
                                  : AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessageModel message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == ChatSender.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primary.withOpacity(0.22)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                message.text,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.35,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
