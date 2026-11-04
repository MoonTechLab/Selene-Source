// offline_aes.dart
// 纯 Dart 实现的 AES-128-CBC 解密（含 PKCS7 去填充），用于解密 HLS 的
// #EXT-X-KEY:METHOD=AES-128 加密分片。
//
// 之所以不引入 encrypt/pointycastle 依赖：本功能只需「解密 + 去填充」这
// 一小块能力，自己实现可让工程零新增依赖（避免 pub 解析失败/源不可达），
// 且 AES 是对称定长算法，代码可被 NIST 测试向量完全验证。
//
// 参考：FIPS-197 (AES)，RFC 8216 §5.2 (HLS AES-128，IV 缺省时用媒体序号)。
import 'dart:typed_data';

/// AES-128 CBC 解密器（无状态，全部静态方法）。
class OfflineAes {
  OfflineAes._();

  static Uint8List? _sbox;
  static Uint8List? _invSbox;

  // ---- T 表（等价逆密码的快速实现）------------------------------------------
  // 朴素的逐字节逆变换要对每个状态字节做 16 次 GF(2^8) 乘法（每次 8 轮分支），
  // 700KB 分片要跑 500ms 量级，是缓存时卡顿的主要源头。
  // T 表把「InvSubBytes + InvMixColumns」合并成 4 张 256 项表，每轮只剩查表 +
  // 异或；配合「按 32 位字运算」让主循环里没有分支，实测提速约一个数量级。
  static Uint32List? _td0, _td1, _td2, _td3;
  static Uint8List? _invSboxFast;

  /// GF(2^8) 乘法（不可约多项式 0x11b）。
  static int _gfMul(int a, int b) {
    var p = 0;
    var x = a & 0xff;
    var y = b & 0xff;
    for (var i = 0; i < 8; i++) {
      if ((y & 1) != 0) p ^= x;
      final hi = x & 0x80;
      x = (x << 1) & 0xff;
      if (hi != 0) x ^= 0x1b;
      y >>= 1;
    }
    return p & 0xff;
  }

  /// GF(2^8) 乘法逆元：a^254。
  static int _gfInv(int a) {
    if (a == 0) return 0;
    var r = 1;
    var base = a & 0xff;
    var e = 254;
    while (e > 0) {
      if ((e & 1) != 0) r = _gfMul(r, base);
      base = _gfMul(base, base);
      e >>= 1;
    }
    return r;
  }

  static int _rotl8(int b, int n) => (((b << n) | (b >> (8 - n))) & 0xff);

  static void _ensureTables() {
    if (_sbox != null) return;
    final s = Uint8List(256);
    final inv = Uint8List(256);
    for (var x = 0; x < 256; x++) {
      final q = _gfInv(x);
      final v =
          q ^ _rotl8(q, 1) ^ _rotl8(q, 2) ^ _rotl8(q, 3) ^ _rotl8(q, 4) ^ 0x63;
      s[x] = v & 0xff;
    }
    for (var x = 0; x < 256; x++) {
      inv[s[x]] = x;
    }
    _sbox = s;
    _invSbox = inv;
    _invSboxFast = inv;
    _buildTdTables(inv);
  }

  /// 构造 4 张逆 T 表。经典构造（Daemen & Rijmen）：
  ///   Td0[x] = S^-1(x) * [0e,09,0d,0b]^T   （列向量，每项 4 字节）
  ///   Td1[x] = rotr8(Td0[x]) … Td2、Td3 依次再转 8 位
  static void _buildTdTables(Uint8List inv) {
    final t0 = Uint32List(256);
    for (var x = 0; x < 256; x++) {
      final sx = inv[x];
      final b0 = _gfMul(sx, 0x0e);
      final b1 = _gfMul(sx, 0x09);
      final b2 = _gfMul(sx, 0x0d);
      final b3 = _gfMul(sx, 0x0b);
      // 大端打包：最高位字节在 b0
      t0[x] = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }
    final t1 = Uint32List(256);
    final t2 = Uint32List(256);
    final t3 = Uint32List(256);
    for (var x = 0; x < 256; x++) {
      final v = t0[x];
      t1[x] = ((v >> 8) | (v << 24)) & 0xffffffff; // rotr 8
      t2[x] = ((v >> 16) | (v << 16)) & 0xffffffff; // rotr 16
      t3[x] = ((v >> 24) | (v << 8)) & 0xffffffff; // rotr 24
    }
    _td0 = t0;
    _td1 = t1;
    _td2 = t2;
    _td3 = t3;
  }

