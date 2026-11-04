// bench_aes.dart —— 实测单分片 AES-128-CBC 解密耗时，用于判断是否需要 isolate。
import 'dart:typed_data';

import '../lib/services/offline_aes.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(16, (i) => i * 7 + 1));
  final iv = OfflineAes.ivFromSequence(12345);

  for (final kb in [128, 512, 700, 1024]) {
    final plain = Uint8List(kb * 1024);
    for (var i = 0; i < plain.length; i++) {
      plain[i] = i & 0xff;
    }
    // 用同一套 CBC 逻辑造密文：这里只需要等长输入，内容不重要。
    final cipher = Uint8List.fromList(plain);

    // 预热
    for (var i = 0; i < 3; i++) {
      OfflineAes.decryptCbcPkcs7(cipher, key, iv);
    }

    const rounds = 20;
    final sw = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      OfflineAes.decryptCbcPkcs7(cipher, key, iv);
    }
    sw.stop();
    final per = sw.elapsedMicroseconds / rounds / 1000.0;
    print('${kb}KB: ${per.toStringAsFixed(2)} ms/片  '
        '(${(kb * 1024 / 1024 / (per / 1000)).toStringAsFixed(1)} MB/s)');
  }
}
