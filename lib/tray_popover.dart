import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app.dart';
import 'core/control.dart';

/// Share the existing controller while leaving the visible main window intact.
class TrayPopover extends StatefulWidget {
  const TrayPopover({
    super.key,
    required this.model,
    required this.onOpen,
    required this.onClose,
  });
  final ControlModel model;
  final VoidCallback onOpen, onClose;
  @override
  State<TrayPopover> createState() => _TrayPopoverState();
}

class _TrayPopoverState extends State<TrayPopover> {
  double height = 620;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: math.min(368, box.maxWidth - 32),
          height: math.min(height, box.maxHeight - 32),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: TrayPanel(
              model: widget.model,
              onOpen: widget.onOpen,
              onClose: widget.onClose,
              onContentSize: (size) {
                if (mounted && (size.height - height).abs() > 1) {
                  setState(() => height = size.height);
                }
              },
            ),
          ),
        ),
      ),
    ),
  );
}
