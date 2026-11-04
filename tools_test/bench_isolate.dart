// bench_isolate.dart —— 对比「本线程解密」与「Isolate.run 解密」的往返开销。
import 'dart:isolate';
import 'dart:typed_data';

import '../lib/services/offline_aes.dart';

Future<void> main() async {
  final key = Uint8List.fromList(List<int>.generate(16, (i) => i * 7 + 1));
  final iv = OfflineAes.ivFromSequence(12345);
  final cipher = Uint8List(700 * 1024);

  Future<int> inIsolate() async {
    return Isolate.run(() {
      OfflineAes.decryptCbcPkcs7(cipher, key, iv);
      return 0;
    });
  }

  // 空 isolate 往返基线：衡量纯调度开销
  final sw0 = Stopwatch()..start();
  for (var i = 0; i < 10; i++) {
    await Isolate.run(() => 0);
  }
  sw0.stop();
  print('空 isolate 往返基线: ${(sw0.elapsedMicroseconds / 10 / 1000).toStringAsFixed(2)} ms/次');

  for (var i = 0; i < 3; i++) {
    await inIsolate();
  }
  const rounds = 20;

  final sw1 = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    OfflineAes.decryptCbcPkcs7(cipher, key, iv);
  }
  sw1.stop();
  print('本线程 700KB: ${(sw1.elapsedMicroseconds / rounds / 1000).toStringAsFixed(2)} ms');

  final sw2 = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    await inIsolate();
  }
  sw2.stop();
  print('Isolate 700KB: ${(sw2.elapsedMicroseconds / rounds / 1000).toStringAsFixed(2)} ms');
}
