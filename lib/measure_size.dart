import 'imports.dart';

class MeasureSize extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onChange;

  const MeasureSize({super.key, required this.child, required this.onChange});

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contextSize = context.size;
      if (contextSize != null && oldSize != contextSize) {
        oldSize = contextSize;
        widget.onChange(contextSize);
      }
    });
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        child: widget.child,
      ),
    );
  }
}
