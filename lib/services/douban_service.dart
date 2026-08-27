import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../models/douban_movie.dart';
import 'api_service.dart';
import 'douban_cache_service.dart';
import 'user_data_service.dart';

/// 豆瓣推荐数据请求参数
class DoubanRecommendsParams {
  final String kind;
  final String category;
  final String format;
  final String region;
  final String year;
  final String platform;
  final String sort;
  final String label;
  final int pageLimit;
  final int page;

  const DoubanRecommendsParams({
    required this.kind,
    this.category = 'all',
    this.format = 'all',
    this.region = 'all',
    this.year = 'all',
    this.platform = 'all',
    this.sort = 'T',
    this.label = 'all',
    this.pageLimit = 20,
    this.page = 0,
  });
}

/// 豆瓣数据请求参数（保持向后兼容）
class DoubanRequestParams {
  final String kind;
  final String category;
  final String type;
  final int pageLimit;
  final int page;

  const DoubanRequestParams({
    required this.kind,
    required this.category,
    required this.type,
    this.pageLimit = 25,
    this.page = 0,
  });

  /// 构建查询参数
  Map<String, String> toQueryParams() {
    return {
      'kind': kind,
      'category': category,
      'type': type,
      'pageLimit': pageLimit.toString(),
      'page': page.toString(),
    };
  }
}

/// 豆瓣数据请求服务
class DoubanService {
  static final DoubanCacheService _cacheService = DoubanCacheService();
  static bool _cacheInitialized = false;
  static String? _uniqueOrigin;
  
  /// 生成唯一的 Origin 以避免统一限流
  static String _getUniqueOrigin() {
    if (_uniqueOrigin == null) {
      final random = Random();
      final domains = [
        'movie.douban.com',
        'm.douban.com',
        'www.douban.com',
      ];
      final subdomains = [
        'app',
        'mobile',
        'client',
        'api',
        'web',
      ];
      
      // 随机选择域名和子域名组合
      final baseDomain = domains[random.nextInt(domains.length)];
      final subdomain = subdomains[random.nextInt(subdomains.length)];
      final randomId = random.nextInt(9999).toString().padLeft(4, '0');
      
      _uniqueOrigin = 'https://$subdomain$randomId.$baseDomain';
    }
    return _uniqueOrigin!;
  }

