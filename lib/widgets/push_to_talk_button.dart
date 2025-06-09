import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:closed_caption_companion/services/caption_service.dart';

class PushToTalkButton extends StatefulWidget {
  const PushToTalkButton({
    Key? key,
    required this.onPressDown,
    required this.onPressUp,
    this.enabled = true,
  }) : super(key: key);
  final VoidCallback onPressDown;
  final VoidCallback onPressUp;
  final bool enabled;

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handlePressDown() {
    if (!widget.enabled) return;

    final captionService = context.read<CaptionService>();

    // If in edit mode, handle as "finish edit" tap
    if (captionService.isEditMode) {
      captionService.finishEditing();
      return;
    }

    // Normal press-to-talk behavior
    setState(() {
      _isPressed = true;
    });
    _animationController.forward();
    widget.onPressDown();
  }

  void _handlePressUp() {
    if (!widget.enabled || !_isPressed) return;

    final captionService = context.read<CaptionService>();

    // Don't handle press up if in edit mode (since it's a tap, not hold)
    if (captionService.isEditMode) return;

    setState(() {
      _isPressed = false;
    });
    _animationController.reverse();
    widget.onPressUp();
  }

  @override
  Widget build(BuildContext context) {
    final captionService = context.watch<CaptionService>();
    final isActive = captionService.isStreaming || captionService.isConnecting;
    final isEditMode = captionService.isEditMode;

    // Button size - smaller for more text space
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = screenWidth * 0.35; // 35% of screen width (smaller)
    const minButtonSize = 120.0;
    const maxButtonSize = 180.0;
    final finalButtonSize = buttonSize.clamp(minButtonSize, maxButtonSize);

    return Semantics(
      button: true,
      label: isActive ? 'Release to stop' : 'Press and hold to start captions',
      hint: 'Push to talk button',
      child: GestureDetector(
        onTapDown: (_) => _handlePressDown(),
        onTapUp: (_) => _handlePressUp(),
        onTapCancel: () => _handlePressUp(),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: finalButtonSize,
                height: finalButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getButtonColor(context, isActive),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pulse animation when active
                    if (isActive)
                      _PulseAnimation(
                        size: finalButtonSize,
                        color: _getButtonColor(context, isActive),
                      ),

                    // Icon
                    Icon(
                      isEditMode
                          ? Icons.check
                          : isActive
                              ? Icons.mic
                              : Icons.mic_none,
                      size: finalButtonSize * 0.4,
                      color: Colors.white,
                    ),

                    // Loading indicator when connecting
                    if (captionService.isConnecting)
                      SizedBox(
                        width: finalButtonSize * 0.8,
                        height: finalButtonSize * 0.8,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),

                    // Status text
                    Positioned(
                      bottom: finalButtonSize * 0.15,
                      child: Text(
                        _getStatusText(captionService),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: finalButtonSize * 0.08,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getButtonColor(BuildContext context, bool isActive) {
    final captionService = context.watch<CaptionService>();

    if (!widget.enabled) {
      return Colors.grey;
    }
    if (captionService.isEditMode) {
      return Colors.green; // Green for "finish edit"
    }
    if (isActive) {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).primaryColor;
  }

  String _getStatusText(CaptionService captionService) {
    if (!widget.enabled) {
      return 'DISABLED';
    }
    if (captionService.isEditMode) {
      return 'FINISH EDIT';
    }
    if (captionService.isConnecting) {
      return 'CONNECTING...';
    }
    if (captionService.isStreaming) {
      return 'LISTENING';
    }
    return 'HOLD TO TALK';
  }
}

// Pulse animation widget
class _PulseAnimation extends StatefulWidget {
  const _PulseAnimation({
    required this.size,
    required this.color,
  });
  final double size;
  final Color color;

  @override
  State<_PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<_PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size * _animation.value,
          height: widget.size * _animation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withOpacity(0.5 * (2.2 - _animation.value)),
              width: 4,
            ),
          ),
        );
      },
    );
  }
}
