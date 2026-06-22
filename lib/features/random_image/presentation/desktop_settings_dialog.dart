import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../services/desktop_settings.dart';

Future<void> showDesktopSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const DesktopSettingsDialog(),
  );
}

class DesktopSettingsDialog extends ConsumerStatefulWidget {
  const DesktopSettingsDialog({super.key});

  @override
  ConsumerState<DesktopSettingsDialog> createState() =>
      _DesktopSettingsDialogState();
}

class _DesktopSettingsDialogState
    extends ConsumerState<DesktopSettingsDialog> {
  late bool _proxyEnabled;
  late final TextEditingController _proxyHostController;
  late final TextEditingController _proxyPortController;
  late final TextEditingController _downloadDirectoryController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(desktopSettingsProvider);
    _proxyEnabled = settings.proxyEnabled;
    _proxyHostController = TextEditingController(text: settings.proxyHost);
    _proxyPortController =
        TextEditingController(text: settings.proxyPort.toString());
    _downloadDirectoryController =
        TextEditingController(text: settings.downloadDirectory ?? '');
  }

  @override
  void dispose() {
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _downloadDirectoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF191A1C),
      title: const Text('桌面设置'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(
                title: '代理',
                trailing: Switch(
                  value: _proxyEnabled,
                  activeColor: niceAmber,
                  onChanged: (value) {
                    setState(() => _proxyEnabled = value);
                  },
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _proxyHostController,
                enabled: _proxyEnabled,
                style: const TextStyle(color: niceText),
                decoration: _inputDecoration(
                  label: '主机',
                  hint: DesktopSettings.defaultProxyHost,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _proxyPortController,
                enabled: _proxyEnabled,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: niceText),
                decoration: _inputDecoration(
                  label: 'HTTP/Mixed 端口',
                  hint: DesktopSettings.defaultProxyPort.toString(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '只代理 veil.ortlinde.com 请求。v2rayN 通常填 127.0.0.1 和 HTTP/Mixed 本地端口，例如 10808。',
                style: TextStyle(color: niceMuted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(title: '下载位置'),
              const SizedBox(height: 10),
              TextField(
                controller: _downloadDirectoryController,
                style: const TextStyle(color: niceText),
                decoration: _inputDecoration(
                  label: '桌面端下载目录',
                  hint: _defaultDownloadHint,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '留空则使用系统下载目录下的 NiceView。整包下载会继续按图包标题创建子目录。',
                style: TextStyle(color: niceMuted, fontSize: 12, height: 1.4),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: niceDanger, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _downloadDirectoryController.clear();
              _error = null;
            });
          },
          child: const Text('下载位置恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final port = int.tryParse(_proxyPortController.text.trim());
    if (_proxyEnabled && (port == null || port <= 0 || port > 65535)) {
      setState(() => _error = '代理端口必须是 1-65535 之间的数字');
      return;
    }

    final directory = _downloadDirectoryController.text.trim();
    if (directory.isNotEmpty) {
      try {
        final target = Directory(directory);
        if (await target.exists()) {
          final stat = await target.stat();
          if (stat.type != FileSystemEntityType.directory) {
            setState(() => _error = '下载位置必须是文件夹路径');
            return;
          }
        }
      } on FileSystemException catch (error) {
        setState(() => _error = error.message);
        return;
      }
    }

    await ref.read(desktopSettingsProvider.notifier).save(
          DesktopSettings(
            proxyEnabled: _proxyEnabled,
            proxyHost: _proxyHostController.text,
            proxyPort: port ?? DesktopSettings.defaultProxyPort,
            downloadDirectory: directory.isEmpty ? null : directory,
          ),
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: niceText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

const _defaultDownloadHint = r'C:\Users\<你>\Downloads\NiceView';
