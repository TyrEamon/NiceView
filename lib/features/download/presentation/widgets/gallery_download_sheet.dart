import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/top_snack_bar.dart';
import '../../../../services/download_service.dart';
import '../../domain/gallery_download_types.dart';
import '../gallery_download_controller.dart';

Future<void?> showGalleryDownloadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF17181A),
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (_) => const GalleryDownloadSheet(),
  );
}

class GalleryDownloadSheet extends ConsumerStatefulWidget {
  const GalleryDownloadSheet({super.key});

  @override
  ConsumerState<GalleryDownloadSheet> createState() =>
      _GalleryDownloadSheetState();
}

class _GalleryDownloadSheetState extends ConsumerState<GalleryDownloadSheet> {
  @override
  Widget build(BuildContext context) {
    ref.listen<GalleryDownloadResult?>(
      galleryDownloadControllerProvider.select((state) => state.result),
      (previous, next) {
        if (next == null || next.canceled || identical(previous, next)) {
          return;
        }
        showTopSnackBar(context, '下载完成：${next.success}/${next.total}');
      },
    );

    final state = ref.watch(galleryDownloadControllerProvider);
    final progress = _DisplayProgress.from(state);
    final status = _StatusPresentation.from(state, progress);
    final title = state.title?.trim().isNotEmpty == true
        ? state.title!.trim()
        : state.galleryId == null
            ? '图包下载'
            : '图包 #${state.galleryId}';
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, bottom + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: niceText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: state.isRunning ? '最小化' : '关闭',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                color: niceMuted,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            label: '下载进度 ${progress.done}/${progress.total}',
            value: progress.total <= 0
                ? '准备中'
                : '${(progress.value * 100).round()}%',
            child: LinearProgressIndicator(
              value: progress.total <= 0 ? null : progress.value,
              minHeight: 6,
              color: niceAmber,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${progress.done}/${progress.total}',
                style: const TextStyle(
                  color: niceText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (progress.secondaryStats != null)
                Flexible(
                  child: Text(
                    progress.secondaryStats!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: niceMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
          if (progress.assumptionBroken) ...[
            const SizedBox(height: 8),
            const Text(
              '图包结构未完全匹配，已降级下载已知图片',
              style: TextStyle(color: niceMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          _StatusArea(
            presentation: status,
            onCancel: () {
              ref.read(galleryDownloadControllerProvider.notifier).cancel();
            },
            onRetry: () {
              unawaited(
                ref.read(galleryDownloadControllerProvider.notifier).retryFailed(),
              );
            },
            onClose: () => Navigator.of(context).maybePop(),
            onOpenFolder: () {
              showTopSnackBar(context, _targetPathFor(state));
            },
          ),
        ],
      ),
    );
  }

  String _targetPathFor(GalleryDownloadUiState state) {
    final raw = state.title?.trim().isNotEmpty == true
        ? state.title!.trim()
        : 'gallery_${state.galleryId ?? 'unknown'}';
    return 'Pictures/NiceView/${sanitizeFileName(raw)}';
  }
}

class _StatusArea extends StatelessWidget {
  const _StatusArea({
    required this.presentation,
    required this.onCancel,
    required this.onRetry,
    required this.onClose,
    required this.onOpenFolder,
  });

  final _StatusPresentation presentation;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          presentation.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: presentation.color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final action in presentation.actions)
              _SheetActionButton(
                label: action.label,
                primary: action.primary,
                onPressed: _handlerFor(action.kind),
              ),
          ],
        ),
      ],
    );
  }

  VoidCallback _handlerFor(_ActionKind kind) {
    return switch (kind) {
      _ActionKind.cancel => onCancel,
      _ActionKind.retry => onRetry,
      _ActionKind.close => onClose,
      _ActionKind.openFolder => onOpenFolder,
    };
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.label,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: niceAmber,
            foregroundColor: niceBlack,
            minimumSize: const Size(88, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: niceText,
            minimumSize: const Size(76, 44),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );

    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _DisplayProgress {
  const _DisplayProgress({
    required this.done,
    required this.total,
    required this.success,
    required this.skipped,
    required this.failed,
    required this.assumptionBroken,
  });

  factory _DisplayProgress.from(GalleryDownloadUiState state) {
    final progress = state.progress;
    final result = state.result;
    final success = progress?.success ?? result?.success ?? 0;
    final skipped = progress?.skipped ?? result?.skipped ?? 0;
    final failed = progress?.failed ?? result?.failed ?? 0;
    final done = progress?.done ?? success + skipped + failed;
    return _DisplayProgress(
      done: done,
      total: progress?.total ?? result?.total ?? 0,
      success: success,
      skipped: skipped,
      failed: failed,
      assumptionBroken:
          progress?.assumptionBroken ?? result?.assumptionBroken ?? false,
    );
  }

  final int done;
  final int total;
  final int success;
  final int skipped;
  final int failed;
  final bool assumptionBroken;

  double get value {
    if (total <= 0) {
      return 0;
    }
    return (done / total).clamp(0.0, 1.0).toDouble();
  }

  String? get secondaryStats {
    final stats = <String>[];
    if (skipped > 0) {
      stats.add('跳过 $skipped');
    }
    if (failed > 0) {
      stats.add('失败 $failed');
    }
    return stats.isEmpty ? null : stats.join(' · ');
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.message,
    required this.color,
    required this.actions,
  });

  factory _StatusPresentation.from(
    GalleryDownloadUiState state,
    _DisplayProgress progress,
  ) {
    final error = state.error;
    if (error != null) {
      return _StatusPresentation(
        message: '出错：$error',
        color: niceDanger,
        actions: const [
          _SheetAction('重试', _ActionKind.retry, primary: true),
          _SheetAction('关闭', _ActionKind.close),
        ],
      );
    }

    final result = state.result;
    final status = state.progress?.status;
    if (result?.canceled == true || status == GalleryDownloadStatus.canceled) {
      return _StatusPresentation(
        message: '已取消（已下${progress.success}张保留）',
        color: niceMuted,
        actions: const [_SheetAction('关闭', _ActionKind.close)],
      );
    }

    if (result != null || status == GalleryDownloadStatus.done) {
      return _StatusPresentation(
        message:
            '完成 · 成功${progress.success}/跳过${progress.skipped}/失败${progress.failed}',
        color: niceAmber,
        actions: [
          const _SheetAction('打开文件夹', _ActionKind.openFolder),
          if (progress.failed > 0)
            const _SheetAction('重试失败', _ActionKind.retry, primary: true),
        ],
      );
    }

    if (status == GalleryDownloadStatus.lockout) {
      final remaining = state.progress?.lockoutRemaining ?? Duration.zero;
      final seconds = remaining.inSeconds <= 0 ? 1 : remaining.inSeconds;
      if (remaining < const Duration(minutes: 1)) {
        return _StatusPresentation(
          message: '请求较快，暂停中 · ${seconds}s 后继续',
          color: niceAmber,
          actions: const [_SheetAction('取消', _ActionKind.cancel)],
        );
      }
      return _StatusPresentation(
        message: '已触发服务器限制，剩 ${_formatMinuteSecond(remaining)}',
        color: niceDanger,
        actions: const [_SheetAction('取消', _ActionKind.cancel)],
      );
    }

    return _StatusPresentation(
      message: state.isRunning ? '下载中…' : '等待下载开始',
      color: niceText,
      actions: state.isRunning
          ? const [_SheetAction('取消', _ActionKind.cancel)]
          : const [_SheetAction('关闭', _ActionKind.close)],
    );
  }

  final String message;
  final Color color;
  final List<_SheetAction> actions;
}

class _SheetAction {
  const _SheetAction(
    this.label,
    this.kind, {
    this.primary = false,
  });

  final String label;
  final _ActionKind kind;
  final bool primary;
}

enum _ActionKind {
  cancel,
  retry,
  close,
  openFolder,
}

String _formatMinuteSecond(Duration duration) {
  final seconds = duration.inSeconds <= 0 ? 0 : duration.inSeconds;
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final remain = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remain';
}
