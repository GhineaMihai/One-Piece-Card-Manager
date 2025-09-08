import 'imports.dart';

String get baseUrl {
  if (Platform.isAndroid) {
    return "http://10.88.253.142:4747";
  } else {
    return "http://localhost:4747";
  }
}

Size parseResolution(String resolutionStr) {
  final parts = resolutionStr.split('x');
  if (parts.length == 2) {
    final width = double.tryParse(parts[0]);
    final height = double.tryParse(parts[1]);
    if (width != null && height != null) {
      return Size(width, height);
    }
  }
  return const Size(1920, 1080);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final prefs = await SharedPreferences.getInstance();
  final savedResolution = prefs.getString('selectedResolution') ?? '1920x1080';
  final savedScreenMode = prefs.getString('selectedScreenMode') ?? 'Fullscreen';
  final size = parseResolution(savedResolution);

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(size: size, center: true, title: 'Card Manager', backgroundColor: Colors.transparent, skipTaskbar: false);

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (savedScreenMode == 'Fullscreen') {
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(false);
        await windowManager.setMinimumSize(size);
        await windowManager.setMaximumSize(size);
      }

      await windowManager.show();
      await windowManager.focus();
      await windowManager.maximize();
    });
  }

  runApp(CardApp(initialResolution: savedResolution, initialScreenMode: savedScreenMode));
}