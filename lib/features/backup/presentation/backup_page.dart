import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../random_image/presentation/random_image_controller.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(randomImageControllerProvider);
    return Scaffold(
      backgroundColor: niceBlack,
      appBar: AppBar(
        backgroundColor: niceBlack,
        foregroundColor: niceText,
        title: const Text('数据备份'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _BackupSummary(
            favoriteCount: state.favoriteImages.length,
          ),
          const SizedBox(height: 18),
          _BackupAction(
            title: '导出备份',
            subtitle: '保存收藏夹 JSON，不包含图片文件。',
            icon: Icons.file_upload_outlined,
            isLoading: _isExporting,
            onPressed: _isImporting ? null : () => unawaited(_exportBackup()),
          ),
          const SizedBox(height: 12),
          _BackupAction(
            title: '导入备份',
            subtitle: '合并收藏夹；不会删除本机已有数据。',
            icon: Icons.file_download_outlined,
            isLoading: _isImporting,
            onPressed: _isExporting ? null : () => unawaited(_importBackup()),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _isExporting = true);
    try {
      final target =
          await ref.read(randomImageControllerProvider.notifier).exportBackup();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份已保存：$target')),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF191A1C),
          title: const Text('导入备份'),
          content: const Text('导入会合并收藏夹，不会删除本机已有数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isImporting = true);
    try {
      final summary =
          await ref.read(randomImageControllerProvider.notifier).importBackup();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：收藏 ${summary.favoriteCount} 张'
            '（新增 ${summary.addedFavoriteCount} 张）',
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

class _BackupSummary extends StatelessWidget {
  const _BackupSummary({
    required this.favoriteCount,
  });

  final int favoriteCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(
              label: '收藏夹',
              value: '$favoriteCount 张',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: niceMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: niceText,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _BackupAction extends StatelessWidget {
  const _BackupAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: niceText,
          disabledForegroundColor: niceMuted,
          alignment: Alignment.centerLeft,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 28,
              child: Center(
                child: isLoading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Icon(icon, color: niceMuted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: niceMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, color: niceMuted),
          ],
        ),
      ),
    );
  }
}
