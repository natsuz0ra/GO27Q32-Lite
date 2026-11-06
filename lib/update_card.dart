import 'package:flutter/material.dart';

import 'core/updates.dart';
import 'desktop.dart';
import 'l10n.dart';
import 'version.dart';

class UpdateControls extends StatefulWidget {
  const UpdateControls({super.key, this.checker});
  final UpdateChecker? checker;
  @override
  State<UpdateControls> createState() => _UpdateControlsState();
}

class _UpdateControlsState extends State<UpdateControls> {
  bool checking = false;
  UpdateResult? result;
  String? error;

  Future<void> check() async {
    setState(() {
      checking = true;
      error = null;
      result = null;
    });
    try {
      final found = await (widget.checker ?? UpdateChecker()).check();
      if (mounted) setState(() => result = found);
    } catch (_) {
      if (mounted) {
        setState(() => error = '无法检查更新，请检查网络后重试，或到 GitHub Release 查看。');
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> openRelease() async {
    try {
      await Desktop.call(
        'openRelease',
        result?.url.toString() ?? '$projectUrl/releases',
      );
    } catch (_) {
      if (mounted) setState(() => error = '无法打开浏览器，请手动访问项目的 GitHub Release。');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const LText(
        '软件更新',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: checking ? null : check,
        icon: checking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update_alt, size: 18),
        label: LText(checking ? '正在检查更新…' : '检查更新'),
      ),
      const SizedBox(height: 8),
      // Use the same slot for the explanation and the result, keeping other rows still.
      SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.topLeft,
          child: LTooltip(
            message:
                error ??
                (result == null
                    ? '仅手动检查 GitHub 正式版；不会自动下载或安装。'
                    : result!.hasUpdate
                    ? '发现新版本：${result!.version}'
                    : '已是最新版本'),
            child: LText(
              error ??
                  (result == null
                      ? '仅手动检查 GitHub 正式版；不会自动下载或安装。'
                      : result!.hasUpdate
                      ? '发现新版本：${result!.version}'
                      : '已是最新版本'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: error != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      if (result?.hasUpdate == true || error != null)
        TextButton.icon(
          onPressed: openRelease,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const LText('打开下载页'),
        ),
    ],
  );
}
