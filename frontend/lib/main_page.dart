import 'imports.dart';

class MainPage extends StatefulWidget {
  final String token;

  const MainPage({super.key, required this.token});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  Timer? _scanCheckTimer;
  List<dynamic> _allCards = [];
  List<dynamic> _filteredCards = [];

  List<dynamic> _allAvailableCards = [];

  List<dynamic> _userDecks = [];

  Map<String, dynamic>? _viewingDeck;
  List<Map<String, dynamic>> _viewingDeckCards = [];

  bool _isCreatingDeck = false;

  Map<int, int> _selectedDeckCards = {}; // card_id -> count
  Map<String, dynamic>? _selectedLeaderCard;

  late String selectedResolution;
  late String selectedScreenMode;

  bool _isHoveringType = false;
  bool _isHoveringColor = false;
  bool _isHoveringSettings = false;

  final Map<String, Size> _resolutions = {"2560x1600": Size(2560, 1600), "1920x1080": Size(1920, 1080), "1600x900": Size(1600, 900), "1366x768": Size(1366, 768), "1280x720": Size(1280, 720)};

  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  final Set<int> _selectedCosts = {};

  final Set<String> _selectedColors = {};
  final Set<String> _selectedTypes = {};

  final List<String> _colorOptions = ['Red', 'Blue', 'Green', 'Black', 'Yellow', 'Purple'];
  final List<String> _typeOptions = ['Character', 'Event', 'Stage', 'Leader'];

  final LayerLink _colorDropdownLink = LayerLink();
  OverlayEntry? _colorDropdownOverlay;

  final LayerLink _typeDropdownLink = LayerLink();
  OverlayEntry? _typeDropdownOverlay;

  int _currentPage = 0;
  final int _cardsPerPage = 8;
  List<CardSuggestion> _suggestions = [];
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  final Map<String, double> _itemHeights = {};

