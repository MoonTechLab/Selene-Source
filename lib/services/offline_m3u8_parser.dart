// offline_m3u8_parser.dart
// 扩展版 m3u8 解析：递归主播放列表选子播放列表、处理 #EXT-X-KEY(AES-128)、
// #EXT-X-BYTERANGE、#EXT-X-MAP(fMP4 初始化段)、绝对/相对地址解析。
// 对应 MoonTV src/lib/m3u8-downloader.ts 的 parseM3U8。
import 'dart:convert';

class M3u8Key {
  final String method; // AES-128 / NONE / SAMPLE-AES
  final String? uri; // 已解析为绝对地址
  final String? iv; // 16 进制字符串，可空
  const M3u8Key({required this.method, this.uri, this.iv});

  bool get isAes128 => method.toUpperCase() == 'AES-128' && uri != null;
}

class M3u8Segment {
  final String url;
  final double duration;
  final String? byteRange; // 形如 "0-1023" 或 "1024@2048"
  final M3u8Key? key; // 该分片使用的密钥（继承播放列表级 key）
  const M3u8Segment({
    required this.url,
    this.duration = 0,
    this.byteRange,
    this.key,
  });
}

class ParsedM3u8 {
  final List<M3u8Segment> segments;
  final M3u8Key? key; // 播放列表级密钥（最后一个生效值）
  final String? initSegment; // #EXT-X-MAP 的绝对地址（fMP4 必须）
  final String container; // 'ts' | 'mp4'
  final bool isMaster;
  final int mediaSequence; // #EXT-X-MEDIA-SEQUENCE，用于推导缺省 IV
  const ParsedM3u8({
    required this.segments,
    this.key,
    this.initSegment,
    this.container = 'ts',
    this.isMaster = false,
    this.mediaSequence = 0,
  });
}

/// 解析 m3u8 文本（纯函数，无 IO，便于单测）。
ParsedM3u8 parseM3u8Content(String content, String baseUrl, {int depth = 0}) {
  final lines = const LineSplitter().convert(content);
  final isMaster = lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'));

  if (isMaster) {
    // 主播放列表：本函数只返回 master 标记，选档由调用方递归处理
    return ParsedM3u8(segments: const [], isMaster: true);
  }

  final segments = <M3u8Segment>[];
  M3u8Key? currentKey;
  String? initSegment;
  double dur = 0;
  String? pendingByteRange;
  var mediaSequence = 0;

  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#')) {
      if (l.startsWith('#EXT-X-KEY')) {
        final methodM = RegExp(r'METHOD=([^,]*)').firstMatch(l);
        final uriM = RegExp(r'URI="([^"]+)"').firstMatch(l);
        final ivM = RegExp(r'IV=([^,]*)').firstMatch(l);
        final method = (methodM?.group(1) ?? 'NONE').trim();
        final uri = uriM?.group(1);
        currentKey = M3u8Key(
          method: method,
          uri: uri != null ? resolveUrl(baseUrl, uri) : null,
          iv: _normalizeIv(ivM?.group(1)),
        );
      } else if (l.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
        final mM = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(l);
        if (mM != null) mediaSequence = int.tryParse(mM.group(1)!) ?? 0;
      } else if (l.startsWith('#EXT-X-MAP')) {
        final uriM = RegExp(r'URI="([^"]+)"').firstMatch(l);
        if (uriM != null) {
          initSegment = resolveUrl(baseUrl, uriM.group(1)!);
        }
      } else if (l.startsWith('#EXTINF')) {
        final dM = RegExp(r'#EXTINF:([\d.]+)').firstMatch(l);
        dur = dM != null ? double.tryParse(dM.group(1)!) ?? 0 : 0;
      } else if (l.startsWith('#EXT-X-BYTERANGE')) {
        final bM = RegExp(r'#EXT-X-BYTERANGE:(\S+)').firstMatch(l);
        pendingByteRange = bM?.group(1);
      }
      continue;
    }
    // 非 # 行 = 片段 URL
    segments.add(
      M3u8Segment(
        url: resolveUrl(baseUrl, l),
        duration: dur,
        byteRange: pendingByteRange,
        key: currentKey,
      ),
    );
    pendingByteRange = null;
  }

  return ParsedM3u8(
    segments: segments,
    key: currentKey,
    initSegment: initSegment,
    container: initSegment != null ? 'mp4' : 'ts',
    mediaSequence: mediaSequence,
  );
}

/// 从主播放列表文本中挑一个子播放列表地址。
/// 优先精确匹配 [preferredHeight]（如 '1080'），否则取 BANDWIDTH 最大者。
String? pickVariant(String content, String baseUrl, {String? preferredHeight}) {
  final lines = const LineSplitter().convert(content);
  String? chosen;
  int best = -1;
  String? exact;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (!l.startsWith('#EXT-X-STREAM-INF')) continue;
    String? next;
    for (var j = i + 1; j < lines.length; j++) {
      final t = lines[j].trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      next = t;
      break;
    }
    if (next == null) continue;
    final bwM = RegExp(r'BANDWIDTH=(\d+)').firstMatch(l);
    final bw = bwM != null ? int.tryParse(bwM.group(1)!) ?? 0 : 0;
    final resM = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(l);
    final height = resM?.group(1);
    if (preferredHeight != null && height == preferredHeight) {
      exact = next;
      break;
    }
    if (bw > best) {
      best = bw;
      chosen = next;
    }
  }
  final pick = exact ?? chosen;
  return pick == null ? null : resolveUrl(baseUrl, pick);
}

/// 相对地址 → 绝对地址。
String resolveUrl(String base, String url) {
  final u = url.trim();
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final b = Uri.tryParse(base);
  if (b == null) return u;
  if (u.startsWith('//')) return '${b.scheme}:$u';
  return b.resolve(u).toString();
}

String? _normalizeIv(String? iv) {
  if (iv == null) return null;
  var v = iv.trim();
  if (v.isEmpty || v.toUpperCase() == 'NONE') return null;
  if (v.startsWith('0x') || v.startsWith('0X')) v = v.substring(2);
  if (v.length.isOdd) v = '0$v';
  return v;
}
