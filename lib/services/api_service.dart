import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'user_data_service.dart';
import '../screens/login_screen.dart';
import '../models/favorite_item.dart';
import '../models/search_result.dart';
import '../models/play_record.dart';
import '../models/search_resource.dart';
import '../models/live_source.dart';
import '../models/live_channel.dart';
import '../models/epg_program.dart';
import '../models/search_suggestion.dart';

/// API响应结果类
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.statusCode,
  });

  factory ApiResponse.success(T data, {int? statusCode}) {
    return ApiResponse<T>(
      success: true,
      data: data,
      statusCode: statusCode,
    );
  }

  factory ApiResponse.error(String message, {int? statusCode}) {
    return ApiResponse<T>(
      success: false,
      message: message,
      statusCode: statusCode,
    );
  }
}

/// 通用API请求服务
class ApiService {
  static const Duration _timeout = Duration(seconds: 30);

  /// 获取基础URL
  static Future<String?> _getBaseUrl() async {
    return await UserDataService.getServerUrl();
  }

  /// 获取认证cookies
  static Future<String?> _getCookies() async {
    return await UserDataService.getCookies();
  }

  /// 构建完整URL
  static Future<String> _buildUrl(String endpoint) async {
    final baseUrl = await _getBaseUrl();
    if (baseUrl == null) {
      throw Exception('服务器地址未配置，请先登录');
    }

    // 确保baseUrl不以/结尾，endpoint以/开头
    String cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    String cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    return '$cleanBaseUrl$cleanEndpoint';
  }

  /// 添加浏览器特征头
  static Future<void> addBrowserHeaders(Map<String, String> headers) async {
    final ua = await UserDataService.getCustomUserAgent();
    headers['User-Agent'] = ua;

    final enabled = await UserDataService.getEnableBrowserHeaders();
    if (enabled) {
      headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
      headers['Accept-Encoding'] = 'gzip, deflate, br';
      headers['Sec-Fetch-Site'] = 'same-origin';
      headers['Sec-Fetch-Mode'] = 'cors';
      headers['Sec-Fetch-Dest'] = 'empty';
      headers['Sec-Ch-Ua'] =
          '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"';
      headers['Sec-Ch-Ua-Mobile'] = '?0';
      headers['Sec-Ch-Ua-Platform'] = '"Windows"';
    }

    final customHeader = await UserDataService.getCustomHeader();
    if (customHeader.isNotEmpty) {
      headers.addAll(customHeader);
    }
  }

  /// 构建请求头
  static Future<Map<String, String>> _buildHeaders({
    Map<String, String>? additionalHeaders,
    bool includeAuth = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // 添加浏览器特征头
    await addBrowserHeaders(headers);

    // 添加认证cookies
    if (includeAuth) {
      final cookies = await _getCookies();
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
    }

    // 添加额外头部
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    return headers;
  }

  /// 处理响应
  static Future<ApiResponse<T>> _handleResponse<T>(
    http.Response response,
    T Function(dynamic)? fromJson,
    BuildContext? context,
  ) async {
    // 处理401未授权
    if (response.statusCode == 401) {
      // 清除用户数据
      await UserDataService.clearUserData();

      // 跳转到登录页
      if (context != null && context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }

      return ApiResponse.error(
        '登录已过期，请重新登录',
        statusCode: 401,
      );
    }

    // 处理其他错误状态码
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String errorMessage = '请求失败';
      try {
        final errorData = json.decode(response.body);
        errorMessage =
            errorData['message'] ?? errorData['error'] ?? errorMessage;
      } catch (e) {
        // 如果解析失败，使用默认错误信息
        switch (response.statusCode) {
          case 400:
            errorMessage = '请求参数错误';
            break;
          case 403:
            errorMessage = '没有权限访问';
            break;
          case 404:
            errorMessage = '请求的资源不存在';
            break;
          case 500:
            errorMessage = '服务器内部错误';
            break;
          default:
            errorMessage = '网络请求失败 (${response.statusCode})';
        }
      }

      return ApiResponse.error(
        errorMessage,
        statusCode: response.statusCode,
      );
    }

    // 处理成功响应
    try {
      final responseData = json.decode(response.body);

      if (fromJson != null) {
        final data = fromJson(responseData);
        return ApiResponse.success(data, statusCode: response.statusCode);
      } else {
        return ApiResponse.success(responseData as T,
            statusCode: response.statusCode);
      }
    } catch (e) {
      return ApiResponse.error(
        '响应数据解析失败: ${e.toString()}',
        statusCode: response.statusCode,
      );
    }
  }

