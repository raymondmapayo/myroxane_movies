import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lantaw_adblock/lantaw_adblock.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  test('blocks a known ad host and allows everything else', () async {
    final engine = AdblockEngine.fromListText(listText: '||doubleclick.net^');
    expect(
      engine.shouldBlock(
        url: 'https://doubleclick.net/ads.js',
        sourceUrl: 'https://example.com',
        requestType: 'script',
      ),
      isTrue,
    );
    expect(
      engine.shouldBlock(
        url: 'https://example.com/app.js',
        sourceUrl: 'https://example.com',
        requestType: 'script',
      ),
      isFalse,
    );
  });
}
