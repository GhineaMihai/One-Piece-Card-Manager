import 'imports.dart';

class LiveScanPage extends StatelessWidget {
  final VoidCallback onStartScan;

  const LiveScanPage({super.key, required this.onStartScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        icon: Icon(Icons.camera_alt),
        label: Text('Start Live Scan'),
        onPressed: onStartScan,
      ),
    );
  }
}
