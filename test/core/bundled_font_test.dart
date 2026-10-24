import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Itim is bundled, so Thai text needs no network', () async {
    final data = await rootBundle.load('google_fonts/Itim-Regular.ttf');
    // TrueType files start with the version tag 0x00010000.
    expect(data.lengthInBytes, greaterThan(100000));
    expect(data.getUint32(0), 0x00010000);
  });

  test('the font licence ships with it', () async {
    final text = await rootBundle.loadString('google_fonts/OFL.txt');
    expect(text, contains('SIL Open Font License'));
  });
}
