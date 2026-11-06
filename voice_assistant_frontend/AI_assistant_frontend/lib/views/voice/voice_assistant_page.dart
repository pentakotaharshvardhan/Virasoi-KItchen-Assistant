import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/chat_message_model.dart';
import '../../services/voice_service.dart';
import '../../view_models/voice_viewmodel.dart';
import '../../widgets/voice_orb.dart';

class VoiceAssistantPage extends StatefulWidget {
  final String? sessionId;
  final bool helpMode;
  const VoiceAssistantPage({super.key, this.sessionId, this.helpMode = false});

  @override
  State<VoiceAssistantPage> createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage> {
  late final VoiceViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<VoiceViewModel>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _vm.init(widget.sessionId, helpMode: widget.helpMode);
      // Ask for the current state so the first cooking instruction is spoken immediately.
      if (!widget.helpMode) _vm.requestStatus();
    });
  }

  @override
  void dispose() {
    _vm.detach();
    super.dispose();
  }

  void _openTranscriptSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4))),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text('Conversation (not saved)', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AnimatedBuilder(
                  animation: _vm,
                  builder: (context, _) => ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _vm.transcript.length,
                    itemBuilder: (_, i) => _ChatBubble(message: _vm.transcript[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.helpMode ? 'Helper Assistant' : 'Cooking Assistant'),
        actions: [
          IconButton(icon: const Icon(Icons.forum_outlined), tooltip: 'Show conversation', onPressed: _openTranscriptSheet),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: AnimatedBuilder(
                animation: _vm,
                builder: (context, _) {
                  return Column(
                    children: [
                      const SizedBox(height: 60),
                      VoiceOrb(state: _vm.state, size: 240),
                      const SizedBox(height: 28),
                      Text(
                        switch (_vm.state) {
                          VoiceState.idle => 'Waiting for your command...',
                          VoiceState.listening => 'I\'m listening...',
                          VoiceState.thinking => 'Processing...',
                          VoiceState.speaking => 'Speaking...',
                        },
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _vm.liveTranscript.isEmpty
                              ? (_vm.transcript.isEmpty ? '' : _vm.transcript.last.text)
                              : _vm.liveTranscript,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 60),
                      GestureDetector(
                        onTap: () {
                          if (_vm.state == VoiceState.listening) {
                            _vm.stopListening();
                          } else {
                            _vm.startListening();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _vm.state == VoiceState.listening ? null : AppColors.primaryGradient,
                            color: _vm.state == VoiceState.listening ? AppColors.error : null,
                            boxShadow: [
                              BoxShadow(
                                color: (_vm.state == VoiceState.listening ? AppColors.error : AppColors.primary).withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: Icon(
                            _vm.state == VoiceState.listening ? Icons.stop_rounded : Icons.mic_rounded, 
                            color: Colors.black, 
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  );
                },
              ),
            ),
          );
        },
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
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary.withOpacity(0.18) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(message.text, style: const TextStyle(fontSize: 14, height: 1.3)),
      ),
    );
  }
}
