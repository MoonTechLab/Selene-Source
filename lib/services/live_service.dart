import 'dart:convert';

import 'package:heintv/services/local_mode_storage_service.dart';
import 'package:heintv/services/user_data_service.dart';

import '../models/live_channel.dart';
import '../models/live_source.dart';
import '../models/epg_program.dart';
import '../models/m3u_content.dart';
import 'api_service.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';
import 'package:gbk_codec/gbk_codec.dart';

// ignore: unused_import
import 'dart:async' show unawaited;

/// 缓存项
class _CacheItem<T> {
  final T data;
  final DateTime cacheTime;

  _CacheItem(this.data, this.cacheTime);

  /// 检查缓存是否过期
  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(cacheTime) > maxAge;
  }
}

/// 直播服务
class LiveService {
  // 缓存存储
  static _CacheItem<List<LiveSource>>? _liveSourcesCache;
  static final Map<String, _CacheItem<M3uContent>> _channelsCache = {};
  static final Map<String, _CacheItem<Map<String, EpgData>>> _epgCache = {};

  static const Duration _sourceCacheDuration = Duration(hours: 2);
  static const Duration _channelCacheDuration = Duration(hours: 2);
  static const Duration _epgCacheDuration = Duration(hours: 2);

  /// 获取所有直播源（乐观缓存：过期时先返回旧数据，后台异步刷新）
  static Future<List<LiveSource>> getLiveSources(
      {bool forceRefresh = false}) async {
    // 如果有缓存且未过期，直接返回
    if (!forceRefresh &&
        _liveSourcesCache != null &&
        !_liveSourcesCache!.isExpired(_sourceCacheDuration)) {
      return _liveSourcesCache!.data;
    }

    // 如果有缓存但已过期，先返回旧数据，然后异步刷新
    if (!forceRefresh && _liveSourcesCache != null) {
      // 异步刷新缓存（不等待）
      unawaited(_fetchAndCacheLiveSources());
      // 立即返回旧数据
      return _liveSourcesCache!.data;
    }

    // 没有缓存或强制刷新，同步获取
    return await _fetchAndCacheLiveSources();
  }

  /// 获取并缓存直播源
  static Future<List<LiveSource>> _fetchAndCacheLiveSources() async {
    try {
      final isLocalMode = await UserDataService.getIsLocalMode();
      List<LiveSource> sources;
      if (isLocalMode) {
        sources = await LocalModeStorageService.getLiveSources();
      } else {
        sources = await ApiService.getLiveSources();
      }
      _liveSourcesCache = _CacheItem(sources, DateTime.now());
      return sources;
    } catch (e) {
      print('获取直播源失败: $e');
      return _liveSourcesCache?.data ?? [];
    }
  }

  /// 获取指定直播源的频道列表（乐观缓存：过期时先返回旧数据，后台异步刷新）
  static Future<List<LiveChannel>> getLiveChannels(String sourceKey,
      {bool forceRefresh = false}) async {
    // 如果有缓存且未过期，直接返回
    if (!forceRefresh && _channelsCache.containsKey(sourceKey)) {
      final cache = _channelsCache[sourceKey]!;
      if (!cache.isExpired(_channelCacheDuration)) {
        return cache.data.channels;
      }
    }

    // 如果有缓存但已过期，先返回旧数据，然后异步刷新
    if (!forceRefresh && _channelsCache.containsKey(sourceKey)) {
      // 异步刷新缓存（不等待）
      unawaited(_fetchAndCacheChannels(sourceKey));
      // 立即返回旧数据
      return _channelsCache[sourceKey]!.data.channels;
    }

    // 没有缓存或强制刷新，同步获取
    return await _fetchAndCacheChannels(sourceKey);
  }

  /// 获取并缓存频道列表
  static Future<List<LiveChannel>> _fetchAndCacheChannels(
      String sourceKey) async {
    try {
      // 从缓存中获取对应的 LiveSource
      final liveSource = _liveSourcesCache?.data.firstWhere(
          (source) => source.key == sourceKey,
          orElse: () => throw Exception('未找到直播源: $sourceKey'));

      if (liveSource == null) {
        throw Exception('未找到直播源: $sourceKey');
      }

      // 确定使用的 User-Agent
      final userAgent =
          liveSource.ua.isEmpty ? 'AptvPlayer/1.4.10' : liveSource.ua;

      // 请求 M3U 内容
      final response = await http.get(
        Uri.parse(liveSource.url),
        headers: {'User-Agent': userAgent},
      );

      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode}');
      }

