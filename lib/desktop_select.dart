import 'package:flutter/material.dart';
import 'core/control.dart';

/// Controlled desktop selector with a short, single Material menu transition.
/// Unlike FormField.initialValue, every external hardware snapshot updates it.
class DesktopSelect<T> extends StatelessWidget {
  const DesktopSelect({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.hint,
    this.borderRadius,
    this.isExpanded = false,
  });
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final InputDecoration decoration;
  final Widget? hint;
  final BorderRadius? borderRadius;
  final bool isExpanded;

  Future<void> open(BuildContext context) async {
    if (onChanged == null || UiActivity.active) return;
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    UiActivity.depth++;
    T? result;
    try {
      result = await showMenu<T>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(rect.left, rect.bottom + 4, rect.width, 0),
          Offset.zero & overlay.size,
        ),
        constraints: BoxConstraints(
          minWidth: rect.width,
          maxWidth: rect.width,
          maxHeight: 400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(12),
        ),
        popUpAnimationStyle: const AnimationStyle(
          duration: Duration(milliseconds: 140),
          reverseDuration: Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        requestFocus: true,
        items: [
          for (final item in items)
            PopupMenuItem<T>(
              value: item.value,
              enabled: item.enabled,
              height: 44,
              child: Semantics(
                selected: item.value == initialValue,
                child: Row(
                  children: [
                    Expanded(child: item.child),
                    const SizedBox(width: 8),
                    if (item.value == initialValue)
                      Icon(
                        Icons.check,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    } finally {
      UiActivity.depth--;
    }
    if (context.mounted && result != null) onChanged?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final selected = items
        .where((item) => item.value == initialValue)
        .firstOrNull;
    final enabled = onChanged != null;
    return RepaintBoundary(
      child: Material(
        type: MaterialType.transparency,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => open(context) : null,
          child: InputDecorator(
            decoration: decoration.copyWith(enabled: enabled),
            isEmpty: selected == null && hint == null,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: enabled
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).disabledColor,
              ),
              child: Row(
                children: [
                  Expanded(child: selected?.child ?? hint ?? const Text('')),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_drop_down,
                    color: enabled ? null : Theme.of(context).disabledColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
