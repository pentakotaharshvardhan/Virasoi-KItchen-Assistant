import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../services/voice_service.dart';
import '../../view_models/ingredient_viewmodel.dart';
import '../../view_models/voice_viewmodel.dart';
import '../../widgets/ingredient_flip_card.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/recipe_card_shimmer.dart';

class IngredientPage extends StatefulWidget {
  /// Every recipe of the meal - their ingredients are merged into one shopping list.
  final List<String> recipeIds;
  const IngredientPage({super.key, required this.recipeIds});

  @override
  State<IngredientPage> createState() => _IngredientPageState();
}

class _IngredientPageState extends State<IngredientPage>
    with WidgetsBindingObserver {
  late final IngredientViewModel _vm;
  late final VoiceViewModel _voiceVm;

  bool _navigating = false;
  bool _handingOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vm = context.read<IngredientViewModel>();
    _voiceVm = context.read<VoiceViewModel>();
    _vm.addListener(_onStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _vm.load(widget.recipeIds);
      // Automatically start voice assistant in background for gathering
      if (_vm.sessionId != null) {
        // "What's left on the list?" -> read out whatever is still pending.
        _voiceVm.onRemainingItemsRequest = () async => _vm.remainingNames;
        _voiceVm.onIngredientsRemoved = _onIngredientsRemovedByVoice;
        _voiceVm.onAvailableIngredients = () async => _vm.remainingNames;
        await _voiceVm.init(_vm.sessionId);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _voiceVm.pauseSessionHeartbeat();
    } else if (state == AppLifecycleState.resumed) {
      _voiceVm.resumeSessionHeartbeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vm.removeListener(_onStateChanged);
    _voiceVm.onRemainingItemsRequest = null;
    _voiceVm.onIngredientsRemoved = null;
    _voiceVm.onAvailableIngredients = null;
    // The cooking screen owns the mic after a hand-off; otherwise release it on the way out.
    if (!_handingOff) {
      _voiceVm.detach();
    }
    _vm.stopLiveSync();
    super.dispose();
  }

  void _onStateChanged() {
    // Auto-transition when all ingredients are confirmed.
    if (_navigating || _handingOff) return;
    if (!_vm.isDoneConfirming ||
        _vm.isLoading ||
        _vm.errorMessage != null ||
        !mounted) return;

    _navigating = true;
    Future.delayed(const Duration(milliseconds: 700), () async {
      if (!mounted || !_vm.isDoneConfirming) {
        _navigating = false;
        return;
      }
      await _goToCooking();
    });
  }

  /// Hands the session over to the cooking screen. Also reachable manually, so an ingredient
  /// that was never confirmed (the assistant failed to remove it, a photo never loaded, the
  /// session expired) can never leave the user stuck on this screen.
  Future<void> _goToCooking() async {
    if (_handingOff) return;
    _navigating = true;
    if (mounted) setState(() {});

    // Close our voice socket first so it doesn't speak the first cooking instruction; the
    // cooking screen reconnects and asks for the current snapshot itself.
    _handingOff = true;
    await _voiceVm.detach();
    if (!mounted) return;

    // Cooking does NOT start yet - the cooking screen first asks "are you ready?" and only
    // adds the dish (starting the scheduler) once the user says yes.
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.voiceAssistant,
      arguments: {
        'sessionId': _vm.sessionId,
        'awaitingReady': true,
        // The steps panel follows the first dish of the meal.
        'recipeId': widget.recipeIds.isNotEmpty ? widget.recipeIds.first : null,
      },
    );
  }

  /// Voice-driven removals land here: confirm the item and tell the user what changed so a
  /// silently-dropped acknowledgement is immediately visible.
  void _onIngredientsRemovedByVoice(List<String> names) {
    _vm.markConfirmedByNames(names);
    if (!mounted || names.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed from the list: ${names.join(', ')}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openHelpAssistant() async {
    await _voiceVm.pause();
    if (!mounted) return;
    await Navigator.pushNamed(
      context,
      AppRoutes.voiceAssistant,
      arguments: {'sessionId': _vm.sessionId, 'helpMode': true},
    );
    // Let the helper route finish disposing (it detaches the shared voice VM) before restarting.
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await _voiceVm.init(_vm.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IngredientViewModel>();
    final voice = context.watch<VoiceViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Gather Ingredients')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status Header
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.divider.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            voice.state == VoiceState.listening
                                ? Icons.mic_rounded
                                : Icons.record_voice_over_rounded,
                            color: voice.state == VoiceState.listening
                                ? AppColors.primary
                                : AppColors.secondary,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Voice Assistant Active: Say "remove [item]" to clear ingredients hands-free.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (vm.missingItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          'Missing: ${vm.missingItems.join(', ')}',
                          style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // The Grid
                    _buildGrid(vm),

                    const SizedBox(height: 24),

                    // Live Transcript UI
                    if (voice.liveTranscript.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hearing_rounded,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                voice.liveTranscript,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Manual escape hatch: the grid only auto-advances once everything is
                    // confirmed, so the user must always be able to move on regardless.
                    GradientButton(
                      label: vm.isDoneConfirming
                          ? 'Start cooking'
                          : 'Continue to cooking (${vm.pending.length} left)',
                      icon: Icons.soup_kitchen_rounded,
                      onPressed:
                          (_navigating || _handingOff || vm.isLoading)
                              ? null
                              : _goToCooking,
                    ),
                    const SizedBox(height: 12),

                    GradientButton(
                      label: 'Helper Assistant',
                      icon: Icons.support_agent_rounded,
                      onPressed: _openHelpAssistant,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(IngredientViewModel vm) {
    if (vm.isLoading) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.9,
        ),
        itemBuilder: (_, __) => const RecipeCardShimmer(),
      );
    }
    if (vm.errorMessage != null) {
      return Center(
          child: Text(vm.errorMessage!,
              style: const TextStyle(color: AppColors.textSecondary)));
    }
    if (vm.pending.isEmpty) {
      return const Center(
        child: Column(
          children: [
            SizedBox(height: 40),
            Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 48),
            SizedBox(height: 12),
            Text('Ready to cook!',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: vm.pending.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (_, i) {
        final item = vm.pending[i];
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: IngredientFlipCard(
            key: ValueKey(item.id),
            ingredient: item,
            showDishNames: vm.dishCount > 1,
          ),
        );
      },
    );
  }
}