  /// 暴露轮密钥扩展供交叉验证测试使用（生产代码请用 decryptCbc* 系列）。
  static Uint8List expandKeyForTest(List<int> key) => _expandKey(key);

  /// 仅支持 128 位密钥；返回 11 组轮密钥（每组 16 字节，共 176 字节）。
  static Uint8List _expandKey(List<int> key) {
    _ensureTables();
    if (key.length != 16) {
      throw ArgumentError('AES-128 需要 16 字节密钥，实际 ${key.length}');
    }
    final w = Uint8List(176);
    w.setRange(0, 16, key);
    var rcon = 1;
    for (var i = 16; i < 176; i += 4) {
      var t0 = w[i - 4];
      var t1 = w[i - 3];
      var t2 = w[i - 2];
      var t3 = w[i - 1];
      if (i % 16 == 0) {
        // RotWord
        final tmp = t0;
        t0 = t1;
        t1 = t2;
        t2 = t3;
        t3 = tmp;
        // SubWord
        t0 = _sbox![t0];
        t1 = _sbox![t1];
        t2 = _sbox![t2];
        t3 = _sbox![t3];
        t0 ^= rcon;
        rcon = _gfMul(rcon, 2);
      }
      w[i] = w[i - 16] ^ t0;
      w[i + 1] = w[i - 15] ^ t1;
      w[i + 2] = w[i - 14] ^ t2;
      w[i + 3] = w[i - 13] ^ t3;
    }
    return w;
  }

  static void _addRoundKey(Uint8List s, Uint8List w, int round) {
    final off = round * 16;
    for (var i = 0; i < 16; i++) {
      s[i] ^= w[off + i];
    }
  }

  static void _invSubBytes(Uint8List s) {
    final inv = _invSbox!;
    for (var i = 0; i < 16; i++) {
      s[i] = inv[s[i]];
    }
  }