  Future<void> _loadAllCards() async {
    final response = await http.get(Uri.parse("$baseUrl/api/cards/all"), headers: {"Authorization": "Bearer ${widget.token}"});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _allAvailableCards = data; // Store all cards separately
      });
    }
  }

  Future<void> _updateCollectionCard(int cardId, int delta) async {
    // Find current count in memory
    final existing = _allCards.firstWhere((entry) => entry['card']['id'] == cardId, orElse: () => null);

    int currentCount = existing != null ? (existing['count'] ?? 0) : 0;
    int newCount = currentCount + delta;

    if (newCount < 0) newCount = 0;

    await http.put(
      Uri.parse('$baseUrl/users/me/collection/$cardId'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({"card_id": cardId, "count": newCount}),
    );

    await _loadCollection();
  }

  void _importDeckFromText(String text) async {
    final lines = text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;

    final List<Map<String, dynamic>> selectedCards = [];
    final List<String> missingCards = [];

    for (final line in lines) {
      final cleanedLine = line.trim();
      final countMatch = RegExp(r'^(\d+)\s+').firstMatch(cleanedLine);
      final count = int.tryParse(countMatch?.group(1) ?? '1') ?? 1;

      final idMatch = RegExp(r'\(([^)]+)\)').firstMatch(cleanedLine);
      final cardId = idMatch?.group(1) ?? '';

      final cardEntry = _allCards.firstWhere((c) => c['card']['card_id'].toString().toLowerCase().trim() == cardId.toLowerCase().trim(), orElse: () => null);

      if (cardEntry != null) {
        selectedCards.add({
          'card_id': cardEntry['card']['id'],
          'count': count,
        });
      } else {
        missingCards.add('$cleanedLine');
      }
    }

    if (missingCards.isNotEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color.fromARGB(255, 242, 194, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.brown.shade800, width: 4),
          ),
          title: Text(
            "Missing Cards",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown.shade800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...missingCards.map(
                      (c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Would you like to add these cards to your collection with the exact counts from the list?",
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "Cancel",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                for (final missingLine in missingCards) {
                  final match = RegExp(r'^(\d+)\s+.*\(([^)]+)\)$').firstMatch(missingLine.trim());
                  if (match != null) {
                    final count = int.tryParse(match.group(1) ?? '1') ?? 1;
                    final cardIdText = match.group(2)?.trim();

                    if (cardIdText != null) {
                      final cardEntry = _allAvailableCards.firstWhere((c) => c['card_id'].toLowerCase().trim() == cardIdText.toLowerCase(), orElse: () => null);

                      if (cardEntry != null) {
                        final cardInternalId = cardEntry['id'];

                        final response = await http.post(
                          Uri.parse('$baseUrl/users/me/collection'),
                          headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
                          body: jsonEncode({"card_id": cardInternalId, "count": count}),
                        );

                        if (response.statusCode != 200 && response.statusCode != 201) {
                          print('Failed to add card $cardIdText with count $count: ${response.statusCode}');
                        }
                      } else {
                        print('Card not found in _allAvailableCards: $cardIdText');
                      }
                    }
                  }
                }

                await _loadCollection();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 233, 186, 92),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.brown.shade800, width: 3),
                ),
              ),
              child: const Text("Add Cards", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return; // Stop until missing cards are fixed
    }

    final TextEditingController nameController = TextEditingController();
    final nameConfirmed = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color.fromARGB(255, 242, 194, 96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.brown.shade800, width: 4),
        ),
        title: Text(
          "Deck Name",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown.shade800),
        ),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            hintText: "Enter deck name",
            filled: true,
            fillColor: const Color.fromARGB(255, 255, 234, 170),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.brown.shade800, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              "Cancel",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(nameController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 233, 186, 92),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.brown.shade800, width: 3),
              ),
            ),
            child: Text("Confirm", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (nameConfirmed != null && nameConfirmed.isNotEmpty) {
      await saveDeck(nameConfirmed, selectedCards, widget.token);
      await _loadUserDecks();
      setState(() {
        _isCreatingDeck = false;
        _viewingDeck = null;
        _selectedLeaderCard = null;
        _selectedDeckCards.clear();
        _selectedTypes.clear();
        _selectedColors.clear();
        _selectedCosts.clear();
        _searchController.clear();
        _currentPage = 0;
      });
      _applyCombinedFilters();
    }
  }

  void _showImportDeckDialog() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color.fromARGB(255, 242, 194, 96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.brown.shade800, width: 4),
        ),
        title: Text(
          "Import Deck",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown.shade800),
        ),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: "Paste deck list here",
            filled: true,
            fillColor: const Color.fromARGB(255, 255, 234, 170),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.brown.shade800, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              "Cancel",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _importDeckFromText(controller.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 233, 186, 92),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.brown.shade800, width: 3),
              ),
            ),
            child: Text("Import", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCardDetailsDialog(Map<String, dynamic> card, int currentCount) {
    int localCount = currentCount; // Local mutable copy

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 242, 194, 96),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.brown.shade800, width: 4),
              ),
              contentPadding: const EdgeInsets.all(16),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network("$baseUrl/${card['image']}", width: 400, height: 545, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "${card['card_id']}: ${card['name']}",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "In Collection: $localCount",
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            setState(() {
                              localCount += 1;
                            });
                            await _updateCollectionCard(card['id'], 1);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 233, 186, 92),
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.brown.shade800, width: 3),
                            ),
                          ),
                          child: const Text(
                            "➕ Add",
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: localCount > 0
                              ? () async {
                            setState(() {
                              localCount -= 1;
                            });
                            await _updateCollectionCard(card['id'], -1);
                          }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 233, 186, 92),
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.brown.shade800, width: 3),
                            ),
                          ),
                          child: const Text(
                            "➖ Remove",
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> checkForScanResults() async {
    final prefs = await SharedPreferences.getInstance();
    final liveScanIds = prefs.getStringList('liveScanResults') ?? [];

    if (liveScanIds.isNotEmpty) {
      prefs.remove('liveScanResults');

      final response = await http.post(
        Uri.parse('$baseUrl/live-scan'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(liveScanIds),
      );

      if (response.statusCode == 200) {
        final List<dynamic> scannedCards = jsonDecode(response.body);

        if (scannedCards.isEmpty) return;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color.fromARGB(255, 242, 194, 96),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.brown.shade800, width: 4),
            ),
            title: Text("Add scanned cards?", style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: scannedCards.map((card) {
                return Text("${card['card_id']}: ${card['name']}", style: TextStyle(fontWeight: FontWeight.bold));
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("Cancel", style: TextStyle(color: Colors.black)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.brown),
                child: Text("Add", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          for (final card in scannedCards) {
            await http.put(
              Uri.parse('$baseUrl/users/me/collection/${card['id']}'),
              headers: {
                'Authorization': 'Bearer ${widget.token}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({"card_id": card['id'], "count": 1}),
            );
          }
          _showTopNotification("Cards added from live scan!");
          await _loadCollection();
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid || Platform.isIOS) {
      selectedResolution = "1920x1080";  // any default, will be ignored visually
      selectedScreenMode = "Phone";
    } else {
      selectedResolution = widget.resolutionOverride ?? "1920x1080";
      selectedScreenMode = widget.screenModeOverride ?? "Fullscreen";
    }

    print("Init Resolution: $selectedResolution");
    print("Init ScreenMode: $selectedScreenMode");

    _loadCollection();
    _loadUserDecks();
    _loadAllCards();

    bool _isScanning = false;

    super.initState();

    _scanCheckTimer = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      if (_isScanning) return;
      _isScanning = true;
      await checkForScanResults();
      _isScanning = false;
    });
  }

  Future<void> _loadUserDecks() async {
    final response = await http.get(Uri.parse('$baseUrl/users/me/decks'), headers: {"Authorization": "Bearer ${widget.token}"});

    if (response.statusCode == 200) {
      setState(() {
        _userDecks = jsonDecode(response.body);
      });
    } else {
      print("Failed to load decks: ${response.body}");
    }
  }


  Future<void> _viewDeck(Map<String, dynamic> deck) async {
    final List<Map<String, dynamic>> deckCards = (deck['cards'] as List).cast<Map<String, dynamic>>();
    final leader = deckCards.firstWhere((c) => c['card']['type'] == 'Leader', orElse: () => {});
    final rest = deckCards.where((c) => c['card']['type'] != 'Leader').toList();

    final selectedLeader = leader.isNotEmpty ? leader['card'] : null;
    final leaderColors = (selectedLeader?['color'] as List?)?.cast<String>() ?? [];

    final newSelectedDeckCards = <int, int>{};
    for (final entry in rest) {
      final card = entry['card'];
      final count = entry['count'] ?? 1;
      newSelectedDeckCards[card['id']] = count;
    }

    setState(() {
      _isCreatingDeck = true; // behave like edit mode
      _viewingDeck = deck;
      _selectedLeaderCard = selectedLeader;
      _selectedDeckCards = newSelectedDeckCards;
      _selectedTypes
        ..clear()
        ..addAll(['Character', 'Event', 'Stage']);
      _selectedColors
        ..clear()
        ..addAll(leaderColors);
      _selectedCosts.clear();
      _searchController.clear();
      _currentPage = 0;
    });

    _applyCombinedFilters();
  }

  Widget _buildStyledButton(String text, {required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromARGB(255, 242, 194, 96),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(
              color: Color.fromARGB(255, 95, 56, 32), // same brown shade
              width: 3,
            ),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 242, 194, 96),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [const BoxShadow(color: Color.fromARGB(255, 129, 84, 45), offset: Offset(-2, -2), blurRadius: 0)],
          ),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  double _getSize(String key) {
    return uiSizeConfig[selectedScreenMode]?[selectedResolution]?[key] ?? 40.0;
  }

  void _showDisplaySettingsDialog() {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }
    final outerContext = context;

    showDialog(
      context: outerContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 242, 194, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.brown.shade800, width: 4),
          ),
          title: Center(
            child: Text(
              'Display Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.brown.shade800),
            ),
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectedScreenMode != 'Phone')
                  // Resolution Dropdown
                    DropdownButtonFormField<String>(
                      value: selectedResolution,
                      dropdownColor: const Color.fromARGB(255, 242, 194, 96),
                      decoration: InputDecoration(
                        labelText: "Resolution",
                        filled: true,
                        fillColor: const Color.fromARGB(255, 242, 194, 96),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.brown.shade800, width: 3),
                        ),
                      ),
                      iconEnabledColor: Colors.brown.shade800,
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      items: ["2560x1600", "1920x1080", "1600x900", "1366x768", "1280x720"].map((res) {
                        return DropdownMenuItem(value: res, child: Text(res));
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedResolution = val!;
                        });
                      },
                    ),
                  const SizedBox(height: 16),

                  // Screen Mode Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedScreenMode,
                    dropdownColor: const Color.fromARGB(255, 242, 194, 96),
                    decoration: InputDecoration(
                      labelText: "Screen Mode",
                      filled: true,
                      fillColor: const Color.fromARGB(255, 242, 194, 96),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.brown.shade800, width: 3),
                      ),
                    ),
                    iconEnabledColor: Colors.brown.shade800,
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    items: ["Fullscreen", "Windowed"].map((mode) {
                      return DropdownMenuItem(value: mode, child: Text(mode));
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedScreenMode = val!;
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Apply Button (just closes for now)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('selectedResolution', selectedResolution);
                              await prefs.setString('selectedScreenMode', selectedScreenMode);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 242, 194, 96),
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.brown.shade800, width: 3),
                              ),
                            ),
                            child: const Text(
                              "Back",
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: () async {
                              final navigator = Navigator.of(context); // ✅ capture BEFORE popping
                              Navigator.of(context).pop(); // Close dialog

                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('selectedResolution', selectedResolution);
                              await prefs.setString('selectedScreenMode', selectedScreenMode);

                              final size = _resolutions[selectedResolution] ?? const Size(1920, 1080);

                              if (selectedScreenMode == "Fullscreen") {
                                await windowManager.setMinimumSize(Size(0, 0));
                                await windowManager.setMaximumSize(Size(size.width, size.height));
                                await windowManager.setFullScreen(true);
                                await Future.delayed(const Duration(milliseconds: 200));
                              } else {
                                await windowManager.setFullScreen(false);
                                await Future.delayed(const Duration(milliseconds: 200));
                                await windowManager.setMinimumSize(size);
                                await windowManager.setMaximumSize(size);
                                await windowManager.setBounds(Rect.fromLTWH(0, 0, size.width, size.height));
                              }

                              if (mounted) {
                                navigator.pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => MainPage(token: widget.token, resolutionOverride: selectedResolution, screenModeOverride: selectedScreenMode, key: UniqueKey()),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 242, 194, 96),
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.brown.shade800, width: 3),
                              ),
                            ),
                            child: const Text(
                              "Apply",
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 242, 194, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.brown.shade800, width: 4),
          ),
          title: Center(
            child: Text(
              'Settings',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.brown.shade800, letterSpacing: 1.2),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStyledButton(
                "Display Settings",
                onTap: () {
                  Navigator.of(context).pop();
                  _showDisplaySettingsDialog();
                },
              ),
              const SizedBox(height: 12),
              _buildStyledButton(
                "Log Out",
                onTap: () async {
                  Navigator.of(context).pop(); // close dialog

                  // Navigate to login and clear history
                  final prefs = await SharedPreferences.getInstance();
                  final savedResolution = prefs.getString('selectedResolution') ?? '1920x1080';
                  final savedScreenMode = prefs.getString('selectedScreenMode') ?? 'Fullscreen';

                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => LoginPage(initialResolution: savedResolution, initialScreenMode: savedScreenMode),
                    ),
                        (route) => false,
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildStyledButton(
                "Exit",
                onTap: () {
                  exit(0);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _applyCombinedFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final tokens = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    setState(() {
      _filteredCards = _allCards.where((entry) {
        final card = entry['card'];

        final matchesText = tokens.every((token) {
          final combined = '${card['card_id']} ${card['name']}'.toLowerCase();
          return combined.contains(token);
        });

        final matchesCost = _selectedCosts.isEmpty || _selectedCosts.contains(card['cost']);
        final matchesColor = _selectedColors.isEmpty || (card['color'] is List && (card['color'] as List).any((c) => _selectedColors.contains(c)));
        final matchesType = _selectedTypes.isEmpty || _selectedTypes.contains(card['type']);

        return matchesText && matchesCost && matchesColor && matchesType;
      }).toList();

      _currentPage = 0;
    });
  }

  void performSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _fetchSuggestions(query); // replace with your actual function
    }
  }

  void _toggleTypeDropdown() {
    if ((_isCreatingDeck && _viewingDeck == null)) return;
    if (_typeDropdownOverlay != null) {
      _typeDropdownOverlay!.remove();
      _typeDropdownOverlay = null;
      return;
    }

    _typeDropdownOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 120,
          child: CompositedTransformFollower(
            link: _typeDropdownLink,
            showWhenUnlinked: false,
            offset: const Offset(0, -160), // adjust as needed
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBA9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.brown.shade800, width: 3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(2, 2))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _typeOptions.map((type) {
                    final isSelected = _selectedTypes.contains(type);
                    return InkWell(
                      onTap: () {
                        if (_selectedTypes.contains(type)) {
                          _selectedTypes.remove(type);
                        } else {
                          _selectedTypes.add(type);
                        }

                        _applyCombinedFilters();

                        // Rebuild to reflect selection
                        _typeDropdownOverlay?.remove();
                        _typeDropdownOverlay = null;
                        _toggleTypeDropdown();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(color: isSelected ? Colors.brown.shade800 : Colors.transparent, borderRadius: BorderRadius.zero),
                        child: Text(
                          type,
                          style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_typeDropdownOverlay!);
  }

  void _toggleColorDropdown() {
    if (_isCreatingDeck && _selectedLeaderCard != null) return;

    if (_colorDropdownOverlay != null) {
      _colorDropdownOverlay!.remove();
      _colorDropdownOverlay = null;
      return;
    }

    _colorDropdownOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 120,
          child: CompositedTransformFollower(
            link: _colorDropdownLink,
            showWhenUnlinked: false,
            offset: const Offset(0, -240), // pop above the button
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBA9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.brown.shade800, width: 3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(2, 2))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _colorOptions.map((color) {
                    final isSelected = _selectedColors.contains(color);
                    return InkWell(
                      onTap: () {
                        if (_selectedColors.contains(color)) {
                          _selectedColors.remove(color);
                        } else {
                          _selectedColors.add(color);
                        }

                        _applyCombinedFilters();

                        // Rebuild the overlay to update visual state
                        _colorDropdownOverlay?.remove();
                        _colorDropdownOverlay = null;
                        _toggleColorDropdown(); // Reopen with updated selection
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(color: isSelected ? Colors.brown.shade800 : Colors.transparent, borderRadius: BorderRadius.zero),
                        child: Text(
                          color,
                          style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_colorDropdownOverlay!);
  }

  void _filterByCost(int cost) {
    setState(() {
      if (_selectedCosts.contains(cost)) {
        _selectedCosts.remove(cost);
      } else {
        _selectedCosts.add(cost);
      }
    });

    _applyCombinedFilters();
  }

  void _showTopNotification(String message) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 40,
        left: MediaQuery.of(context).size.width * 0.5 - 150, // center horizontally
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 242, 194, 96), // same as search bar
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.brown.shade800, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 3))],
            ),
            child: Center(
              child: Text(
                message,
                style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 2), () => overlayEntry.remove());
  }

  void _addCardFromSearch() async {
    final input = _searchController.text.trim();
    if (input.isEmpty) return;

    // Try to split input into cardId and name
    final parts = input.split(RegExp(r'\s+'));
    final cardId = parts.first;
    final name = parts.skip(1).join(' ');

    final response = await http.get(
      Uri.parse('$baseUrl/card-api/search?card_id=${Uri.encodeComponent(cardId)}&name=${Uri.encodeComponent(name)}'),
      headers: {"Authorization": "Bearer ${widget.token}"},
    );

    if (response.statusCode == 200) {
      final results = jsonDecode(response.body);
      if (results.isNotEmpty) {
        final card = results[0];
        final cardId = card['id'];

        final addResponse = await http.post(
          Uri.parse('$baseUrl/users/me/collection'),
          headers: {"Authorization": "Bearer ${widget.token}", "Content-Type": "application/json"},
          body: jsonEncode({"card_id": cardId, "count": 1}),
        );

        if (addResponse.statusCode == 200) {
          _showTopNotification("Card added!");
          _loadCollection(); // Refresh collection
        } else {
          _showTopNotification("Failed to add card");
        }
      } else {
        _showTopNotification("No matching cards found");
      }
    }
  }

  void _showSuggestions() {
    _removeSuggestions();
    final double dropdownHeight = _suggestions.take(10).fold(0.0, (sum, s) => sum + (_itemHeights[s.cardId] ?? 54.0));

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 1000,
        bottom: 70, // position of the search bar
        width: 400,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, -dropdownHeight), // move it UP by exact height
          child: Material(
            color: Colors.white.withAlpha(140),
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.brown.shade800, width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.take(10).map((suggestion) {
                  return MeasureSize(
                    onChange: (size) {
                      setState(() {
                        _itemHeights[suggestion.cardId] = size.height;
                      });
                    },
                    child: ListTile(
                      dense: true,
                      minLeadingWidth: 40,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network('$baseUrl/cards/${suggestion.cardId}.png', width: 40, height: 40, fit: BoxFit.cover),
                      ),
                      title: Text(suggestion.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text(suggestion.cardId, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onTap: () {
                        final fullText = '${suggestion.cardId} ${suggestion.name}';
                        _searchController.text = fullText;
                        _handleSearch(fullText);
                        _removeSuggestions();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeSuggestions() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      _removeSuggestions();
      return;
    }

    // Use "op" to get a wide-enough range of cards
    final response = await http.get(Uri.parse('$baseUrl/card-api/autocomplete?q=${Uri.encodeQueryComponent(query)}'), headers: {"Authorization": "Bearer ${widget.token}"});

    if (response.statusCode == 200) {
      final List<dynamic> json = jsonDecode(response.body);
      final List<CardSuggestion> allSuggestions = json.map((e) => CardSuggestion.fromJson(e)).toList();

      final tokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      final filtered = allSuggestions.where((s) {
        final combined = '${s.cardId} ${s.name}'.toLowerCase();
        return tokens.every((token) => combined.contains(token));
      }).toList();

      setState(() {
        _suggestions = filtered;
      });

      if (_suggestions.isNotEmpty) {
        _showSuggestions();
      } else {
        _removeSuggestions();
      }
    }
  }

  Future<void> _handleSearch(String query) async {
    await _loadCollection();     // <— refresh before searching
    _applyCombinedFilters();
    _removeSuggestions();
  }

  void _showSaveDialog(BuildContext context, Function(String) onConfirm) {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color.fromARGB(255, 242, 194, 96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.brown.shade800, width: 4),
        ),
        title: Center(
          child: Text(
            "Save Deck",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.brown.shade800),
          ),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: "Enter deck name",
            hintStyle: const TextStyle(color: Colors.black87),
            filled: true,
            fillColor: const Color.fromARGB(255, 255, 234, 170),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.brown.shade800, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.brown.shade900, width: 3),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              "Back",
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 233, 186, 92),
              foregroundColor: Colors.black,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.brown.shade800, width: 3),
              ),
            ),
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop();
                onConfirm(name);
              }
            },
            child: const Text("Confirm", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> updateDeck(int deckId, String name, List<Map<String, dynamic>> selectedCards, String token) async {
    final url = Uri.parse('$baseUrl/users/me/decks/$deckId');
    final response = await http.put(url, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({"name": name, "cards": selectedCards}));

    if (response.statusCode == 200) {
      print("Deck updated successfully!");
    } else {
      print("Failed to update deck: ${response.body}");
    }
  }

  Future<void> saveDeck(String name, List<Map<String, dynamic>> selectedCards, String token, {int? deckId}) async {
    final url = deckId != null
        ? Uri.parse('$baseUrl/users/me/decks/$deckId') // UPDATE
        : Uri.parse('$baseUrl/users/me/decks'); // CREATE

    final response = await (deckId != null
        ? http.put(url, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({"name": name, "cards": selectedCards}))
        : http.post(url, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({"name": name, "cards": selectedCards})));

    if (response.statusCode == 200 || response.statusCode == 201) {
      print(deckId != null ? "Deck updated!" : "Deck saved!");
    } else {
      print("Failed to save/update deck: ${response.body}");
    }
  }

  Future<void> _loadCollection() async {
    final response = await http.get(Uri.parse("$baseUrl/users/me/collection"), headers: {"Authorization": "Bearer ${widget.token}"});

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _allCards = data["cards"];
        _filteredCards = _allCards; // at first show all
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_filteredCards.length / _cardsPerPage).ceil();
    final currentCards = _filteredCards.skip(_currentPage * _cardsPerPage).take(_cardsPerPage).toList();

    final isDeckFull = _selectedDeckCards.values.fold<int>(0, (sum, c) => sum + c) == 50;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: null,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Sidebar
                Container(
                  width: _getSize("sidebarWidth"),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6F4E37),
                    image: DecorationImage(image: AssetImage('assets/images/sidebar_texture.png'), fit: BoxFit.fill, colorFilter: ColorFilter.mode(Colors.brown.withOpacity(0.2), BlendMode.dstATop)),
                  ),
                  padding: EdgeInsets.all(_getSize("sidebarPadding")),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: _getSize("sidebarTitlePaddingH"),
                          vertical: _getSize("sidebarTitlePaddingV"),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6F4E37),
                          borderRadius: BorderRadius.circular(_getSize("sidebarTitleFont")/2),
                          border: Border.all(color: const Color(0xFFF2C260), width: _getSize("sidebarBorder")),
                          boxShadow: [BoxShadow(color: Colors.brown.shade900, offset: const Offset(2, 2), blurRadius: 2)],
                        ),
                        child: Text(
                          "My Decks",
                          style: TextStyle(
                            fontFamily: 'Alegreya',
                            fontSize: _getSize("sidebarTitleFont"),
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade100,
                            shadows: [Shadow(offset: Offset(1.5, 1.5), blurRadius: 2, color: Colors.black45)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if ((_isCreatingDeck || _viewingDeck != null) && _selectedLeaderCard != null) ...[
                        Text(
                          "Leader:",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade100, fontSize: _getSize("sidebarFontSize")),
                        ),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6F4E37),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF2C260), width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedLeaderCard!["card_id"] ?? "",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: _getSize("sidebarFontSize")),
                              ),
                              Text(
                                _selectedLeaderCard!["name"] ?? "",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: _getSize("sidebarFontSize")),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "${_selectedDeckCards.values.fold<int>(0, (sum, count) => sum + count)} / 50",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade100, fontSize: _getSize("sidebarFontSize")),
                        ),
                      ],
                      if (_selectedDeckCards.isNotEmpty) ...[
                        Text(
                          "Selected Cards:",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade100, fontSize: _getSize("sidebarFontSize")),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 80),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6F4E37),
                            border: Border.all(color: const Color(0xFFF2C260), width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: GridView.count(
                            shrinkWrap: true,
                            crossAxisCount: 2,
                            crossAxisSpacing: 1,
                            mainAxisSpacing: 1,
                            childAspectRatio: 3.5,
                            children: _selectedDeckCards.entries.map((e) {
                              final cardId = e.key;
                              final count = e.value;
                              final cardData = _allCards.firstWhere((c) => c['card']['id'] == cardId)['card'];

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_selectedDeckCards.containsKey(cardId)) {
                                      if (_selectedDeckCards[cardId]! > 1) {
                                        _selectedDeckCards[cardId] = _selectedDeckCards[cardId]! - 1;
                                      } else {
                                        _selectedDeckCards.remove(cardId);
                                      }
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                                  child: Text(
                                    '${cardData['card_id']} x$count',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: _getSize("sidebarFontSize"),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      Expanded(
                        child: ListView.builder(
                          itemCount: _userDecks.length,
                          itemBuilder: (context, index) {
                            final deck = _userDecks[index];

                            if (_isCreatingDeck && _viewingDeck != null) return const SizedBox.shrink();

                            if (_viewingDeck != null && deck['id'] != _viewingDeck!['id']) return const SizedBox.shrink();

                            return GestureDetector(
                              onTap: () => _viewDeck(deck),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: EdgeInsets.symmetric(horizontal: _getSize("sidebarPaddingH"), vertical: _getSize("sidebarPaddingV")),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6F4E37),
                                  borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                  border: Border.all(color: const Color(0xFFF2C260), width: 2),
                                ),
                                child: Text(
                                  deck['name'],
                                  style:  TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: _getSize("sidebarButtonFont")),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_isCreatingDeck && _viewingDeck == null)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isCreatingDeck = true;
                                _selectedLeaderCard = null;
                                _selectedDeckCards.clear();
                                _selectedTypes.clear();
                                _selectedTypes.add('Leader');
                              });
                              _applyCombinedFilters();
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: _getSize("sidebarPaddingV")),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6F4E37),
                                borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                border: Border.all(color: const Color(0xFFF2C260), width: 3),
                                boxShadow: [BoxShadow(color: Colors.brown.shade900, offset: Offset(2, 2), blurRadius: 2)],
                              ),
                              child: Center(
                                child: Text(
                                  "Add Deck",
                                  style: TextStyle(color: Colors.amber.shade100, fontSize: _getSize("sidebarButtonFont"), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if ((_isCreatingDeck || _viewingDeck != null) && isDeckFull)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              final selectedCards = _selectedDeckCards.entries.map((e) => {"card_id": e.key, "count": e.value}).toList();

                              if (_selectedLeaderCard != null) {
                                selectedCards.insert(0, {"card_id": _selectedLeaderCard!['id'], "count": 1});
                              }

                              _showSaveDialog(context, (deckName) async {
                                try {
                                  if (_viewingDeck != null) {
                                    // EDIT existing deck
                                    final deckId = _viewingDeck!['id'];
                                    await updateDeck(deckId, deckName, selectedCards, widget.token);
                                  } else {
                                    // CREATE new deck
                                    await saveDeck(deckName, selectedCards, widget.token);
                                  }
                                  await _loadUserDecks();
                                  setState(() {
                                    _isCreatingDeck = false;
                                    _viewingDeck = null;
                                    _selectedLeaderCard = null;
                                    _selectedDeckCards.clear();
                                    _selectedTypes.clear();
                                    _selectedColors.clear();
                                    _selectedCosts.clear();
                                    _searchController.clear();
                                    _currentPage = 0;
                                  });
                                  _applyCombinedFilters();
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to save deck: $e")));
                                }
                              });
                            },
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(vertical: _getSize("sidebarPaddingV")),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6F4E37),
                                borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                border: Border.all(color: const Color(0xFFF2C260), width: 3),
                                boxShadow: [BoxShadow(color: Colors.brown.shade900, offset: Offset(2, 2), blurRadius: 2)],
                              ),
                              child: Center(
                                child: Text(
                                  "Save Deck",
                                  style: TextStyle(color: Colors.amber.shade100, fontSize: _getSize("sidebarButtonFont"), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_viewingDeck != null)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color.fromARGB(255, 242, 194, 96),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: Colors.brown.shade800, width: 4),
                                  ),
                                  title: Center(
                                    child: Text(
                                      "Delete Deck",
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.brown.shade800),
                                    ),
                                  ),
                                  content: const Text(
                                    "Are you sure you want to delete this deck?",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                                    textAlign: TextAlign.center,
                                  ),
                                  actionsAlignment: MainAxisAlignment.spaceEvenly,
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(false),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.black,
                                        padding: EdgeInsets.symmetric(vertical: _getSize("sidebarPaddingV")),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                          side: BorderSide(color: Colors.brown.shade800, width: 2),
                                        ),
                                      ),
                                      child: Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold, fontSize: _getSize("sidebarButtonFont"))),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.of(context).pop(true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(255, 233, 100, 92),
                                        foregroundColor: Colors.black,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: Colors.brown.shade800, width: 3),
                                        ),
                                      ),
                                      child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final deleteResponse = await http.delete(Uri.parse('$baseUrl/users/me/decks/${_viewingDeck!['id']}'), headers: {'Authorization': 'Bearer ${widget.token}'});

                                if (deleteResponse.statusCode == 200) {
                                  await _loadUserDecks();
                                  setState(() {
                                    _isCreatingDeck = false;
                                    _viewingDeck = null;
                                    _selectedLeaderCard = null;
                                    _selectedDeckCards.clear();
                                    _selectedTypes.clear();
                                    _selectedColors.clear();
                                    _selectedCosts.clear();
                                    _searchController.clear();
                                    _currentPage = 0;
                                  });
                                  _applyCombinedFilters();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete deck")));
                                }
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(vertical: _getSize("sidebarPaddingV")),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6F4E37),
                                borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                border: Border.all(color: const Color(0xFFF2C260), width: 3),
                                boxShadow: [BoxShadow(color: Colors.brown.shade900, offset: Offset(2, 2), blurRadius: 2)],
                              ),
                              child: Center(
                                child: Text(
                                  "Delete Deck",
                                  style: TextStyle(color: Colors.amber.shade100, fontSize: _getSize("sidebarButtonFont"), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_viewingDeck != null)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isCreatingDeck = false;
                                _viewingDeck = null;
                                _viewingDeckCards.clear();
                                _selectedLeaderCard = null;
                                _selectedDeckCards.clear();
                                _selectedTypes.clear();
                                _selectedColors.clear();
                                _selectedCosts.clear();
                                _searchController.clear();
                                _currentPage = 0;
                              });
                              _applyCombinedFilters();
                            },
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(vertical: _getSize("sidebarPaddingV")),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6F4E37),
                                borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                border: Border.all(color: const Color(0xFFF2C260), width: 3),
                                boxShadow: [BoxShadow(color: Colors.brown.shade900, offset: Offset(2, 2), blurRadius: 2)],
                              ),
                              child: Center(
                                child: Text(
                                  "Back to Collection",
                                  style: TextStyle(color: Colors.amber.shade100, fontSize: _getSize("sidebarButtonFont"), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if ((_isCreatingDeck && _viewingDeck == null))
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isCreatingDeck = false;
                                _selectedLeaderCard = null;
                                _selectedDeckCards.clear();
                                _selectedTypes.clear();
                                _selectedColors.clear();
                                _selectedCosts.clear();
                                _searchController.clear();
                                _currentPage = 0;
                                _applyCombinedFilters();
                              });
                            },
                            child: Container(
                              width: double.infinity,
                              padding:  EdgeInsets.symmetric(vertical: _getSize("sidebarPaddingV")),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6F4E37),
                                borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                border: Border.all(color: const Color(0xFFF2C260), width: 3),
                                boxShadow: [BoxShadow(color: Colors.brown.shade900, offset: Offset(2, 2), blurRadius: 2)],
                              ),
                              child: Center(
                                child: Text(
                                  "Cancel",
                                  style: TextStyle(color: Colors.amber.shade100, fontSize: _getSize("sidebarButtonFont"), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!_isCreatingDeck && _viewingDeck == null)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              _showImportDeckDialog();
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: _getSize("sidebarPaddingV")),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6F4E37),
                                borderRadius: BorderRadius.circular(_getSize("sidebarButtonFont")),
                                border: Border.all(color: const Color(0xFFF2C260), width: 3),
                                boxShadow: [BoxShadow(color: Colors.brown.shade900, offset: Offset(2, 2), blurRadius: 2)],
                              ),
                              child: Center(
                                child: Text(
                                  "Import Deck",
                                  style: TextStyle(color: Colors.amber.shade100, fontSize: _getSize("sidebarButtonFont"), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: Image.asset('assets/images/background.png', fit: BoxFit.fill)),
                      Column(
                        children: [
                          const SizedBox(height: kToolbarHeight + 8),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GridView.builder(
                                  padding: EdgeInsets.symmetric(horizontal: _getSize("cardPaddingH"), vertical: _getSize("cardPaddingV")),
                                  itemCount: currentCards.length,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _getSize("cardCrossAxisCount").toInt(),
                                    mainAxisSpacing: _getSize("cardMainAxisSpacing"),
                                    crossAxisSpacing: _getSize("cardCrossAxisSpacing"),
                                    childAspectRatio: _getSize("cardChildAspectRatio"),
                                  ),
                                  itemBuilder: (context, index) {
                                    final card = currentCards[index]['card'];
                                    final count = currentCards[index]['count'];

                                    final cardId = card['id'];
                                    final ownedCount = count;
                                    final selectedCount = _selectedDeckCards[cardId] ?? 0;
                                    final totalSelected = _selectedDeckCards.values.fold<int>(0, (sum, c) => sum + c);

                                    final bool shouldGrayOut =
                                        _isCreatingDeck && _selectedLeaderCard != null && (ownedCount == 0 || selectedCount >= ownedCount || selectedCount >= 4 || totalSelected >= 50);

                                    return GestureDetector(
                                      onTap: () {
                                        final cardId = card['id'];
                                        final ownedCount = count;
                                        final selectedCount = _selectedDeckCards[cardId] ?? 0;
                                        final totalSelected = _selectedDeckCards.values.fold<int>(0, (sum, c) => sum + c);

                                        final bool shouldGrayOut =
                                            _isCreatingDeck && _selectedLeaderCard != null && (ownedCount == 0 || selectedCount >= ownedCount || selectedCount >= 4 || totalSelected >= 50);

                                        if (_isCreatingDeck) {
                                          if (_selectedLeaderCard == null && card['type'] == 'Leader') {
                                            final leaderColors = (card['color'] as List).cast<String>();
                                            setState(() {
                                              _selectedLeaderCard = card;
                                              _selectedTypes
                                                ..clear()
                                                ..addAll(['Character', 'Event', 'Stage']);
                                              _selectedColors
                                                ..clear()
                                                ..addAll(leaderColors);
                                              _applyCombinedFilters();
                                            });
                                          } else if (_selectedLeaderCard != null && card['type'] != 'Leader') {
                                            setState(() {
                                              if (!shouldGrayOut) {
                                                _selectedDeckCards.update(cardId, (val) => val + 1, ifAbsent: () => 1);
                                              }
                                            });
                                          }
                                        }
                                        if (!_isCreatingDeck && _viewingDeck == null) {
                                          final collectionEntry = _allCards.firstWhere((c) => c['card']['id'] == cardId, orElse: () => null);
                                          final currentCount = collectionEntry != null ? collectionEntry['count'] ?? 0 : 0;
                                          _showCardDetailsDialog(card, currentCount);
                                        }
                                      },
                                      child: Stack(
                                        alignment: Alignment.bottomCenter,
                                        clipBehavior: Clip.none,
                                        children: [
                                          Positioned(
                                            bottom: _getSize("badgeBottomOffset"),
                                            child: Container(
                                              padding: EdgeInsets.symmetric(horizontal: _getSize("badgePaddingH"), vertical: _getSize("badgePaddingV")),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF9E0A0),
                                                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                                                border: Border.all(color: Colors.brown.shade800, width: _getSize("badgeBorderWidth")),
                                              ),
                                              child: Text(
                                                'x$count',
                                                style: TextStyle(fontSize: _getSize("badgeFont"), fontWeight: FontWeight.bold, color: Colors.black),
                                              ),
                                            ),
                                          ),
                                          Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(_getSize("cardBorderRadius")),
                                                child: ColorFiltered(
                                                  colorFilter: shouldGrayOut
                                                      ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                                                      : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                                                  child: Image.network("$baseUrl/${card['image']}", fit: BoxFit.cover),
                                                ),
                                              ),
                                              Positioned.fill(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Colors.brown.shade800, width: _getSize("cardBorderWidth")),
                                                    borderRadius: BorderRadius.circular(_getSize("cardBorderRadius")),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      if (_currentPage > 0)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: 0,
                          width: 80,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () async {
                              if (!_isCreatingDeck && _viewingDeck == null)
                              {
                                await _loadCollection();
                              }
                              setState(() => _currentPage--);
                            }, child: Container()),
                          ),
                        ),
                      if (_currentPage < totalPages - 1)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: 80,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () async {
                              if (!_isCreatingDeck && _viewingDeck == null)
                                {
                                  await _loadCollection();
                                }
                              setState(() => _currentPage++);
                            }, child: Container()),
                          ),
                        ),
                      Positioned(
                        bottom: _getSize("buttonsPositionBottom"),
                        left: _getSize("buttonsPositionLeft"),
                        child: Row(
                          children: [
                            CompositedTransformTarget(
                              link: _typeDropdownLink,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) => setState(() => _isHoveringType = true),
                                onExit: (_) => setState(() => _isHoveringType = false),
                                child: GestureDetector(
                                  onTap: _toggleTypeDropdown,
                                  child: Container(
                                    height: _getSize("typeColorButtonHeight"),
                                    padding: EdgeInsets.symmetric(horizontal: _getSize("typeColorButtonPaddingH")),
                                    decoration: BoxDecoration(
                                      color: _isHoveringType ? const Color.fromARGB(255, 233, 186, 92) : const Color.fromARGB(255, 242, 194, 96),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.brown.shade800, width: _getSize("typeColorButtonBorderWidth")),
                                      boxShadow: [
                                        BoxShadow(color: Colors.brown.shade500, offset: Offset(_getSize("typeColorButtonShadowOffset"), _getSize("typeColorButtonShadowOffset")), blurRadius: 0),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        "Type",
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: _getSize("typeColorTextSize")),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CompositedTransformTarget(
                              link: _colorDropdownLink,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) => setState(() => _isHoveringColor = true),
                                onExit: (_) => setState(() => _isHoveringColor = false),
                                child: GestureDetector(
                                  onTap: _toggleColorDropdown,
                                  child: Container(
                                    height: _getSize("typeColorButtonHeight"),
                                    padding: EdgeInsets.symmetric(horizontal: _getSize("typeColorButtonPaddingH")),
                                    decoration: BoxDecoration(
                                      color: _isHoveringColor ? const Color.fromARGB(255, 233, 186, 92) : const Color.fromARGB(255, 242, 194, 96),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.brown.shade800, width: _getSize("typeColorButtonBorderWidth")),
                                      boxShadow: [
                                        BoxShadow(color: Colors.brown.shade500, offset: Offset(_getSize("typeColorButtonShadowOffset"), _getSize("typeColorButtonShadowOffset")), blurRadius: 0),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        "Color",
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: _getSize("typeColorTextSize")),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            for (int i = 0; i <= 10; i++)
                              Padding(
                                padding: EdgeInsets.only(right: _getSize("costButtonPadding")),
                                child: SizedBox(
                                  height: _getSize("costButtonSize"),
                                  width: _getSize("costButtonSize"),
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: _getSize("costButtonSize"),
                                        width: _getSize("costButtonSize"),
                                        decoration: BoxDecoration(
                                          color: _selectedCosts.contains(i) ? Colors.brown.shade800 : const Color.fromARGB(255, 242, 194, 96),
                                          borderRadius: BorderRadius.circular(_getSize("costButtonSize")),
                                          border: Border.all(color: Colors.brown.shade800, width: _getSize("costButtonBorderWidth")),
                                          boxShadow: [BoxShadow(color: Colors.brown.shade600, offset: Offset(_getSize("costButtonShadowOffset"), _getSize("costButtonShadowOffset")), blurRadius: 0)],
                                        ),
                                        alignment: Alignment.center,
                                        child: Transform.translate(
                                          offset: Offset(0, _getSize("costButtonTextOffsetY")),
                                          child: Text(
                                            '$i',
                                            style: TextStyle(color: _selectedCosts.contains(i) ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: _getSize("costButtonFont")),
                                          ),
                                        ),
                                      ),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(onTap: () => _filterByCost(i), borderRadius: BorderRadius.circular(20)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            CompositedTransformTarget(
                              link: _layerLink,
                              child: SearchBarWidget(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: _fetchSuggestions,
                                onSubmitted: (text) {
                                  _handleSearch(text);
                                  _removeSuggestions();
                                },
                                style: SearchBarStyle(
                                  width: _getSize("searchBarWidth"),
                                  height: _getSize("searchBarHeight"),
                                  outerBorderWidth: _getSize("searchBarOuterBorderWidth"),
                                  innerBorderWidth: _getSize("searchBarInnerBorderWidth"),
                                  margin: _getSize("searchBarMargin"),
                                  paddingH: _getSize("searchBarContentPaddingH"),
                                  paddingV: _getSize("searchBarContentPaddingV"),
                                  fontSize: _getSize("searchBarFont"),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Stack(
                              children: [
                                Container(
                                  height: _getSize("searchAddButtonSize"),
                                  width: _getSize("searchAddButtonSize"),
                                  decoration: BoxDecoration(
                                    color: const Color.fromARGB(255, 242, 194, 96),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.brown.shade800, width: _getSize("searchAddButtonBorderWidth")),
                                    boxShadow: [
                                      BoxShadow(color: Colors.brown.shade500, offset: Offset(_getSize("searchAddButtonShadowOffset"), _getSize("searchAddButtonShadowOffset")), blurRadius: 0),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: _getSize("searchAddButtonSize"),
                                  width: _getSize("searchAddButtonSize"),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      _handleSearch(_searchController.text);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      elevation: 0,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: Icon(Icons.search, color: Colors.black, size: _getSize("searchAddIconSize")),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Stack(
                              children: [
                                Container(
                                  height: _getSize("searchAddButtonSize"),
                                  width: _getSize("searchAddButtonSize"),
                                  decoration: BoxDecoration(
                                    color: const Color.fromARGB(255, 242, 194, 96),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.brown.shade800, width: _getSize("searchAddButtonBorderWidth")),
                                    boxShadow: [
                                      BoxShadow(color: Colors.brown.shade500, offset: Offset(_getSize("searchAddButtonShadowOffset"), _getSize("searchAddButtonShadowOffset")), blurRadius: 0),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: _getSize("searchAddButtonSize"),
                                  width: _getSize("searchAddButtonSize"),
                                  child: ElevatedButton(
                                    onPressed: (_isCreatingDeck || _viewingDeck != null) ? null : () => _addCardFromSearch(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      elevation: 0,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: Icon(Icons.add, color: Colors.black, size: _getSize("searchAddIconSize")),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            if (selectedScreenMode == "Phone")
                              Stack(
                                children: [
                                  Container(
                                    height: _getSize("searchAddButtonSize"),
                                    width: _getSize("searchAddButtonSize"),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(255, 242, 194, 96),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.brown.shade800, width: _getSize("searchAddButtonBorderWidth")),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.brown.shade500,
                                          offset: Offset(_getSize("searchAddButtonShadowOffset"), _getSize("searchAddButtonShadowOffset")),
                                          blurRadius: 0,
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox (
                                    height: _getSize("searchAddButtonSize"),
                                    width: _getSize("searchAddButtonSize"),
                                    child: ElevatedButton (
                                      onPressed: () async {
                                        final added = await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LiveScanPage(token: widget.token),
                                          ),
                                        );

                                        if (added == true) {
                                          await _loadCollection();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        elevation: 0,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: Icon(Icons.camera_alt, color: Colors.black, size: _getSize("searchAddIconSize")),
                                    ),
                                  ),
                                ],
                              ),

                          ],
                        ),
                      ),

                      Positioned(
                        top: _getSize("settingsTop"),
                        right: _getSize("settingsRight"),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _isHoveringSettings = true),
                          onExit: (_) => setState(() => _isHoveringSettings = false),
                          child: GestureDetector(
                            onTap: _showSettingsDialog,
                            child: Container(
                              padding: EdgeInsets.all(_getSize("settingsPadding")),
                              decoration: BoxDecoration(
                                color: _isHoveringSettings ? const Color.fromARGB(255, 233, 186, 92) : const Color.fromARGB(255, 242, 194, 96),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.brown.shade800, width: _getSize("settingsBorderWidth")),
                                boxShadow: [BoxShadow(color: Colors.brown.shade500, offset: Offset(_getSize("settingsShadowOffset"), _getSize("settingsShadowOffset")), blurRadius: 0)],
                              ),
                              child: const Icon(Icons.settings, color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scanCheckTimer?.cancel();
    super.dispose();
  }
}