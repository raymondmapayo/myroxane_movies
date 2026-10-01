import 'package:flutter/material.dart';
import 'package:lantaw_adblock/lantaw_adblock.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = AdblockEngine.fromListText(
      listText: '||doubleclick.net^\n||googlesyndication.com^',
    );
    final blocked = engine.shouldBlock(
      url: 'https://doubleclick.net/ads.js',
      sourceUrl: 'https://example.com',
      requestType: 'script',
    );
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('lantaw_adblock quickstart')),
        body: Center(
          child: Text('doubleclick.net blocked: $blocked'),
        ),
      ),
    );
  }
}
