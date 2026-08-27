import 'dart:async';

// 缓存状态类型
enum CachedPageStatus {
  ok,
  timeout,
  forbidden,
}

// 缓存条目类
class CachedPageEntry {
  final int expiresAt;
  final CachedPageStatus status;
  final List<dynamic> data; // SearchResult list
  final int? pageCount; // 仅第一页可选存储

  CachedPageEntry({
    required this.expiresAt,
    required this.status,
    required this.data,
    this.pageCount,
  });
}

// 缓存配置
const int _searchCacheTtlMs = 10 * 60 * 1000; // 10分钟
const int _cacheCleanupIntervalMs = 5 * 60 * 1000; // 5分钟清理一次
const int _maxCacheSize = 1000; // 最大缓存条目数量

class LocalSearchCacheService {
  // 单例模式
  static final LocalSearchCacheService _instance = LocalSearchCacheService._internal();
  factory LocalSearchCacheService() => _instance;
  LocalSearchCacheService._internal();

  final Map<String, CachedPageEntry> _searchCache = {};
  Timer? _cleanupTimer;
  int _lastCleanupTime = 0;

  /// 生成搜索缓存键：source + query + page
  String _makeSearchCacheKey(String sourceKey, String query, int page) {
    return '$sourceKey::${query.trim()}::$page';
  }

  /// 获取缓存的搜索页面数据
  CachedPageEntry? getCachedSearchPage(
    String sourceKey,
    String query,
    int page,
  ) {
    final key = _makeSearchCacheKey(sourceKey, query, page);
    final entry = _searchCache[key];
    
    if (entry == null) return null;

    // 检查是否过期
    if (entry.expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      _searchCache.remove(key);
      return null;
    }

    return entry;
  }

  /// 设置缓存的搜索页面数据
  void setCachedSearchPage(
    String sourceKey,
    String query,
    int page,
    CachedPageStatus status,
    List<dynamic> data, {
    int? pageCount,
  }) {
    // 惰性启动自动清理
    _ensureAutoCleanupStarted();

    // 惰性清理：每次写入时检查是否需要清理
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCleanupTime > _cacheCleanupIntervalMs) {
      _performCacheCleanup();
    }

    final key = _makeSearchCacheKey(sourceKey, query, page);
    _searchCache[key] = CachedPageEntry(
      expiresAt: now + _searchCacheTtlMs,
      status: status,
      data: data,
      pageCount: pageCount,
    );
  }

  /// 确保自动清理已启动（惰性初始化）
  void _ensureAutoCleanupStarted() {
    if (_cleanupTimer == null) {
      _startAutoCleanup();
    }
  }

  /// 智能清理过期的缓存条目
  Map<String, int> _performCacheCleanup() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final keysToDelete = <String>[];
    int sizeLimitedDeleted = 0;

    // 1. 清理过期条目
    _searchCache.forEach((key, entry) {
      if (entry.expiresAt <= now) {
        keysToDelete.add(key);
      }
    });

    final expiredCount = keysToDelete.length;
    for (final key in keysToDelete) {
      _searchCache.remove(key);
    }

    // 2. 如果缓存大小超限，清理最老的条目（LRU策略）
    if (_searchCache.length > _maxCacheSize) {
      final entries = _searchCache.entries.toList();
      // 按照过期时间排序，最早过期的在前面
      entries.sort((a, b) => a.value.expiresAt.compareTo(b.value.expiresAt));

      final toRemove = _searchCache.length - _maxCacheSize;
      for (int i = 0; i < toRemove; i++) {
        _searchCache.remove(entries[i].key);
        sizeLimitedDeleted++;
      }
    }

    _lastCleanupTime = now;

    return {
      'expired': expiredCount,
      'total': _searchCache.length,
      'sizeLimited': sizeLimitedDeleted,
    };
  }

  /// 启动自动清理定时器
  void _startAutoCleanup() {
    if (_cleanupTimer != null) return; // 避免重复启动

    _cleanupTimer = Timer.periodic(
      const Duration(milliseconds: _cacheCleanupIntervalMs),
      (_) {
        _performCacheCleanup();
      },
    );
  }

  /// 停止自动清理（用于资源清理）
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _searchCache.clear();
  }

  /// 清空所有缓存
  void clearCache() {
    _searchCache.clear();
  }

  /// 获取当前缓存大小
  int get cacheSize => _searchCache.length;
}
