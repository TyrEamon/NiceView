import 'package:flutter/material.dart';

class FloatingAdjacentButtons extends StatelessWidget {
  const FloatingAdjacentButtons({
    required this.enabled,
    required this.loadingDelta,
    required this.opacity,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final bool enabled;
  final int? loadingDelta;
  final double opacity;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity = enabled || loadingDelta != null ? opacity : 0.22;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: effectiveOpacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdjacentButton(
            icon: Icons.chevron_left_rounded,
            isLoading: loadingDelta == -1,
            onPressed: enabled ? onPrevious : null,
          ),
          const SizedBox(width: 10),
          _AdjacentButton(
            icon: Icons.chevron_right_rounded,
            isLoading: loadingDelta == 1,
            onPressed: enabled ? onNext : null,
          ),
        ],
      ),
    );
  }
}

class _AdjacentButton extends StatelessWidget {
  const _AdjacentButton({
    required this.icon,
    required this.isLoading,
    required this.onPressed,
  });

  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 46,
      child: Material(
        color: Colors.black.withValues(alpha: 0.56),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, size: 30),
          ),
        ),
      ),
    );
  }
}
