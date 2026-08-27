import 'video_info.dart';

/// 搜索结果数据模型
class SearchResult {
  final String id;
  final String title;
  final String poster;
  final List<String> episodes;
  final List<String> episodesTitles;
  final String source;
  final String sourceName;
  final String? class_;
  final String year;
  final String? desc;
  final String? typeName;
  final int? doubanId;

  SearchResult({
    required this.id,
    required this.title,
    required this.poster,
    required this.episodes,
    required this.episodesTitles,
    required this.source,
    required this.sourceName,
    this.class_,
    required this.year,
    this.desc,
    this.typeName,
    this.doubanId,
  });

  /// 从JSON创建SearchResult
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      poster: json['poster'] ?? '',
      episodes: json['episodes'] != null 
          ? List<String>.from(json['episodes'])
          : [],
      episodesTitles: json['episodes_titles'] != null 
          ? List<String>.from(json['episodes_titles'])
          : [],
      source: json['source'] ?? '',
      sourceName: json['source_name'] ?? '',
      class_: json['class'],
      year: json['year'] ?? '',
      desc: json['desc'],
      typeName: json['type_name'],
      doubanId: json['douban_id'],
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'poster': poster,
      'episodes': episodes,
      'episodes_titles': episodesTitles,
      'source': source,
      'source_name': sourceName,
      'class': class_,
      'year': year,
      'desc': desc,
      'type_name': typeName,
      'douban_id': doubanId,
    };
  }

  /// 获取显示用的类型名称
  String get displayType {
    return typeName ?? class_ ?? '未知';
  }

  /// 获取集数信息
  String get episodeInfo {
    if (episodes.isEmpty) return '';
    return '共${episodes.length}集';
  }

  /// 获取年份信息
  String get yearInfo {
    return year.isNotEmpty ? year : '未知年份';
  }

  /// 转换为VideoInfo
  VideoInfo toVideoInfo() {
    return VideoInfo(
      id: id,
      source: source,
      title: title,
      sourceName: sourceName,
      year: year,
      cover: poster,
      index: 1, // 搜索结果默认从第1集开始
      totalEpisodes: episodes.length,
      playTime: 0, // 搜索结果默认未播放
      totalTime: 0, // 搜索结果默认未知总时长
      saveTime: DateTime.now().millisecondsSinceEpoch ~/ 1000, // 当前时间戳
      searchTitle: title, // 使用标题作为搜索标题
      doubanId: doubanId?.toString(), // 传递豆瓣ID，转换为字符串
    );
  }
}

/// WebSocket 搜索事件类型
enum SearchEventType {
  start,
  sourceResult,
  sourceError,
  complete,
}

/// WebSocket 搜索事件基类
abstract class SearchEvent {
  final SearchEventType type;
  final int timestamp;

  SearchEvent({
    required this.type,
    required this.timestamp,
  });

  factory SearchEvent.fromJson(Map<String, dynamic> json) {
    final typeString = json['type'] as String?;
    
    switch (typeString) {
      case 'start':
        return SearchStartEvent.fromJson(json);
      case 'source_result':
        return SearchSourceResultEvent.fromJson(json);
      case 'source_error':
        return SearchSourceErrorEvent.fromJson(json);
      case 'complete':
        return SearchCompleteEvent.fromJson(json);
      default:
        throw Exception('未知的搜索事件类型: $typeString');
    }
  }
}

/// 搜索开始事件
class SearchStartEvent extends SearchEvent {
  final String query;
  final int totalSources;

  SearchStartEvent({
    required this.query,
    required this.totalSources,
    required super.timestamp,
  }) : super(
          type: SearchEventType.start,
        );

  factory SearchStartEvent.fromJson(Map<String, dynamic> json) {
    return SearchStartEvent(
      query: json['query'] ?? '',
      totalSources: json['totalSources'] ?? 0,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 搜索结果事件
class SearchSourceResultEvent extends SearchEvent {
  final String source;
  final String sourceName;
  final List<SearchResult> results;

  SearchSourceResultEvent({
    required this.source,
    required this.sourceName,
    required this.results,
    required super.timestamp,
  }) : super(
          type: SearchEventType.sourceResult,
        );

  factory SearchSourceResultEvent.fromJson(Map<String, dynamic> json) {
    final resultsData = json['results'] as List<dynamic>? ?? [];
    final results = resultsData
        .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
        .toList();

    return SearchSourceResultEvent(
      source: json['source'] ?? '',
      sourceName: json['sourceName'] ?? '',
      results: results,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 搜索错误事件
class SearchSourceErrorEvent extends SearchEvent {
  final String source;
  final String sourceName;
  final String error;

  SearchSourceErrorEvent({
    required this.source,
    required this.sourceName,
    required this.error,
    required super.timestamp,
  }) : super(
          type: SearchEventType.sourceError,
        );

  factory SearchSourceErrorEvent.fromJson(Map<String, dynamic> json) {
    return SearchSourceErrorEvent(
      source: json['source'] ?? '',
      sourceName: json['sourceName'] ?? '',
      error: json['error'] ?? '未知错误',
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 搜索完成事件
class SearchCompleteEvent extends SearchEvent {
  final int totalResults;
  final int completedSources;

  SearchCompleteEvent({
    required this.totalResults,
    required this.completedSources,
    required super.timestamp,
  }) : super(
          type: SearchEventType.complete,
        );

  factory SearchCompleteEvent.fromJson(Map<String, dynamic> json) {
    return SearchCompleteEvent(
      totalResults: json['totalResults'] ?? 0,
      completedSources: json['completedSources'] ?? 0,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