  /// 状态按列优先存放：index = row + 4*col。
  static void _invShiftRows(Uint8List s) {
    final t = Uint8List.fromList(s);
    for (var r = 1; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        s[r + 4 * ((c + r) % 4)] = t[r + 4 * c];
      }
    }
  }

  static void _invMixColumns(Uint8List s) {
    for (var c = 0; c < 4; c++) {
      final i = 4 * c;
      final a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
      s[i] = _gfMul(a0, 14) ^ _gfMul(a1, 11) ^ _gfMul(a2, 13) ^ _gfMul(a3, 9);
      s[i + 1] =
          _gfMul(a0, 9) ^ _gfMul(a1, 14) ^ _gfMul(a2, 11) ^ _gfMul(a3, 13);
      s[i + 2] =
          _gfMul(a0, 13) ^ _gfMul(a1, 9) ^ _gfMul(a2, 14) ^ _gfMul(a3, 11);
      s[i + 3] =
          _gfMul(a0, 11) ^ _gfMul(a1, 13) ^ _gfMul(a2, 9) ^ _gfMul(a3, 14);
    }
  }

  /// 单块解密（逐字节参考实现）。保留仅供对照/测试，生产路径走 T 表版本。
  static Uint8List decryptBlockReference(Uint8List input, Uint8List w) {
    _ensureTables();
    final s = Uint8List.fromList(input);
    _addRoundKey(s, w, 10);
    for (var round = 9; round >= 1; round--) {
      _invShiftRows(s);
      _invSubBytes(s);
      _addRoundKey(s, w, round);
      _invMixColumns(s);
    }
    _invShiftRows(s);
    _invSubBytes(s);
    _addRoundKey(s, w, 0);
    return s;
  }

  /// CBC 解密，不做去填充（供单元测试/无填充场景）。
  /// 密文长度必须是 16 的整数倍。
  ///
  /// 实现说明：状态按 4 个 32 位大端字（s0..s3）保存，每轮用 4 张 T 表查表
  /// 替代逐字节 InvSubBytes+InvMixColumns；最后一轮不做 MixColumns，改用
  /// InvSbox 直接组装。CBC 的串联异或直接作用在 32 位字上，省掉一次逐字节循环。
  static Uint8List decryptCbcRaw(
    List<int> cipher,
    List<int> key,
    List<int> iv,
  ) {
    if (cipher.length % 16 != 0) {
      throw ArgumentError('密文长度 ${cipher.length} 不是 16 的倍数');
    }
    _ensureTables();
    final rk = _decryptKeyWords(key);
    final td0 = _td0!, td1 = _td1!, td2 = _td2!, td3 = _td3!;
    final inv = _invSboxFast!;
    final ivb = _normalizeIv(iv);
    final out = Uint8List(cipher.length);

    // 上一块密文（CBC 串联），初值为 IV。
    var p0 = _be32(ivb, 0);
    var p1 = _be32(ivb, 4);
    var p2 = _be32(ivb, 8);
    var p3 = _be32(ivb, 12);

    for (var off = 0; off < cipher.length; off += 16) {
      final c0 = _be32(cipher, off);
      final c1 = _be32(cipher, off + 4);
      final c2 = _be32(cipher, off + 8);
      final c3 = _be32(cipher, off + 12);

      var s0 = c0 ^ rk[40];
      var s1 = c1 ^ rk[41];
      var s2 = c2 ^ rk[42];
      var s3 = c3 ^ rk[43];

      for (var r = 9; r >= 1; r--) {
        final k = r << 2;
        final t0 = td0[s0 >> 24] ^
            td1[(s3 >> 16) & 0xff] ^
            td2[(s2 >> 8) & 0xff] ^
            td3[s1 & 0xff] ^
            rk[k];
        final t1 = td0[s1 >> 24] ^
            td1[(s0 >> 16) & 0xff] ^
            td2[(s3 >> 8) & 0xff] ^
            td3[s2 & 0xff] ^
            rk[k + 1];
        final t2 = td0[s2 >> 24] ^
            td1[(s1 >> 16) & 0xff] ^
            td2[(s0 >> 8) & 0xff] ^
            td3[s3 & 0xff] ^
            rk[k + 2];
        final t3 = td0[s3 >> 24] ^
            td1[(s2 >> 16) & 0xff] ^
            td2[(s1 >> 8) & 0xff] ^
            td3[s0 & 0xff] ^
            rk[k + 3];
        s0 = t0;
        s1 = t1;
        s2 = t2;
        s3 = t3;
      }

      // 最后一轮：InvShiftRows + InvSubBytes + AddRoundKey(0)
      final o0 = ((inv[s0 >> 24] << 24) |
              (inv[(s3 >> 16) & 0xff] << 16) |
              (inv[(s2 >> 8) & 0xff] << 8) |
              inv[s1 & 0xff]) ^
          rk[0];
      final o1 = ((inv[s1 >> 24] << 24) |
              (inv[(s0 >> 16) & 0xff] << 16) |
              (inv[(s3 >> 8) & 0xff] << 8) |
              inv[s2 & 0xff]) ^
          rk[1];
      final o2 = ((inv[s2 >> 24] << 24) |
              (inv[(s1 >> 16) & 0xff] << 16) |
              (inv[(s0 >> 8) & 0xff] << 8) |
              inv[s3 & 0xff]) ^
          rk[2];
      final o3 = ((inv[s3 >> 24] << 24) |
              (inv[(s2 >> 16) & 0xff] << 16) |
              (inv[(s1 >> 8) & 0xff] << 8) |
              inv[s0 & 0xff]) ^
          rk[3];

      // CBC：明文 = 解出的块 ^ 上一块密文
      _putBe32(out, off, o0 ^ p0);
      _putBe32(out, off + 4, o1 ^ p1);
      _putBe32(out, off + 8, o2 ^ p2);
      _putBe32(out, off + 12, o3 ^ p3);

      p0 = c0;
      p1 = c1;
      p2 = c2;
      p3 = c3;
    }
    return out;
  }

  static int _be32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static void _putBe32(Uint8List b, int o, int v) {
    b[o] = (v >> 24) & 0xff;
    b[o + 1] = (v >> 16) & 0xff;
    b[o + 2] = (v >> 8) & 0xff;
    b[o + 3] = v & 0xff;
  }

  /// 轮密钥按 32 位大端字重排，并改造成「等价逆密码」所需的解密密钥序列。
  ///
  /// 这是 T 表演算法正确性的关键一步：等价逆密码的中间轮用 InvMixColumns
  /// 代替 MixColumns，因此中间轮密钥也必须先做一次 InvMixColumns，否则只有
  /// 首尾两轮是对的、中间结果全错（表现为解出来是乱码但长度正确）。
  /// 顺序为：轮密钥 10（原样）→ 轮密钥 9..1（各做 InvMixColumns）→ 轮密钥 0。
  static Uint32List _decryptKeyWords(List<int> key) {
    final w = _expandKey(key);
    final raw = Uint32List(44);
    for (var i = 0; i < 44; i++) {
      raw[i] = _be32(w, i * 4);
    }
    final rk = Uint32List(44);
    // rk[40..43] = 轮密钥 10（首次 AddRoundKey，不做 InvMixColumns）
    for (var i = 0; i < 4; i++) {
      rk[40 + i] = raw[40 + i];
    }
    // 中间轮 9..1：各自先做 InvMixColumns
    for (var r = 9; r >= 1; r--) {
      for (var k = 0; k < 4; k++) {
        rk[r * 4 + k] = _invMixColWord(raw[r * 4 + k]);
      }
    }
    // 末轮使用轮密钥 0（原样）
    for (var i = 0; i < 4; i++) {
      rk[i] = raw[i];
    }
    return rk;
  }

  /// 对一个 32 位字做 InvMixColumns（列向量 [14,11,13,9] 矩阵乘）。
  static int _invMixColWord(int v) {
    final a0 = (v >> 24) & 0xff;
    final a1 = (v >> 16) & 0xff;
    final a2 = (v >> 8) & 0xff;
    final a3 = v & 0xff;
    final r0 = _gfMul(a0, 14) ^ _gfMul(a1, 11) ^ _gfMul(a2, 13) ^ _gfMul(a3, 9);
    final r1 = _gfMul(a0, 9) ^ _gfMul(a1, 14) ^ _gfMul(a2, 11) ^ _gfMul(a3, 13);
    final r2 = _gfMul(a0, 13) ^ _gfMul(a1, 9) ^ _gfMul(a2, 14) ^ _gfMul(a3, 11);
    final r3 = _gfMul(a0, 11) ^ _gfMul(a1, 13) ^ _gfMul(a2, 9) ^ _gfMul(a3, 14);
    return (r0 << 24) | (r1 << 16) | (r2 << 8) | r3;
  }

  /// CBC 解密 + 去 PKCS7 填充（HLS 分片标准用法）。
  static Uint8List decryptCbcPkcs7(
    List<int> cipher,
    List<int> key,
    List<int> iv,
  ) {
    final raw = decryptCbcRaw(cipher, key, iv);
    final n = _pkcs7PadLen(raw);
    if (n == 0) return raw; // 填充不合法：原样返回，交给播放器容错
    return Uint8List.sublistView(raw, 0, raw.length - n);
  }

  /// 返回合法 PKCS7 填充长度；不合法返回 0。
  static int _pkcs7PadLen(Uint8List data) {
    if (data.isEmpty) return 0;
    final p = data[data.length - 1];
    if (p < 1 || p > 16 || p > data.length) return 0;
    for (var i = data.length - p; i < data.length; i++) {
      if (data[i] != p) return 0;
    }
    return p;
  }

  /// IV 归一化：不足 16 字节左侧补 0，超过则截断。
  static Uint8List _normalizeIv(List<int> iv) {
    final b = Uint8List(16);
    if (iv.isEmpty) return b;
    if (iv.length >= 16) {
      b.setRange(0, 16, iv);
    } else {
      b.setRange(0, iv.length, iv);
    }
    return b;
  }

  /// 由十六进制字符串构造 IV（HLS `IV=0x...`）。
  static Uint8List ivFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return Uint8List(16);
    var h = hex;
    if (h.startsWith('0x') || h.startsWith('0X')) h = h.substring(2);
    if (h.length.isOdd) h = '0$h';
    final b = Uint8List(h.length ~/ 2);
    for (var i = 0; i < b.length; i++) {
      b[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return b;
  }

  /// RFC 8216 §5.2：未提供 IV 时，IV = 媒体序号（64 位大端）放在 16 字节尾部。
  static Uint8List ivFromSequence(int sequence) {
    final b = Uint8List(16);
    var v = sequence;
    for (var i = 15; i >= 0 && v > 0; i--) {
      b[i] = v & 0xff;
      v = v >> 8;
    }
    return b;
  }
}
