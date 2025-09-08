import 'imports.dart';

class CardSuggestion extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const CardSuggestion({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.style),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