      // 处理编码，尝试多种编码方式
      final m3uText = _decodeResponse(response.bodyBytes);

      // 解析 M3U 内容
      final m3uContent = _parseM3U(sourceKey, m3uText);

      // 缓存结果
      _channelsCache[sourceKey] = _CacheItem(m3uContent, DateTime.now());
      return m3uContent.channels;
    } catch (e) {
      print('获取直播频道失败: $e');
      return _channelsCache[sourceKey]?.data.channels ?? [];
    }
  }

  /// 智能解码响应内容，支持 UTF-8、GBK、GB2312 等编码
  static String _decodeResponse(List<int> bytes) {
    // 1. 首先尝试 UTF-8 解码
    try {
      final utf8Text = utf8.decode(bytes, allowMalformed: false);
      // 检查是否有替换字符（�），如果有说明解码失败
      if (!utf8Text.contains('�')) {
        return utf8Text;
      }
    } catch (e) {
      // UTF-8 解码失败，继续尝试其他编码
    }

    // 2. 尝试 GBK 解码（GBK 是 GB2312 的超集，兼容 GB2312）
    try {
      final gbkText = gbk.decode(bytes);
      // 简单验证：检查是否包含常见的中文字符或标点
      if (gbkText.isNotEmpty) {
        return gbkText;
      }
    } catch (e) {
      // GBK 解码失败
    }

    // 3. 最后尝试 Latin1 作为回退（不会抛出异常）
    return latin1.decode(bytes);
  }

  /// 解析 M3U 内容
  static M3uContent _parseM3U(String sourceKey, String m3uContent) {
    final channels = <LiveChannel>[];
    final lines = m3uContent
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    String tvgUrl = '';
    int channelIndex = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 检查是否是 #EXTM3U 行，提取 tvg-url
      if (line.startsWith('#EXTM3U')) {
        // 支持两种格式：x-tvg-url 和 url-tvg
        final tvgUrlMatch =
            RegExp(r'(?:x-tvg-url|url-tvg)="([^"]*)"').firstMatch(line);
        if (tvgUrlMatch != null) {
          tvgUrl = tvgUrlMatch.group(1)?.split(',')[0].trim() ?? '';
        }
        continue;
      }

      // 检查是否是 #EXTINF 行
      if (line.startsWith('#EXTINF:')) {
        // 提取 tvg-id
        final tvgIdMatch = RegExp(r'tvg-id="([^"]*)"').firstMatch(line);
        final tvgId = tvgIdMatch?.group(1) ?? '';

        // 提取 tvg-name
        final tvgNameMatch = RegExp(r'tvg-name="([^"]*)"').firstMatch(line);
        final tvgName = tvgNameMatch?.group(1) ?? '';

        // 提取 tvg-logo
        final tvgLogoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
        final logo = tvgLogoMatch?.group(1) ?? '';

        // 提取 group-title
        final groupTitleMatch =
            RegExp(r'group-title="([^"]*)"').firstMatch(line);
        final group = groupTitleMatch?.group(1) ?? '无分组';

        // 提取标题（#EXTINF 行最后的逗号后面的内容）
        // 使用 lastIndexOf 更健壮，避免频道名中包含逗号的问题
        final commaIndex = line.lastIndexOf(',');
        final title = commaIndex != -1 && commaIndex < line.length - 1
            ? line.substring(commaIndex + 1).trim()
            : '';

        // 优先使用 title（逗号后的内容），如果没有则使用 tvg-name
        final name = title.isNotEmpty ? title : tvgName;

        // 检查下一行是否是URL
        if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
          final url = lines[i + 1];

          // 只有当有名称和URL时才添加到结果中，并验证URL格式
          if (name.isNotEmpty && url.isNotEmpty && Uri.tryParse(url) != null) {
            channels.add(LiveChannel(
              id: '$sourceKey-$channelIndex',
              tvgId: tvgId,
              name: name,
              logo: logo,
              group: group,
              url: url,
            ));
            channelIndex++;
          }

          // 跳过下一行，因为已经处理了
          i++;
        }
      }
    }

    return M3uContent(tvgUrl: tvgUrl, channels: channels);
  }

  /// 获取 EPG 节目单（乐观缓存：过期时先返回旧数据，后台异步刷新）
  static Future<EpgData?> getLiveEpg(String tvgId, String sourceKey,
      {bool forceRefresh = false}) async {
    // 如果有缓存且未过期，从缓存中查找对应 tvgId 的数据
    if (!forceRefresh && _epgCache.containsKey(sourceKey)) {
      final cache = _epgCache[sourceKey]!;
      if (!cache.isExpired(_epgCacheDuration)) {
        final epgData = cache.data[tvgId];
        if (epgData != null) {
          return epgData;
        }
      }
    }

    // 如果有缓存但已过期，先返回旧数据，然后异步刷新
    if (!forceRefresh && _epgCache.containsKey(sourceKey)) {
      final epgData = _epgCache[sourceKey]!.data[tvgId];
      if (epgData != null) {
        // 异步刷新缓存（不等待）
        unawaited(_fetchAndCacheEpg(sourceKey));
        // 立即返回旧数据
        return epgData;
      }
    }

    // 没有缓存或强制刷新，同步获取
    await _fetchAndCacheEpg(sourceKey);
    return _epgCache[sourceKey]?.data[tvgId];
  }

  /// 获取并缓存 EPG 数据
  static Future<void> _fetchAndCacheEpg(String sourceKey) async {
    try {
      // 从缓存中获取对应的 LiveSource
      final liveSource = _liveSourcesCache?.data.firstWhere(
        (source) => source.key == sourceKey,
        orElse: () => throw Exception('未找到直播源: $sourceKey'),
      );

      if (liveSource == null) {
        throw Exception('未找到直播源: $sourceKey');
      }

      // 从缓存中获取对应的频道列表
      final m3uContent = _channelsCache[sourceKey]?.data;
      if (m3uContent == null) {
        throw Exception('未找到频道列表: $sourceKey');
      }

      // 确定 EPG URL：优先使用 LiveSource 的 epg，其次使用 m3uContent 的 tvgUrl
      final epgUrl =
          liveSource.epg.isNotEmpty ? liveSource.epg : m3uContent.tvgUrl;

      if (epgUrl.isEmpty) {
        print('EPG URL 为空: $sourceKey');
        return;
      }

      // 确定使用的 User-Agent
      final userAgent =
          liveSource.ua.isEmpty ? 'AptvPlayer/1.4.10' : liveSource.ua;

      // 获取所有需要查询的 tvgId
      final tvgIds = m3uContent.channels
          .where((channel) => channel.tvgId.isNotEmpty)
          .map((channel) => channel.tvgId)
          .toSet()
          .toList();

      if (tvgIds.isEmpty) {
        print('没有需要获取 EPG 的频道: $sourceKey');
        return;
      }

      // 解析 EPG
      final epgMap = await _parseEpg(epgUrl, userAgent, tvgIds);

      // 转换为 EpgData 并缓存
      final epgDataMap = <String, EpgData>{};
      for (final entry in epgMap.entries) {
        final tvgId = entry.key;
        final programs = entry.value
            .map((p) => EpgProgram(
                  channelId: tvgId,
                  title: p['title'] ?? '',
                  startTime: _parseEpgDateTime(p['start'] ?? ''),
                  endTime: _parseEpgDateTime(p['end'] ?? ''),
                ))
            .toList();

        epgDataMap[tvgId] = EpgData(
          tvgId: tvgId,
          source: sourceKey,
          epgUrl: epgUrl,
          programs: programs,
        );
      }

      // 更新缓存
      _epgCache[sourceKey] = _CacheItem(epgDataMap, DateTime.now());
    } catch (e) {
      print('获取 EPG 节目单失败: $e');
    }
  }

  /// 解析 EPG XML 数据（使用流式解析）
  static Future<Map<String, List<Map<String, String>>>> _parseEpg(
      String epgUrl, String userAgent, List<String> tvgIds) async {
    if (epgUrl.isEmpty) {
      return {};
    }

    final tvgSet = tvgIds.toSet();
    final result = <String, List<Map<String, String>>>{};

    try {
      final request = http.Request('GET', Uri.parse(epgUrl));
      request.headers['User-Agent'] = userAgent;

      final response = await request.send();
      if (response.statusCode != 200) {
        return {};
      }

      // 使用 XML 事件流解析，避免加载整个文件到内存
      String currentTvgId = '';
      String currentStart = '';
      String currentEnd = '';
      String currentTitle = '';
      bool inProgramme = false;
      bool inTitle = false;
      bool shouldSkipCurrentProgram = false;

      await for (final events
          in response.stream.transform(utf8.decoder).toXmlEvents()) {
        for (final event in events) {
          if (event is XmlStartElementEvent) {
            if (event.name == 'programme') {
              inProgramme = true;
              // 提取属性
              currentTvgId = event.attributes
                  .firstWhere((attr) => attr.name == 'channel',
                      orElse: () => XmlEventAttribute(
                          '', '', XmlAttributeType.DOUBLE_QUOTE))
                  .value;
              currentStart = event.attributes
                  .firstWhere((attr) => attr.name == 'start',
                      orElse: () => XmlEventAttribute(
                          '', '', XmlAttributeType.DOUBLE_QUOTE))
                  .value;
              currentEnd = event.attributes
                  .firstWhere((attr) => attr.name == 'stop',
                      orElse: () => XmlEventAttribute(
                          '', '', XmlAttributeType.DOUBLE_QUOTE))
                  .value;
              currentTitle = '';

              // 如果当前频道不在关注列表中，标记为跳过
              shouldSkipCurrentProgram = !tvgSet.contains(currentTvgId);
            } else if (event.name == 'title' &&
                inProgramme &&
                !shouldSkipCurrentProgram) {
              inTitle = true;
            }
          } else if (event is XmlTextEvent) {
            if (inTitle && !shouldSkipCurrentProgram) {
              currentTitle += event.value;
            }
          } else if (event is XmlEndElementEvent) {
            if (event.name == 'title') {
              inTitle = false;
            } else if (event.name == 'programme') {
              // 保存节目信息
              if (!shouldSkipCurrentProgram &&
                  currentTvgId.isNotEmpty &&
                  currentStart.isNotEmpty &&
                  currentEnd.isNotEmpty &&
                  currentTitle.isNotEmpty) {
                if (!result.containsKey(currentTvgId)) {
                  result[currentTvgId] = [];
                }
                result[currentTvgId]!.add({
                  'start': currentStart,
                  'end': currentEnd,
                  'title': currentTitle.trim(),
                });
              }

              // 重置状态
              inProgramme = false;
              currentTvgId = '';
              currentStart = '';
              currentEnd = '';
              currentTitle = '';
              shouldSkipCurrentProgram = false;
            }
          }
        }
      }
    } catch (e) {
      print('解析 EPG 失败: $e');
    }

    return result;
  }

  /// 解析 EPG 时间格式 "20251021235000 +0900"
  static DateTime _parseEpgDateTime(String dateTimeStr) {
    if (dateTimeStr.isEmpty) return DateTime.now();

    try {
      // 格式: "20251021235000 +0900"
      final parts = dateTimeStr.split(' ');
      if (parts.isEmpty) return DateTime.now();

      final dateTimePart = parts[0];
      // 解析: YYYYMMDDHHMMSS
      if (dateTimePart.length < 14) return DateTime.now();

      final year = int.parse(dateTimePart.substring(0, 4));
      final month = int.parse(dateTimePart.substring(4, 6));
      final day = int.parse(dateTimePart.substring(6, 8));
      final hour = int.parse(dateTimePart.substring(8, 10));
      final minute = int.parse(dateTimePart.substring(10, 12));
      final second = int.parse(dateTimePart.substring(12, 14));

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// 清除所有缓存
  static void clearAllCache() {
    _liveSourcesCache = null;
    _channelsCache.clear();
    _epgCache.clear();
  }

  /// 清除直播源缓存
  static void clearSourcesCache() {
    _liveSourcesCache = null;
  }

  /// 清除指定源的频道缓存
  static void clearChannelsCache(String sourceKey) {
    _channelsCache.remove(sourceKey);
  }

  /// 清除指定的 EPG 缓存
  static void clearEpgCache(String sourceKey) {
    _epgCache.remove(sourceKey);
  }

  /// 一键清除所有频道和 EPG 缓存（保留直播源缓存）
  static void clearAllChannelsAndEpgCache() {
    _channelsCache.clear();
    _epgCache.clear();
  }
}
