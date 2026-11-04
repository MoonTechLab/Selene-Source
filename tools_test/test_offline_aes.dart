// test_offline_aes.dart
// 用 NIST SP 800-38A / FIPS-197 官方向量验证 offline_aes.dart 的 CBC 解密。
import 'dart:typed_data';
import '../lib/services/offline_aes.dart';

List<int> hex(String s) {
  final b = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    b.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return b;
}

String toHex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

int failures = 0;
void check(String name, String got, String want) {
  if (got != want) {
    failures++;
    print('FAIL $name\n  got  $got\n  want $want');
  } else {
    print('PASS $name');
  }
}

void main() {
  // NIST SP 800-38A F.2.1 CBC-AES128.Decrypt (blocks 1..4)
  final key = hex('2b7e151628aed2a6abf7158809cf4f3c');
  final iv = hex('000102030405060708090a0b0c0d0e0f');
  final ct = hex('7649abac8119b246cee98e9b12e9197d'
      '5086cb9b507219ee95db113a917678b2'
      '73bed6b8e3c1743b7116e69e22229516'
      '3ff1caa1681fac09120eca307586e1a7');
  final want = '6bc1bee22e409f96e93d7e117393172a'
      'ae2d8a571e03ac9c9eb76fac45af8e51'
      '30c81c46a35ce411e5fbc1191a0a52ef'
      'f69f2445df4f9b17ad2b417be66c3710';

  check('NIST SP800-38A CBC-AES128 decrypt 4 blocks',
      toHex(OfflineAes.decryptCbcRaw(ct, key, iv)), want);

  // FIPS-197 C.1 单块（CBC with zero IV 的第一个块等价于 ECB）
  final k2 = hex('000102030405060708090a0b0c0d0e0f');
  final c2 = hex('69c4e0d86a7b0430d8cdb78070b4c55a');
  check('FIPS-197 C.1 AES-128 block',
      toHex(OfflineAes.decryptCbcRaw(c2, k2, List<int>.filled(16, 0))),
      '00112233445566778899aabbccddeeff');

  // PKCS7 去填充：对全 0x10 填充块解密后长度应为 0
  final padOnly = OfflineAes.decryptCbcRaw(
      List<int>.filled(16, 0), k2, List<int>.filled(16, 0));
  print('pkcs7 raw(16 zero ct) len=${padOnly.length}');

  // IV 构造
  check('ivFromHex 0x-prefixed', toHex(OfflineAes.ivFromHex('0x000102030405060708090a0b0c0d0e0f')),
      '000102030405060708090a0b0c0d0e0f');
  check('ivFromSequence(1)', toHex(OfflineAes.ivFromSequence(1)),
      '00000000000000000000000000000001');
  check('ivFromSequence(0x0102030405060708)',
      toHex(OfflineAes.ivFromSequence(0x0102030405060708)),
      '00000000000000000102030405060708');

  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILURE(S)');
}
