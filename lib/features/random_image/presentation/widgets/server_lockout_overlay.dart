import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/quota_state.dart';

class ServerLockoutOverlay extends StatelessWidget {
  const ServerLockoutOverlay({
    required this.quota,
    this.onRetryNow,
    this.onOpenSettings,
    super.key,
  });

  final QuotaState quota;
  final VoidCallback? onRetryNow;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (!quota.isServerLocked) {
      return const SizedBox.shrink();
    }

    final remaining = quota.serverLockoutRemaining;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(
          2,
          '0',
        );
    final label = '$minutes:$seconds';
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ModalBarrier(color: Colors.black, dismissible: false),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: niceText,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '请求暂时受限',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: niceText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '可能触发了 300s 请求限制，或当前网络/IP 被服务端限制。可以稍后再试，或切换网络、代理后立即重试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: niceMuted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  if (onRetryNow != null) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: onRetryNow,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: niceAmber,
                            side: const BorderSide(color: niceAmber),
                          ),
                          child: const Text('立即重试'),
                        ),
                        if (onOpenSettings != null)
                          TextButton(
                            onPressed: onOpenSettings,
                            child: const Text('设置代理'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