  /// 解析豆瓣HTML详情页面
  static DoubanMovieDetails _parseDoubanHtmlDetails(String html, String id) {
    try {
      // 提取基本信息 - 标题
      final titleRegex = RegExp(r'<h1[^>]*>[\s\S]*?<span[^>]*property="v:itemreviewed"[^>]*>([^<]+)</span>');
      final titleMatch = titleRegex.firstMatch(html);
      final title = titleMatch?.group(1)?.trim() ?? '';

      // 提取海报
      final posterRegex = RegExp(r'<a[^>]*class="nbgnbg"[^>]*>[\s\S]*?<img[^>]*src="([^"]+)"');
      final posterMatch = posterRegex.firstMatch(html);
      final poster = posterMatch?.group(1) ?? '';

      // 提取评分
      final ratingRegex = RegExp(r'<strong[^>]*class="ll rating_num"[^>]*property="v:average">([^<]+)</strong>');
      final ratingMatch = ratingRegex.firstMatch(html);
      final rate = ratingMatch?.group(1);

      // 提取年份
      final yearRegex = RegExp(r'<span[^>]*class="year">[(]([^)]+)[)]</span>');
      final yearMatch = yearRegex.firstMatch(html);
      final year = yearMatch?.group(1) ?? '';

      // 提取导演
      List<String> directors = [];
      final directorRegex = RegExp(r'<span class=["\x27]pl["\x27]>导演</span>:\s*<span class=["\x27]attrs["\x27]>(.*?)</span>');
      final directorMatch = directorRegex.firstMatch(html);
      if (directorMatch != null) {
        final directorLinks = RegExp(r'<a[^>]*>([^<]+)</a>').allMatches(directorMatch.group(1)!);
        directors = directorLinks.map((match) => match.group(1)?.trim() ?? '').where((name) => name.isNotEmpty).toList();
      }

      // 提取编剧
      List<String> screenwriters = [];
      final writerRegex = RegExp(r'<span class=["\x27]pl["\x27]>编剧</span>:\s*<span class=["\x27]attrs["\x27]>(.*?)</span>');
      final writerMatch = writerRegex.firstMatch(html);
      if (writerMatch != null) {
        final writerLinks = RegExp(r'<a[^>]*>([^<]+)</a>').allMatches(writerMatch.group(1)!);
        screenwriters = writerLinks.map((match) => match.group(1)?.trim() ?? '').where((name) => name.isNotEmpty).toList();
      }

      // 提取主演
      List<String> actors = [];
      final castRegex = RegExp(r'<span class=["\x27]pl["\x27]>主演</span>:\s*<span class=["\x27]attrs["\x27]>(.*?)</span>');
      final castMatch = castRegex.firstMatch(html);
      if (castMatch != null) {
        final castLinks = RegExp(r'<a[^>]*>([^<]+)</a>').allMatches(castMatch.group(1)!);
        actors = castLinks.map((match) => match.group(1)?.trim() ?? '').where((name) => name.isNotEmpty).toList();
      }

      // 提取类型
      final genreRegex = RegExp(r'<span[^>]*property="v:genre">([^<]+)</span>');
      final genreMatches = genreRegex.allMatches(html);
      final genres = genreMatches.map((match) => match.group(1) ?? '').where((genre) => genre.isNotEmpty).toList();

      // 提取制片国家/地区
      final countryRegex = RegExp(r'<span[^>]*class="pl">制片国家/地区:</span>([^<]+)');
      final countryMatch = countryRegex.firstMatch(html);
      final countries = countryMatch?.group(1)?.trim().split('/').map((c) => c.trim()).where((c) => c.isNotEmpty).toList() ?? <String>[];

      // 提取语言
      final languageRegex = RegExp(r'<span[^>]*class="pl">语言:</span>([^<]+)');
      final languageMatch = languageRegex.firstMatch(html);
      final languages = languageMatch?.group(1)?.trim().split('/').map((l) => l.trim()).where((l) => l.isNotEmpty).toList() ?? <String>[];

      // 提取首播/上映日期
      String? releaseDate;
      final firstAiredRegex = RegExp(r'<span class="pl">首播:</span>\s*<span[^>]*property="v:initialReleaseDate"[^>]*content="([^"]*)"[^>]*>([^<]*)</span>');
      final firstAiredMatch = firstAiredRegex.firstMatch(html);
      if (firstAiredMatch != null) {
        releaseDate = firstAiredMatch.group(1);
      } else {
        final releaseDateRegex = RegExp(r'<span class="pl">上映日期:</span>\s*<span[^>]*property="v:initialReleaseDate"[^>]*content="([^"]*)"[^>]*>([^<]*)</span>');
        final releaseDateMatch = releaseDateRegex.firstMatch(html);
        if (releaseDateMatch != null) {
          releaseDate = releaseDateMatch.group(1);
        }
      }

      // 提取集数（仅剧集有）
      int? episodes;
      final episodesRegex = RegExp(r'<span[^>]*class="pl">集数:</span>([^<]+)');
      final episodesMatch = episodesRegex.firstMatch(html);
      if (episodesMatch != null) {
        episodes = int.tryParse(episodesMatch.group(1)?.trim() ?? '');
      }

      // 提取时长 - 支持电影和剧集
      int? episodeLength;
      int? movieDuration;
      
      // 先尝试提取剧集的单集片长
      final singleEpisodeDurationRegex = RegExp(r'<span[^>]*class="pl">单集片长:</span>([^<]+)');
      final singleEpisodeDurationMatch = singleEpisodeDurationRegex.firstMatch(html);
      if (singleEpisodeDurationMatch != null) {
        episodeLength = int.tryParse(singleEpisodeDurationMatch.group(1)?.trim() ?? '');
      } else {
        // 如果没有单集片长，尝试提取电影的总片长
        final movieDurationRegex = RegExp(r'<span[^>]*class="pl">片长:</span>([^<]+)');
        final movieDurationMatch = movieDurationRegex.firstMatch(html);
        if (movieDurationMatch != null) {
          movieDuration = int.tryParse(movieDurationMatch.group(1)?.trim() ?? '');
        }
      }
      
      // 为了保持与现有代码的兼容性，将时长转换为字符串
      String? duration;
      if (episodeLength != null) {
        duration = '$episodeLength分钟';
      } else if (movieDuration != null) {
        duration = '$movieDuration分钟';
      }

      // 提取剧情简介 - 两个正则都匹配，选择内容更长的
      String? summary;
      
      // 使用多行模式和非贪婪匹配来正确处理包含HTML标签的内容
      final summaryRegex1 = RegExp(r'<span[^>]*class="all hidden">(.*?)</span>', multiLine: true, dotAll: true);
      final summaryMatch1 = summaryRegex1.firstMatch(html);
      String? summary1;
      if (summaryMatch1 != null) {
        summary1 = summaryMatch1.group(1)
            ?.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '|||LINEBREAK|||') // 先用特殊标记替换<br>
            .replaceAll(RegExp(r'<[^>]*>'), '') // 移除所有HTML标签
            .replaceAll(RegExp(r'\s+'), ' ') // 去除重复空格，将所有空白字符（包括HTML中的\n）合并为单个空格
            .replaceAll('|||LINEBREAK|||', '\n') // 将特殊标记恢复为换行符
            .trim()
            .split('\n') // 按换行符分割
            .join('\n'); // 重新组合
      }
      
      final summaryRegex2 = RegExp(r'<span[^>]*property="v:summary"[^>]*>(.*?)</span>', multiLine: true, dotAll: true);
      final summaryMatch2 = summaryRegex2.firstMatch(html);
      String? summary2;
      if (summaryMatch2 != null) {
        summary2 = summaryMatch2.group(1)
            ?.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '|||LINEBREAK|||') // 先用特殊标记替换<br>
            .replaceAll(RegExp(r'<[^>]*>'), '') // 移除所有HTML标签
            .replaceAll(RegExp(r'\s+'), ' ') // 去除重复空格，将所有空白字符（包括HTML中的\n）合并为单个空格
            .replaceAll('|||LINEBREAK|||', '\n') // 将特殊标记恢复为换行符
            .trim()
            .split('\n') // 按换行符分割
            .join('\n'); // 重新组合
      }
      
