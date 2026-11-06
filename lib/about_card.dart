import 'package:flutter/material.dart';
import 'core/updates.dart';
import 'l10n.dart';
import 'ui_parts.dart';
import 'update_card.dart';
import 'version.dart';

class AboutCard extends StatelessWidget {
  const AboutCard({super.key, this.onQuit, this.updateChecker});
  final VoidCallback? onQuit;
  final UpdateChecker? updateChecker;
  @override
  Widget build(BuildContext context) => SectionCard(
    key: const ValueKey('about-card'),
    title: 'GO27Q32 Lite',
    subtitle: '版本 $appVersion',
    leading: const AppMark(size: 36),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DetailLine('控制接口', 'Windows DDC/CI'),
              const SizedBox(height: 20),
              UpdateControls(checker: updateChecker),
            ],
          ),
        ),
        const Divider(indent: 20, endIndent: 20),
        ListTile(
          key: const ValueKey('about-licenses'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: const Icon(Icons.description_outlined, size: 22),
          title: const LText('开源许可'),
          subtitle: const LText('HarmonyOS Sans 字体与第三方组件'),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'GO27Q32 Lite',
            applicationVersion: appVersion,
          ),
        ),
        const Divider(indent: 20, endIndent: 20),
        ListTile(
          key: const ValueKey('about-quit'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 6,
          ),
          leading: const Icon(Icons.logout, size: 22),
          title: const LText('退出程序'),
          onTap: onQuit,
        ),
      ],
    ),
  );
}
