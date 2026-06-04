import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/top_snack_bar.dart';
import '../../random_image/presentation/random_image_controller.dart';
import '../domain/webdav_backup_file.dart';
import '../domain/webdav_config.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isTestingWebDav = false;
  bool _isUploadingWebDav = false;
  bool _isLoadingWebDavFiles = false;
  bool _isImportingWebDav = false;
  List<WebDavBackupFile> _webDavFiles = const [];

  bool get _isBusy =>
      _isExporting ||
      _isImporting ||
      _isTestingWebDav ||
      _isUploadingWebDav ||
      _isLoadingWebDavFiles ||
      _isImportingWebDav;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _webDavConfig.isConfigured) {
        unawaited(_loadWebDavFiles(silent: true));
      }
    });
  }

  WebDavConfig get _webDavConfig {
    return ref.read(randomImageControllerProvider.notifier).loadWebDavConfig();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(randomImageControllerProvider);
    final webDavConfig = _webDavConfig;
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
          const _SectionLabel('本地备份'),
          const SizedBox(height: 10),
          _BackupAction(
            title: '导出备份',
            subtitle: '保存收藏夹 JSON，不包含图片文件。',
            icon: Icons.file_upload_outlined,
            isLoading: _isExporting,
            onPressed: _isBusy && !_isExporting
                ? null
                : () => unawaited(_exportBackup()),
          ),
          const SizedBox(height: 12),
          _BackupAction(
            title: '导入备份',
            subtitle: '合并收藏夹；不会删除本机已有数据。',
            icon: Icons.file_download_outlined,
            isLoading: _isImporting,
            onPressed: _isBusy && !_isImporting
                ? null
                : () => unawaited(_importBackup()),
          ),
          const SizedBox(height: 22),
          const _SectionLabel('WebDAV'),
          const SizedBox(height: 10),
          _WebDavStatusCard(
            config: webDavConfig,
            onEdit: _isBusy ? null : () => unawaited(_openWebDavSettings()),
          ),
          const SizedBox(height: 12),
          _BackupAction(
            title: '测试连接',
            subtitle: webDavConfig.isConfigured
                ? '验证 WebDAV 地址和账号是否可用。'
                : '先填写 WebDAV 配置。',
            icon: Icons.cloud_done_outlined,
            isLoading: _isTestingWebDav,
            onPressed: !webDavConfig.isConfigured ||
                    (_isBusy && !_isTestingWebDav)
                ? null
                : () => unawaited(_testWebDavConnection()),
          ),
          const SizedBox(height: 12),
          _BackupAction(
            title: '上传到 WebDAV',
            subtitle: '把当前收藏夹备份到远端目录。',
            icon: Icons.cloud_upload_outlined,
            isLoading: _isUploadingWebDav,
            onPressed: !webDavConfig.isConfigured ||
                    (_isBusy && !_isUploadingWebDav)
                ? null
                : () => unawaited(_uploadWebDavBackup()),
          ),
          const SizedBox(height: 12),
          _BackupAction(
            title: '刷新远端备份',
            subtitle: '读取 WebDAV 目录中的 JSON 备份。',
            icon: Icons.sync_rounded,
            isLoading: _isLoadingWebDavFiles,
            onPressed:
                !webDavConfig.isConfigured || (_isBusy && !_isLoadingWebDavFiles)
                    ? null
                    : () => unawaited(_loadWebDavFiles()),
          ),
          const SizedBox(height: 12),
          _WebDavFileList(
            files: _webDavFiles,
            isLoading: _isLoadingWebDavFiles,
            onImport: _isBusy
                ? null
                : (file) => unawaited(_importWebDavBackup(file)),
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
      showTopSnackBar(context, '备份已保存：$target');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importBackup() async {
    final confirmed = await _confirmImport('导入会合并收藏夹，不会删除本机已有数据。');
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _isImporting = true);
    try {
      final summary =
          await ref.read(randomImageControllerProvider.notifier).importBackup();
      if (!mounted) {
        return;
      }
      _showImportSummary(summary);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _openWebDavSettings() async {
    final config = _webDavConfig;
    final updated = await showDialog<WebDavConfig>(
      context: context,
      builder: (context) => _WebDavSettingsDialog(config: config),
    );
    if (updated == null || !mounted) {
      return;
    }

    try {
      await ref
          .read(randomImageControllerProvider.notifier)
          .saveWebDavConfig(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _webDavFiles = const [];
      });
      showTopSnackBar(context, 'WebDAV 配置已保存');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _testWebDavConnection() async {
    setState(() => _isTestingWebDav = true);
    try {
      await ref
          .read(randomImageControllerProvider.notifier)
          .testWebDavConnection(_webDavConfig);
      if (!mounted) {
        return;
      }
      showTopSnackBar(context, 'WebDAV 连接正常');
      await _loadWebDavFiles(silent: true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isTestingWebDav = false);
      }
    }
  }

  Future<void> _uploadWebDavBackup() async {
    setState(() => _isUploadingWebDav = true);
    try {
      await ref
          .read(randomImageControllerProvider.notifier)
          .uploadBackupToWebDav();
      if (!mounted) {
        return;
      }
      showTopSnackBar(context, '已上传到 WebDAV');
      await _loadWebDavFiles(silent: true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isUploadingWebDav = false);
      }
    }
  }

  Future<void> _loadWebDavFiles({bool silent = false}) async {
    setState(() => _isLoadingWebDavFiles = true);
    try {
      final files = await ref
          .read(randomImageControllerProvider.notifier)
          .listWebDavBackups();
      if (!mounted) {
        return;
      }
      setState(() => _webDavFiles = files);
      if (!silent) {
        showTopSnackBar(context, '已找到 ${files.length} 个远端备份');
      }
    } catch (error) {
      if (!silent) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingWebDavFiles = false);
      }
    }
  }

  Future<void> _importWebDavBackup(WebDavBackupFile file) async {
    final confirmed = await _confirmImport(
      '将从 WebDAV 导入 ${file.name}，并合并收藏夹。',
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _isImportingWebDav = true);
    try {
      final summary = await ref
          .read(randomImageControllerProvider.notifier)
          .importWebDavBackup(file);
      if (!mounted) {
        return;
      }
      _showImportSummary(summary);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isImportingWebDav = false);
      }
    }
  }

  Future<bool> _confirmImport(String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF191A1C),
          title: const Text('导入备份'),
          content: Text(message),
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
    return confirmed == true;
  }

  void _showImportSummary(BackupImportSummary summary) {
    showTopSnackBar(
      context,
      '导入完成：收藏 ${summary.favoriteCount} 张'
      '（新增 ${summary.addedFavoriteCount} 张）',
    );
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    showTopSnackBar(context, error.toString());
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: const TextStyle(
        color: niceMuted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _WebDavStatusCard extends StatelessWidget {
  const _WebDavStatusCard({
    required this.config,
    required this.onEdit,
  });

  final WebDavConfig config;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final title = config.isConfigured ? '已配置 WebDAV' : '未配置 WebDAV';
    final subtitle = config.isConfigured
        ? '${config.baseUrl.trim()}${config.normalizedRemotePath}'
        : '填写地址、账号和远端目录后可同步备份。';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(
            config.isConfigured
                ? Icons.cloud_queue_rounded
                : Icons.cloud_off_outlined,
            color: niceMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: niceText,
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
          OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              foregroundColor: niceText,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(config.isConfigured ? '修改' : '配置'),
          ),
        ],
      ),
    );
  }
}