  /// GET请求
  static Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
    BuildContext? context,
  }) async {
    try {
      String url = await _buildUrl(endpoint);

      // 添加查询参数
      if (queryParameters != null && queryParameters.isNotEmpty) {
        final uri = Uri.parse(url);
        final newUri = uri.replace(queryParameters: queryParameters);
        url = newUri.toString();
      }

      final requestHeaders = await _buildHeaders(additionalHeaders: headers);

      final response = await http
          .get(
            Uri.parse(url),
            headers: requestHeaders,
          )
          .timeout(_timeout);

      return await _handleResponse(response, fromJson, context);
    } catch (e) {
      return ApiResponse.error('网络请求异常: ${e.toString()}');
    }
  }

  /// POST请求
  static Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
    BuildContext? context,
  }) async {
    try {
      final url = await _buildUrl(endpoint);
      final requestHeaders = await _buildHeaders(additionalHeaders: headers);

      final response = await http
          .post(
            Uri.parse(url),
            headers: requestHeaders,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(_timeout);

      return await _handleResponse(response, fromJson, context);
    } catch (e) {
      return ApiResponse.error('网络请求异常: ${e.toString()}');
    }
  }

  /// PUT请求
  static Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
    BuildContext? context,
  }) async {
    try {
      final url = await _buildUrl(endpoint);
      final requestHeaders = await _buildHeaders(additionalHeaders: headers);

      final response = await http
          .put(
            Uri.parse(url),
            headers: requestHeaders,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(_timeout);

      return await _handleResponse(response, fromJson, context);
    } catch (e) {
      return ApiResponse.error('网络请求异常: ${e.toString()}');
    }
  }

  /// DELETE请求
  static Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
    BuildContext? context,
  }) async {
    try {
      final url = await _buildUrl(endpoint);
      final requestHeaders = await _buildHeaders(additionalHeaders: headers);

      final response = await http
          .delete(
            Uri.parse(url),
            headers: requestHeaders,
          )
          .timeout(_timeout);

      return await _handleResponse(response, fromJson, context);
    } catch (e) {
      return ApiResponse.error('网络请求异常: ${e.toString()}');
    }
  }

  /// 上传文件请求
  static Future<ApiResponse<T>> uploadFile<T>(
    String endpoint,
    String filePath, {
    Map<String, String>? fields,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
    BuildContext? context,
  }) async {
    try {
      final url = await _buildUrl(endpoint);
      final requestHeaders = await _buildHeaders(
        additionalHeaders: headers,
        includeAuth: true,
      );

      // 移除Content-Type，让http包自动设置multipart的Content-Type
      requestHeaders.remove('Content-Type');

      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers.addAll(requestHeaders);

      // 添加文件
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      // 添加其他字段
      if (fields != null) {
        request.fields.addAll(fields);
      }

      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      return await _handleResponse(response, fromJson, context);
    } catch (e) {
      return ApiResponse.error('文件上传异常: ${e.toString()}');
    }
  }

  /// 获取收藏夹列表
  static Future<ApiResponse<List<FavoriteItem>>> getFavorites(
      BuildContext context) async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) {
        return ApiResponse.error('服务器地址未配置');
      }

      final cookies = await _getCookies();
      if (cookies == null) {
        return ApiResponse.error('用户未登录');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/favorites'),
        headers: await _buildHeaders(),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<FavoriteItem> favorites = [];

        // 将Map转换为List并按save_time降序排序
        data.forEach((id, itemData) {
          favorites.add(FavoriteItem.fromJson(id, itemData));
        });

        // 按save_time降序排序
        favorites.sort((a, b) => b.saveTime.compareTo(a.saveTime));

        return ApiResponse.success(favorites, statusCode: response.statusCode);
      } else if (response.statusCode == 401) {
        // 未授权，跳转到登录页面
        if (context.mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return ApiResponse.error('登录已过期，请重新登录',
            statusCode: response.statusCode);
      } else {
        return ApiResponse.error('获取收藏夹失败: ${response.statusCode}',
            statusCode: response.statusCode);
      }
    } catch (e) {
      return ApiResponse.error('获取收藏夹异常: ${e.toString()}');
    }
  }

  /// 获取搜索历史
  static Future<ApiResponse<List<String>>> getSearchHistory(
      BuildContext context) async {
    try {
      final response = await get<List<String>>(
        '/api/searchhistory',
        context: context,
        fromJson: (data) => (data as List).cast<String>(),
      );

      if (response.success && response.data != null) {
        return ApiResponse.success(response.data!,
            statusCode: response.statusCode);
      } else {
        return ApiResponse.error(response.message ?? '获取搜索历史失败');
      }
    } catch (e) {
      return ApiResponse.error('获取搜索历史异常: ${e.toString()}');
    }
  }

  /// 添加搜索历史
  static Future<ApiResponse<void>> addSearchHistory(
      String query, BuildContext context) async {
    try {
      final response = await post<void>(
        '/api/searchhistory',
        context: context,
        body: {'keyword': query},
      );

      return response;
    } catch (e) {
      return ApiResponse.error('添加搜索历史异常: ${e.toString()}');
    }
  }

  /// 清空搜索历史
  static Future<ApiResponse<void>> clearSearchHistory(
      BuildContext context) async {
    try {
      final response = await delete<void>(
        '/api/searchhistory',
        context: context,
      );

      return response;
    } catch (e) {
      return ApiResponse.error('清空搜索历史异常: ${e.toString()}');
    }
  }

  /// 删除单个搜索历史
  static Future<ApiResponse<void>> deleteSearchHistory(
      String query, BuildContext context) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await delete<void>(
        '/api/searchhistory?keyword=$encodedQuery',
        context: context,
      );

      return response;
    } catch (e) {
      return ApiResponse.error('删除搜索历史异常: ${e.toString()}');
    }
  }

  /// 保存播放记录
  static Future<ApiResponse<void>> savePlayRecord(
      PlayRecord playRecord, BuildContext context) async {
    try {
      // 构建正确的请求体格式
      final key = '${playRecord.source}+${playRecord.id}';
      final body = {
        'key': key,
        'record': playRecord.toJson(),
      };

      final response = await post<void>(
        '/api/playrecords',
        body: body,
        context: context,
      );

      return response;
    } catch (e) {
      return ApiResponse.error('保存播放记录异常: ${e.toString()}');
    }
  }

  /// 删除播放记录
  static Future<ApiResponse<void>> deletePlayRecord(
      String source, String id, BuildContext context) async {
    try {
      final key = '$source+$id';
      final encodedKey = Uri.encodeComponent(key);
      final response = await delete<void>(
        '/api/playrecords?key=$encodedKey',
        context: context,
      );

      return response;
    } catch (e) {
      return ApiResponse.error('删除播放记录异常: ${e.toString()}');
    }
  }

  /// 清空播放记录
  static Future<ApiResponse<void>> clearPlayRecord(BuildContext context) async {
    try {
      final response = await delete<void>(
        '/api/playrecords',
        context: context,
      );

      return response;
    } catch (e) {
      return ApiResponse.error('清空播放记录异常: ${e.toString()}');
    }
  }

  /// 添加收藏
  static Future<ApiResponse<void>> favorite(String source, String id,
      Map<String, dynamic> favoriteData, BuildContext context) async {
    try {
      final key = '$source+$id';
      final body = {
        'key': key,
        'favorite': favoriteData,
      };

      final response = await post<void>(
        '/api/favorites',
        body: body,
        context: context,
      );

      return response;
    } catch (e) {
      return ApiResponse.error('收藏异常: ${e.toString()}');
    }
  }

  /// 取消收藏
  static Future<ApiResponse<void>> unfavorite(
      String source, String id, BuildContext context) async {
    try {
      final key = '$source+$id';
      final encodedKey = Uri.encodeComponent(key);
      final response = await delete<void>(
        '/api/favorites?key=$encodedKey',
        context: context,
      );

      return response;
    } catch (e) {
      return ApiResponse.error('取消收藏异常: ${e.toString()}');
    }
  }

  /// 检查网络连接状态
  static Future<bool> checkConnection() async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) return false;

      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
        headers: await _buildHeaders(includeAuth: false),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 自动登录方法
  static Future<ApiResponse<String>> autoLogin() async {
    try {
      // 获取用户数据
      final serverUrl = await UserDataService.getServerUrl();
      final username = await UserDataService.getUsername();
      final password = await UserDataService.getPassword();

      if (serverUrl == null || username == null || password == null) {
        return ApiResponse.error('缺少登录信息');
      }

      // 处理 URL
      String baseUrl = serverUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      String loginUrl = '$baseUrl/api/login';

      final loginHeaders = <String, String>{
        'Content-Type': 'application/json',
      };
      await addBrowserHeaders(loginHeaders);

      // 发送登录请求
      final response = await http
          .post(
            Uri.parse(loginUrl),
            headers: loginHeaders,
            body: json.encode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        // 解析并保存 cookies
        String cookies = _parseCookies(response);

        // 更新 cookies
        await UserDataService.saveUserData(
          serverUrl: baseUrl,
          username: username,
          password: password,
          cookies: cookies,
        );

        return ApiResponse.success('自动登录成功', statusCode: response.statusCode);
      } else {
        return ApiResponse.error(
          '自动登录失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.error('自动登录异常: ${e.toString()}');
    }
  }

  /// 获取视频详情
  static Future<List<SearchResult>> fetchSourceDetail(
      String source, String id) async {
    try {
      final response = await get<SearchResult>(
        '/api/detail',
        queryParameters: {
          'source': source,
          'id': id,
        },
        fromJson: (data) => SearchResult.fromJson(data as Map<String, dynamic>),
      );

      if (response.success && response.data != null) {
        return [response.data!];
      } else {
        print('获取视频详情失败: ${response.message}');
        return [];
      }
    } catch (e) {
      print('获取视频详情失败: $e');
      return [];
    }
  }

  /// 搜索视频源数据
  static Future<List<SearchResult>> fetchSourcesData(String query) async {
    try {
      final response = await get<Map<String, dynamic>>(
        '/api/search',
        queryParameters: {
          'q': query.trim(),
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final data = response.data!;
        final results = data['results'] as List<dynamic>? ?? [];

        // 直接返回所有搜索结果，不进行过滤
        return results
            .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        print('搜索失败: ${response.message}');
        return [];
      }
    } catch (e) {
      print('搜索失败: $e');
      return [];
    }
  }

  /// 获取搜索资源列表
  static Future<List<SearchResource>> getSearchResources() async {
    try {
      final response = await get<List<SearchResource>>(
        '/api/search/resources',
        fromJson: (data) {
          final list = data as List<dynamic>;
          return list
              .map((item) =>
                  SearchResource.fromJson(item as Map<String, dynamic>))
              .toList();
        },
      );

      if (response.success && response.data != null) {
        return response.data!;
      } else {
        print('获取搜索源失败: ${response.message}');
        return [];
      }
    } catch (e) {
      print('获取搜索源失败: $e');
      return [];
    }
  }

  /// 获取直播源列表
  static Future<List<LiveSource>> getLiveSources() async {
    try {
      final response = await get<List<LiveSource>>(
        '/api/live/sources',
        fromJson: (data) {
          final responseData = data as Map<String, dynamic>;
          final list = responseData['data'] as List<dynamic>;
          return list
              .map((item) => LiveSource.fromJson(item as Map<String, dynamic>))
              .toList();
        },
      );

      if (response.success && response.data != null) {
        return response.data!;
      } else {
        print('获取直播源列表失败: ${response.message}');
        return [];
      }
    } catch (e) {
      print('获取直播源列表失败: $e');
      return [];
    }
  }

  /// 获取直播频道列表
  static Future<List<LiveChannel>> getLiveChannels(String source) async {
    try {
      final response = await get<List<LiveChannel>>(
        '/api/live/channels',
        queryParameters: {'source': source},
        fromJson: (data) {
          final responseData = data as Map<String, dynamic>;
          final list = responseData['data'] as List<dynamic>;
          return list
              .map((item) => LiveChannel.fromJson(item as Map<String, dynamic>))
              .toList();
        },
      );

      if (response.success && response.data != null) {
        return response.data!;
      } else {
        print('获取直播频道列表失败: ${response.message}');
        return [];
      }
    } catch (e) {
      print('获取直播频道列表失败: $e');
      return [];
    }
  }

  /// 获取 EPG 节目单
  static Future<EpgData?> getLiveEpg(String tvgId, String source) async {
    try {
      final response = await get<EpgData>(
        '/api/live/epg',
        queryParameters: {
          'tvgId': tvgId,
          'source': source,
        },
        fromJson: (data) {
          final responseData = data as Map<String, dynamic>;
          final epgData = responseData['data'] as Map<String, dynamic>;
          return EpgData.fromJson(epgData);
        },
      );

      if (response.success && response.data != null) {
        return response.data!;
      } else {
        print('获取 EPG 节目单失败: ${response.message}');
        return null;
      }
    } catch (e) {
      print('获取 EPG 节目单失败: $e');
      return null;
    }
  }

  /// 获取搜索建议
  static Future<List<String>> getSearchSuggestions(String query) async {
    try {
      final response = await get<List<SearchSuggestion>>(
        '/api/search/suggestions',
        queryParameters: {'q': query.trim()},
        fromJson: (data) {
          final responseData = data as Map<String, dynamic>;
          final list = responseData['suggestions'] as List<dynamic>;
          return list
              .map((item) =>
                  SearchSuggestion.fromJson(item as Map<String, dynamic>))
              .toList();
        },
      );

      if (response.success && response.data != null) {
        // 提取建议文本列表
        return response.data!.map((suggestion) => suggestion.text).toList();
      } else {
        print('获取搜索建议失败: ${response.message}');
        return [];
      }
    } catch (e) {
      print('获取搜索建议失败: $e');
      return [];
    }
  }

  /// 解析 Set-Cookie 头部，提取所有 Cookie 的 name=value
  static String _parseCookies(http.Response response) {
    final allCookies = response.headers['set-cookie'];
    if (allCookies == null || allCookies.isEmpty) return '';

    // 按 \n（Dart http 包多值拼接方式）或 ","（HTTP 标准）切分多个 cookie
    final lines = allCookies
        .split('\n')
        .expand((line) => line.split(','))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final cookies = <String>[];
    for (final line in lines) {
      final semicolonIdx = line.indexOf(';');
      final nameValue = semicolonIdx > 0
          ? line.substring(0, semicolonIdx).trim()
          : line.trim();
      if (nameValue.contains('=')) {
        cookies.add(nameValue);
      }
    }

    return cookies.join('; ');
  }
}
