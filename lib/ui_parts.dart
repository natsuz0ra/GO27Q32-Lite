import 'desktop_select.dart';
import 'l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'core/control.dart';

/// Desktop scrollbars paint over a fixed viewport instead of changing its width.
class OverlayScrollView extends StatefulWidget {
  const OverlayScrollView({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onContentSize,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final ValueChanged<Size>? onContentSize;
  @override
  State<OverlayScrollView> createState() => _OverlayScrollViewState();
}

class _OverlayScrollViewState extends State<OverlayScrollView> {
  final controller = ScrollController();
  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      controller: controller,
      thickness: 4,
      radius: const Radius.circular(2),
      interactive: true,
      child: RepaintBoundary(
        child: SingleChildScrollView(
          controller: controller,
          child: _ContentSizeObserver(
            onSize: widget.onContentSize,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

/// Report natural content size without constraining its scroll viewport.
class _ContentSizeObserver extends SingleChildRenderObjectWidget {
  const _ContentSizeObserver({required super.child, this.onSize});
  final ValueChanged<Size>? onSize;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ContentSizeRender(onSize);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ContentSizeRender renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _ContentSizeRender extends RenderProxyBox {
  _ContentSizeRender(this.onSize);
  ValueChanged<Size>? onSize;
  Size? previous;
  @override
  void performLayout() {
    super.performLayout();
    if (size == previous) return;
    previous = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize?.call(measured);
    });
  }
}

/// Operation feedback never participates in the content's layout or scroll extent.
class OperationFeedback extends StatelessWidget {
  const OperationFeedback({
    super.key,
    required this.model,
    required this.child,
    this.extraError,
    this.onDismiss,
    this.errorTop = 12,
  });
  final ControlModel model;
  final Widget child;
  final String? extraError;
  final VoidCallback? onDismiss;
  final double errorTop;
  @override
  Widget build(BuildContext context) {
    final error = model.error ?? extraError;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (model.busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 3,
            child: IgnorePointer(child: LinearProgressIndicator(minHeight: 3)),
          ),
        if (error != null)
          Positioned(
            top: errorTop,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.topRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  key: const ValueKey('operation-error'),
                  elevation: 3,
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 20,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: LTooltip(
                            message: error,
                            child: LText(
                              error,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onErrorContainer),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: tr(context, '关闭提示'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onDismiss ?? model.dismissError,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icons/go27q32.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: 'GO27Q32 Lite',
  );
}

class HdrLabelIcon extends StatelessWidget {
  const HdrLabelIcon({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: Center(
      child: Text(
        'HDR',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: IconTheme.of(context).color,
        ),
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.subtitle,
    this.tint = false,
    this.leading,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final bool tint;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      color: tint ? c.primaryContainer.withValues(alpha: .35) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (icon != null || leading != null) ...[
                  leading ??
                      (icon == Icons.hdr_on || icon == Icons.hdr_on_outlined
                          ? Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: LText(
                                'HDR',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: c.onPrimaryContainer,
                                ),
                              ),
                            )
                          : Icon(icon, color: c.primary, size: 28)),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        LText(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: c.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
              ],
            ),
          ),
          const Divider(),
          child,
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.good = false});
  final String text;
  final bool good;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: good ? c.tertiaryContainer : c.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(40),
      ),
      child: LText(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: good ? c.onTertiaryContainer : c.onSurfaceVariant,
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.error = false, this.action});
  final String text;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: error
          ? c.errorContainer
          : c.secondaryContainer.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              color: error ? c.onErrorContainer : c.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LText(text, style: Theme.of(context).textTheme.bodySmall),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
      ),
    );
  }
}

class DetailLine extends StatelessWidget {
  const DetailLine(this.title, this.value, {super.key});
  final String title, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LText(title, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: LText(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    ),
  );
}

class FeatureControl extends StatelessWidget {
  const FeatureControl({
    super.key,
    required this.model,
    required this.id,
    this.large = false,
    this.compact = false,
    this.padding,
  });
  final ControlModel model;
  final String id;
  final bool large;
  final bool compact;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) {
    final f = model.feature(id);
    if (f == null) return const SizedBox.shrink();
    final value = model.value(id),
        reason = model.blocked(id),
        choices = f['Choices'] as List?;
    final label = LText(
      f['Name'] as String,
      style: Theme.of(context).textTheme.titleSmall,
    );
    Widget control;
    if (choices != null) {
      control = SizedBox(
        width: large ? double.infinity : 192,
        child: DesktopSelect<int>(
          borderRadius: BorderRadius.circular(12),
          key: ValueKey('$id-${model.activeHdr}'),
          initialValue: choices.any((x) => x['Value'] == value) ? value : null,
          isExpanded: true,
          hint: const LText('不可用'),
          decoration: const InputDecoration(isDense: true),
          items: choices
              .map(
                (choice) => DropdownMenuItem<int>(
                  value: choice['Value'] as int,
                  child: LText(choice['Name'] as String),
                ),
              )
              .toList(),
          onChanged: reason != null
              ? null
              : (v) async {
                  if (v == null) return;
                  if (id == 'input') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const LText('切换输入源？'),
                        content: const LText('切换后当前电脑可能失去显示器连接。请确认另一输入源已连接。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const LText('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const LText('切换'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                  }
                  model.stage(id, v);
                },
        ),
      );
    } else {
      final max = model.maximum(id);
      control = Row(
        children: [
          Expanded(
            child: Slider(
              value: (value ?? 0).clamp(0, max).toDouble(),
              min: 0,
              max: max.toDouble(),
              divisions: max > 0 ? max : 1,
              label: model.label(id),
              onChangeStart: reason != null ? null : (_) => model.beginDrag(),
              onChangeEnd: reason != null ? null : (_) => model.endDrag(),
              onChanged: reason != null
                  ? null
                  : (v) => model.stage(id, v.round()),
            ),
          ),
          if (!large)
            SizedBox(
              width: 46,
              child: LText(
                model.label(id),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
        ],
      );
    }
    control = LTooltip(
      key: ValueKey('feature-tip-$id'),
      verticalOffset: 36,
      message: reason ?? '调节${f['Name']}',
      child: control,
    );
    return Padding(
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: large ? 0 : 20,
            vertical: compact ? 8 : 14,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (large) ...[
            LText(
              value == null ? '—' : '$value%',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: compact ? 32 : 58,
              ),
            ),
            control,
          ] else
            LayoutBuilder(
              builder: (_, box) => Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: (box.maxWidth * .62).clamp(150, 252),
                    child: control,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class HdrSwitch extends StatelessWidget {
  const HdrSwitch({super.key, required this.model});
  final ControlModel model;
  @override
  Widget build(BuildContext context) => Switch(
    value: model.hdrEnabled,
    onChanged:
        !model.connected ||
            model.busy ||
            model.automatic ||
            !model.stableHdr ||
            (model.state['hdr'] as Json?)?['Supported'] != true
        ? null
        : (v) => model.command('hdr', {'enabled': v}),
  );
}

class QuickProfiles extends StatelessWidget {
  const QuickProfiles({super.key, required this.model});
  final ControlModel model;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final p in model.deviceProfiles.take(4))
        ActionChip(
          avatar: Icon(
            p['Id'] == model.state['activeProfile']
                ? Icons.check_circle_outline
                : Icons.bookmark_border,
            size: 17,
          ),
          label: Text(p['Name'] as String),
          onPressed: !model.connected || model.busy || model.automatic
              ? null
              : () => model.command('apply', {'id': p['Id']}),
        ),
    ],
  );
}