class _WebDavFileList extends StatelessWidget {
  const _WebDavFileList({
    required this.files,
    required this.isLoading,
    required this.onImport,
  });

  final List<WebDavBackupFile> files;
  final bool isLoading;
  final ValueChanged<WebDavBackupFile>? onImport;

  @override
  Widget build(BuildContext context) {
    if (isLoading && files.isEmpty) {
      return const SizedBox(
        height: 58,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (files.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Text(
          '暂无远端备份',
          style: TextStyle(color: niceMuted, fontSize: 13),
        ),
      );
    }
    return Column(
      children: [
        for (final file in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _WebDavFileTile(
              file: file,
              onImport: onImport == null ? null : () => onImport!(file),
            ),
          ),
      ],
    );
  }
}

class _WebDavFileTile extends StatelessWidget {
  const _WebDavFileTile({
    required this.file,
    required this.onImport,
  });

  final WebDavBackupFile file;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: OutlinedButton(
        onPressed: onImport,
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
            const Icon(Icons.description_outlined, color: niceMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fileMeta(file),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: niceMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.file_download_outlined, color: niceMuted),
          ],
        ),
      ),
    );
  }

  String _fileMeta(WebDavBackupFile file) {
    final parts = <String>[];
    final size = file.size;
    if (size != null) {
      parts.add(_formatSize(size));
    }
    final updatedAt = file.updatedAt;
    if (updatedAt != null) {
      parts.add(_formatTime(updatedAt.toLocal()));
    }
    return parts.isEmpty ? '点击导入' : parts.join(' · ');
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _WebDavSettingsDialog extends StatefulWidget {
  const _WebDavSettingsDialog({required this.config});

  final WebDavConfig config;

  @override
  State<_WebDavSettingsDialog> createState() => _WebDavSettingsDialogState();
}

class _WebDavSettingsDialogState extends State<_WebDavSettingsDialog> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _remotePathController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.config.baseUrl);
    _usernameController = TextEditingController(text: widget.config.username);
    _passwordController = TextEditingController(text: widget.config.password);
    _remotePathController = TextEditingController(
      text: widget.config.remotePath.isEmpty
          ? '/NiceView/'
          : widget.config.remotePath,
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remotePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF191A1C),
      title: const Text('WebDAV 设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogTextField(
              controller: _baseUrlController,
              label: '服务器地址',
              hintText: 'https://example.com/dav/',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            _DialogTextField(
              controller: _usernameController,
              label: '用户名',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '密码 / Token',
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _DialogTextField(
              controller: _remotePathController,
              label: '远端目录',
              hintText: '/NiceView/',
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      WebDavConfig(
        baseUrl: _baseUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        remotePath: _remotePathController.text,
      ),
    );
  }
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({
    required this.controller,
    required this.label,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
      ),
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
