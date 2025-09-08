import 'imports.dart';

class ScannedResultPage extends StatelessWidget {
  final Uint8List imageBytes;
  final List<Map<String, dynamic>> cardList;

  const ScannedResultPage({super.key, required this.imageBytes, required this.cardList});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detected Cards')),
      body: Stack(
        children: [
          Image.memory(imageBytes, width: double.infinity, fit: BoxFit.contain),
          ...cardList.map((card) {
            final box = card['box'];
            return Positioned(
              left: box[0] * MediaQuery.of(context).size.width,
              top: box[1] * MediaQuery.of(context).size.height,
              width: box[2] * MediaQuery.of(context).size.width,
              height: box[3] * MediaQuery.of(context).size.height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.redAccent, width: 2),
                  color: Colors.redAccent.withOpacity(0.1),
                ),
                child: Center(
                  child: Text(
                    card['label'] ?? 'Card',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
