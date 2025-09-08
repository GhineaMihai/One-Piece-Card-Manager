import 'imports.dart';

class SearchBarStyle {
  final String hintText;
  final EdgeInsets padding;
  final double radius;

  const SearchBarStyle({
    this.hintText = 'Search',
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.radius = 16,
  });
}

class SearchBarWidget extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final SearchBarStyle style;

  const SearchBarWidget({
    super.key,
    required this.controller,
    this.onChanged,
    this.onClear,
    this.style = const SearchBarStyle(),
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return Container(
      padding: style.padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(style.radius),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.search),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              decoration: InputDecoration.collapsed(hintText: style.hintText),
              onChanged: widget.onChanged,
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                widget.controller.clear();
                widget.onClear?.call();
                setState(() {});
              },
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handle);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handle);
    super.dispose();
  }

  void _handle() {
    setState(() {});
  }
}