      // 选择内容更长的简介
      if (summary1 != null && summary2 != null) {
        summary = summary1.length >= summary2.length ? summary1 : summary2;
      } else if (summary1 != null) {
        summary = summary1;
      } else if (summary2 != null) {
        summary = summary2;
      }

      // 提取推荐区域
      List<DoubanRecommendItem> recommends = [];
      try {
        // 查找推荐区域
        final recommendationsRegex = RegExp(r'<div[^>]*id="recommendations"[^>]*>(.*?)</div>', multiLine: true, dotAll: true);
        final recommendationsMatch = recommendationsRegex.firstMatch(html);
        
        if (recommendationsMatch != null) {
          final recommendationsContent = recommendationsMatch.group(1) ?? '';
          
          // 提取所有推荐项目
          final dlRegex = RegExp(r'<dl>(.*?)</dl>', multiLine: true, dotAll: true);
          final dlMatches = dlRegex.allMatches(recommendationsContent);
          
          for (final dlMatch in dlMatches) {
            final dlContent = dlMatch.group(1) ?? '';
            
            // 提取链接和海报
            final linkRegex = RegExp(r'<a[^>]*href="https://movie\.douban\.com/subject/(\d+)/[^"]*"[^>]*>');
            final linkMatch = linkRegex.firstMatch(dlContent);
            
            // 提取海报图片
            final imgRegex = RegExp(r'<img[^>]*src="([^"]+)"[^>]*alt="([^"]*)"');
            final imgMatch = imgRegex.firstMatch(dlContent);
            
            // 提取评分
            final rateRegex = RegExp(r'<span[^>]*class="subject-rate"[^>]*>([^<]*)</span>');
            final rateMatch = rateRegex.firstMatch(dlContent);
            
            if (linkMatch != null && imgMatch != null) {
              final recommendId = linkMatch.group(1) ?? '';
              final posterUrl = imgMatch.group(1) ?? '';
              final title = imgMatch.group(2) ?? '';
              final recommendRate = rateMatch?.group(1)?.trim();
              
              // 过滤掉空的评分
              final rate = recommendRate?.isNotEmpty == true ? recommendRate : null;
              
              if (recommendId.isNotEmpty && title.isNotEmpty && posterUrl.isNotEmpty) {
                recommends.add(DoubanRecommendItem(
                  id: recommendId,
                  title: title,
                  poster: posterUrl,
                  rate: rate,
                ));
              }
            }
          }
        }
      } catch (e) {
        // 推荐区域解析失败，继续执行
        print('解析推荐区域失败: $e');
      }

      return DoubanMovieDetails(
        id: id,
        title: title,
        poster: poster,
        rate: rate,
        year: year,
        summary: summary,
        genres: genres,
        directors: directors,
        screenwriters: screenwriters,
        actors: actors,
        duration: duration,
        countries: countries,
        languages: languages,
        releaseDate: releaseDate,
        originalTitle: null, // HTML页面中暂未找到原始标题的提取逻辑
        imdbId: null, // HTML页面中暂未找到IMDB ID的提取逻辑
        recommends: recommends,
        totalEpisodes: episodes,
      );
    } catch (e) {
      // 如果解析失败，返回基本信息
      return DoubanMovieDetails(
        id: id,
        title: '解析失败',
        poster: '',
        year: '',
      );
    }
  }
  /// 初始化缓存服务
  static Future<void> _initCache() async {
    if (!_cacheInitialized) {
      await _cacheService.init();
      _cacheInitialized = true;
    }
  }
  /// 获取豆瓣分类数据
  /// 
  /// 参数说明：
  /// - kind: 类型 (movie, tv)
  /// - category: 分类 (热门, tv, show 等)
  /// - type: 子类型 (全部, tv, show 等)
  /// - pageLimit: 每页数量，默认20
  /// - page: 起始页码，默认0
  static Future<ApiResponse<List<DoubanMovie>>> getCategoryData(
    BuildContext context, {
    required String kind,
    required String category,
    required String type,
    int pageLimit = 25,
    int page = 0,
  }) async {
    // 初始化缓存服务
    await _initCache();

    // 生成缓存键
    final cacheKey = _cacheService.generateDoubanCategoryCacheKey(
      kind: kind,
      category: category,
      type: type,
      pageLimit: pageLimit,
      page: page,
    );

    // 尝试从缓存获取数据（存取均为已处理后的 DoubanMovie 列表）
    try {
      final cachedData = await _cacheService.get<List<DoubanMovie>>(
        cacheKey,
        (raw) => (raw as List<dynamic>)
            .map((m) {
              final map = m as Map<String, dynamic>;
              return DoubanMovie(
                id: map['id']?.toString() ?? '',
                title: map['title']?.toString() ?? '',
                poster: map['poster']?.toString() ?? '',
                rate: map['rate']?.toString(),
                year: map['year']?.toString() ?? '',
              );
            })
            .toList(),
      );

      if (cachedData != null) {
        return ApiResponse.success(cachedData);
      }
    } catch (e) {
      // 缓存读取失败，继续执行网络请求
      print('读取缓存失败: $e');
    }
    // 获取用户存储的豆瓣数据源选项
    final dataSourceKey = await UserDataService.getDoubanDataSourceKey();
    
    // 根据数据源选项构建不同的基础URL
    String apiUrl;
    switch (dataSourceKey) {
      case 'cdn_tencent':
        apiUrl = 'https://m.douban.cmliussss.net/rexxar/api/v2/subject/recent_hot/$kind?start=${page * pageLimit}&limit=$pageLimit&category=$category&type=$type';
        break;
      case 'cdn_aliyun':
        apiUrl = 'https://m.douban.cmliussss.com/rexxar/api/v2/subject/recent_hot/$kind?start=${page * pageLimit}&limit=$pageLimit&category=$category&type=$type';
        break;
      case 'direct':
      default:
        apiUrl = 'https://m.douban.com/rexxar/api/v2/subject/recent_hot/$kind?start=${page * pageLimit}&limit=$pageLimit&category=$category&type=$type';
        break;
    }
    if (dataSourceKey == 'cors_proxy') {
      apiUrl = 'https://ciao-cors.is-an.org/${Uri.encodeComponent(apiUrl)}';
    }
    
    try {
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Referer': 'https://movie.douban.com/',
        'Accept': 'application/json, text/plain, */*',
      };
      
      // 如果使用 cors_proxy，添加 Origin 头
      if (dataSourceKey == 'cors_proxy') {
        headers['Origin'] = _getUniqueOrigin();
      }
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        try {
          final Map<String, dynamic> data = json.decode(response.body);
          final doubanResponse = DoubanResponse.fromJson(data);
          
          // 缓存成功的结果（保存已处理后的 DoubanMovie 列表），缓存时间为1天
          try {
            await _cacheService.set(
              cacheKey,
              doubanResponse.items.map((e) => e.toJson()).toList(),
              const Duration(hours: 6),
            );
          } catch (cacheError) {
            print('缓存数据失败: $cacheError');
          }
          
          return ApiResponse.success(doubanResponse.items, statusCode: response.statusCode);
        } catch (parseError) {
          return ApiResponse.error('豆瓣数据解析失败: ${parseError.toString()}');
        }
      } else {
        return ApiResponse.error(
          '获取豆瓣数据失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.error('豆瓣数据请求异常: ${e.toString()}');
    }
  }

  /// 获取热门电影数据
  static Future<ApiResponse<List<DoubanMovie>>> getHotMovies(
    BuildContext context, {
    int pageLimit = 25,
    int page = 0,
  }) async {
    return getCategoryData(
      context,
      kind: 'movie',
      category: '热门',
      type: '全部',
      pageLimit: pageLimit,
      page: page,
    );
  }

  /// 获取热门剧集数据
  static Future<ApiResponse<List<DoubanMovie>>> getHotTvShows(
    BuildContext context, {
    int pageLimit = 25,
    int page = 0,
  }) async {
    return getCategoryData(
      context,
      kind: 'tv',
      category: '最近热门',
      type: 'tv',
      pageLimit: pageLimit,
      page: page,
    );
  }

  /// 获取热门综艺数据
  static Future<ApiResponse<List<DoubanMovie>>> getHotShows(
    BuildContext context, {
    int pageLimit = 25,
    int page = 0,
  }) async {
    return getCategoryData(
      context,
      kind: 'tv',
      category: 'show',
      type: 'show',
      pageLimit: pageLimit,
      page: page,
    );
  }

  /// 获取豆瓣推荐数据（新版筛选逻辑）
  static Future<ApiResponse<List<DoubanMovie>>> fetchDoubanRecommends(
    BuildContext context,
    DoubanRecommendsParams params, {
    String proxyUrl = '',
    bool useTencentCDN = false,
    bool useAliCDN = false,
  }) async {
    // 初始化缓存服务
    await _initCache();

    // 生成缓存键
    final cacheKey = _cacheService.generateDoubanRecommendsCacheKey(
      kind: params.kind,
      category: params.category,
      format: params.format,
      region: params.region,
      year: params.year,
      platform: params.platform,
      sort: params.sort,
      label: params.label,
      pageLimit: params.pageLimit,
      page: params.page,
    );

    // 尝试从缓存获取数据（存取均为已处理后的 DoubanMovie 列表）
    try {
      final cachedData = await _cacheService.get<List<DoubanMovie>>(
        cacheKey,
        (raw) => (raw as List<dynamic>)
            .map((m) {
              final map = m as Map<String, dynamic>;
              return DoubanMovie(
                id: map['id']?.toString() ?? '',
                title: map['title']?.toString() ?? '',
                poster: map['poster']?.toString() ?? '',
                rate: map['rate']?.toString(),
                year: map['year']?.toString() ?? '',
              );
            })
            .toList(),
      );

      if (cachedData != null) {
        return ApiResponse.success(cachedData);
      }
    } catch (e) {
      // 缓存读取失败，继续执行网络请求
      print('读取缓存失败: $e');
    }
    // 处理筛选参数，将 'all' 转换为空字符串
    String category = params.category == 'all' ? '' : params.category;
    String format = params.format == 'all' ? '' : params.format;
    String region = params.region == 'all' ? '' : params.region;
    String year = params.year == 'all' ? '' : params.year;
    String platform = params.platform == 'all' ? '' : params.platform;
    String label = params.label == 'all' ? '' : params.label;
    String sort = params.sort == 'T' ? '' : params.sort;

    // 构建 selected_categories
    Map<String, dynamic> selectedCategories = {'类型': category};
    if (format.isNotEmpty) {
      selectedCategories['形式'] = format;
    }
    if (region.isNotEmpty) {
      selectedCategories['地区'] = region;
    }

    // 构建 tags 数组
    List<String> tags = [];
    if (category.isNotEmpty) {
      tags.add(category);
    }
    if (category.isEmpty && format.isNotEmpty) {
      tags.add(format);
    }
    if (label.isNotEmpty) {
      tags.add(label);
    }
    if (region.isNotEmpty) {
      tags.add(region);
    }
    if (year.isNotEmpty) {
      tags.add(year);
    }
    if (platform.isNotEmpty) {
      tags.add(platform);
    }

    // 获取用户存储的豆瓣数据源选项
    final dataSourceKey = await UserDataService.getDoubanDataSourceKey();
    
    // 根据数据源选项构建不同的基础URL
    String baseUrl;
    switch (dataSourceKey) {
      case 'cdn_tencent':
        baseUrl = 'https://m.douban.cmliussss.net/rexxar/api/v2/${params.kind}/recommend';
        break;
      case 'cdn_aliyun':
        baseUrl = 'https://m.douban.cmliussss.com/rexxar/api/v2/${params.kind}/recommend';
        break;
      case 'direct':
      default:
        baseUrl = 'https://m.douban.com/rexxar/api/v2/${params.kind}/recommend';
        break;
    }
    
    // 构建查询参数
    final queryParams = <String, String>{
      'refresh': '0',
      'start': (params.page * params.pageLimit).toString(),
      'count': params.pageLimit.toString(),
      'selected_categories': json.encode(selectedCategories),
      'uncollect': 'false',
      'score_range': '0,10',
      'tags': tags.join(','),
    };
    
    if (sort.isNotEmpty) {
      queryParams['sort'] = sort;
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
    String target = uri.toString();
    if (dataSourceKey == 'cors_proxy') {
      target = 'https://ciao-cors.is-an.org/${Uri.encodeComponent(target)}';
    }

    try {
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Referer': 'https://movie.douban.com/',
        'Accept': 'application/json, text/plain, */*',
      };
      
      // 如果使用 cors_proxy，添加 Origin 头
      if (dataSourceKey == 'cors_proxy') {
        headers['Origin'] = _getUniqueOrigin();
      }
      
      final response = await http.get(
        Uri.parse(target),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        try {
          final Map<String, dynamic> data = json.decode(response.body);
          
          // 过滤并转换数据
          final itemsData = data['items'] as List<dynamic>? ?? [];
          final filteredItems = itemsData
              .where((item) => item['type'] == 'movie' || item['type'] == 'tv')
              .map((item) => DoubanMovie.fromJson(item as Map<String, dynamic>))
              .toList();

          // 缓存成功的结果（保存已处理后的 DoubanMovie 列表），缓存时间为1天
          try {
            await _cacheService.set(
              cacheKey,
              filteredItems.map((e) => e.toJson()).toList(),
              const Duration(hours: 6),
            );
          } catch (cacheError) {
            print('缓存数据失败: $cacheError');
          }

          return ApiResponse.success(filteredItems, statusCode: response.statusCode);
        } catch (parseError) {
          return ApiResponse.error('豆瓣推荐数据解析失败: ${parseError.toString()}');
        }
      } else {
        return ApiResponse.error(
          '获取豆瓣推荐数据失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.error('豆瓣推荐数据请求异常: ${e.toString()}');
    }
  }

  /// 获取豆瓣详情数据
  /// 
  /// 参数说明：
  /// - doubanId: 豆瓣ID
  static Future<ApiResponse<DoubanMovieDetails>> getDoubanDetails(
    BuildContext context, {
    required String doubanId,
  }) async {
    // 初始化缓存服务
    await _initCache();

    // 生成缓存键
    final cacheKey = _cacheService.generateDoubanDetailsCacheKey(
      doubanId: doubanId,
    );

    // 尝试从缓存获取数据
    try {
      final cachedData = await _cacheService.get<DoubanMovieDetails>(
        cacheKey,
        (raw) {
          final map = raw as Map<String, dynamic>;
          
          // 处理推荐列表
          List<DoubanRecommendItem> recommends = [];
          if (map['recommends'] != null) {
            final recommendsData = map['recommends'] as List<dynamic>? ?? [];
            recommends = recommendsData.map((r) => DoubanRecommendItem.fromJson(r as Map<String, dynamic>)).toList();
          }
          
          return DoubanMovieDetails(
            id: map['id']?.toString() ?? '',
            title: map['title']?.toString() ?? '',
            poster: map['poster']?.toString() ?? '',
            rate: map['rate']?.toString(),
            year: map['year']?.toString() ?? '',
            summary: map['summary']?.toString(),
            genres: (map['genres'] as List<dynamic>? ?? [])
                .map((g) => g.toString())
                .toList(),
            directors: (map['directors'] as List<dynamic>? ?? [])
                .map((d) => d.toString())
                .toList(),
            screenwriters: (map['screenwriters'] as List<dynamic>? ?? [])
                .map((s) => s.toString())
                .toList(),
            actors: (map['actors'] as List<dynamic>? ?? [])
                .map((a) => a.toString())
                .toList(),
            duration: map['duration']?.toString(),
            countries: (map['countries'] as List<dynamic>? ?? [])
                .map((c) => c.toString())
                .toList(),
            languages: (map['languages'] as List<dynamic>? ?? [])
                .map((l) => l.toString())
                .toList(),
            releaseDate: map['releaseDate']?.toString(),
            originalTitle: map['originalTitle']?.toString(),
            imdbId: map['imdbId']?.toString(),
            totalEpisodes: map['totalEpisodes'] is int
                ? map['totalEpisodes'] as int
                : int.tryParse(map['totalEpisodes']?.toString() ?? ''),
            recommends: recommends,
          );
        },
      );

      if (cachedData != null && cachedData.title.trim().isNotEmpty) {
        return ApiResponse.success(cachedData);
      } else if (cachedData != null) {
        await _cacheService.delete(cacheKey);
      }
    } catch (e) {
      // 缓存读取失败，继续执行网络请求
      print('读取豆瓣详情缓存失败: $e');
    }

    // 获取用户存储的豆瓣数据源选项
    final dataSourceKey = await UserDataService.getDoubanDataSourceKey();
    
    // 根据数据源选项构建不同的详情 API URL。HTML 页面会被豆瓣反爬跳到
    // sec.douban.com 校验页；rexxar JSON 接口和推荐列表同源，能稳定取详情。
    String apiUrl;
    switch (dataSourceKey) {
      case 'cdn_tencent':
        apiUrl = 'https://m.douban.cmliussss.net/rexxar/api/v2/subject/$doubanId';
        break;
      case 'cdn_aliyun':
        apiUrl = 'https://m.douban.cmliussss.com/rexxar/api/v2/subject/$doubanId';
        break;
      case 'direct':
      default:
        apiUrl = 'https://m.douban.com/rexxar/api/v2/subject/$doubanId';
        break;
    }
    
    if (dataSourceKey == 'cors_proxy') {
      apiUrl = 'https://ciao-cors.is-an.org/${Uri.encodeComponent(apiUrl)}';
    }
    
    try {
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Referer': 'https://movie.douban.com/',
        'Accept': 'application/json, text/plain, */*',
      };
      
      // 如果使用 cors_proxy，添加 Origin 头
      if (dataSourceKey == 'cors_proxy') {
        headers['Origin'] = _getUniqueOrigin();
      }
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        try {
          // 解析 rexxar JSON 响应
          final data = jsonDecode(response.body);
          if (data is! Map<String, dynamic>) {
            return ApiResponse.error('豆瓣详情数据格式错误');
          }

          final details = DoubanMovieDetails.fromJson(data);
          if (details.title.trim().isEmpty) {
            return ApiResponse.error('豆瓣详情数据解析为空');
          }
          
          // 缓存成功的结果，缓存时间为3天
          try {
            await _cacheService.set(
              cacheKey,
              details.toJson(),
              const Duration(days: 3),
            );
          } catch (cacheError) {
            print('缓存豆瓣详情数据失败: $cacheError');
          }
          
          return ApiResponse.success(details, statusCode: response.statusCode);
        } catch (parseError) {
          return ApiResponse.error('豆瓣详情数据解析失败: ${parseError.toString()}');
        }
      } else {
        return ApiResponse.error(
          '获取豆瓣详情数据失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.error('豆瓣详情数据请求异常: ${e.toString()}');
    }
  }
}
