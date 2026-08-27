import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../widgets/capsule_tab_switcher.dart';
import '../widgets/custom_refresh_indicator.dart';
import '../widgets/douban_movies_grid.dart';
import '../services/douban_service.dart';
import '../services/bangumi_service.dart';
import '../models/douban_movie.dart';
import '../models/bangumi.dart';
import '../models/video_info.dart';
import '../widgets/video_menu_bottom_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/pulsing_dots_indicator.dart';
import '../widgets/bangumi_grid.dart';
import '../widgets/simple_tab_switcher.dart';
import 'player_screen.dart';
import '../widgets/filter_pill_hover.dart';
import '../utils/device_utils.dart';
import '../utils/font_utils.dart';
import '../widgets/filter_options_selector.dart';

class AnimeScreen extends StatefulWidget {
  const AnimeScreen({super.key});

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  // 动漫一级选择器选项
  final List<SelectorOption> _animePrimaryOptions = const [
    SelectorOption(label: '每日放送', value: '每日放送'),
    SelectorOption(label: '番剧', value: '番剧'),
    SelectorOption(label: '剧场版', value: '剧场版'),
  ];

  // 星期选项
  final List<SelectorOption> _weekdayOptions = const [
    SelectorOption(label: '周一', value: '1'),
    SelectorOption(label: '周二', value: '2'),
    SelectorOption(label: '周三', value: '3'),
    SelectorOption(label: '周四', value: '4'),
    SelectorOption(label: '周五', value: '5'),
    SelectorOption(label: '周六', value: '6'),
    SelectorOption(label: '周日', value: '7'),
  ];

  // 番剧类型选项
  final List<SelectorOption> _animeTypeOptions = const [
    SelectorOption(label: '全部', value: 'all'),
    SelectorOption(label: '黑色幽默', value: 'dark_humor'),
    SelectorOption(label: '历史', value: 'history'),
    SelectorOption(label: '歌舞', value: 'musical'),
    SelectorOption(label: '励志', value: 'inspirational'),
    SelectorOption(label: '恶搞', value: 'parody'),
    SelectorOption(label: '治愈', value: 'healing'),
    SelectorOption(label: '运动', value: 'sports'),
    SelectorOption(label: '后宫', value: 'harem'),
    SelectorOption(label: '情色', value: 'erotic'),
    SelectorOption(label: '国漫', value: 'chinese_anime'),
    SelectorOption(label: '人性', value: 'human_nature'),
    SelectorOption(label: '悬疑', value: 'suspense'),
    SelectorOption(label: '恋爱', value: 'love'),
    SelectorOption(label: '魔幻', value: 'fantasy'),
    SelectorOption(label: '科幻', value: 'sci_fi'),
  ];

  // 剧场版类型选项
  final List<SelectorOption> _movieTypeOptions = const [
    SelectorOption(label: '全部', value: 'all'),
    SelectorOption(label: '定格动画', value: 'stop_motion'),
    SelectorOption(label: '传记', value: 'biography'),
    SelectorOption(label: '美国动画', value: 'us_animation'),
    SelectorOption(label: '爱情', value: 'romance'),
    SelectorOption(label: '黑色幽默', value: 'dark_humor'),
    SelectorOption(label: '歌舞', value: 'musical'),
    SelectorOption(label: '儿童', value: 'children'),
    SelectorOption(label: '二次元', value: 'anime'),
    SelectorOption(label: '动物', value: 'animal'),
    SelectorOption(label: '青春', value: 'youth'),
    SelectorOption(label: '历史', value: 'history'),
    SelectorOption(label: '励志', value: 'inspirational'),
    SelectorOption(label: '恶搞', value: 'parody'),
    SelectorOption(label: '治愈', value: 'healing'),
    SelectorOption(label: '运动', value: 'sports'),
    SelectorOption(label: '后宫', value: 'harem'),
    SelectorOption(label: '情色', value: 'erotic'),
    SelectorOption(label: '人性', value: 'human_nature'),
    SelectorOption(label: '悬疑', value: 'suspense'),
    SelectorOption(label: '恋爱', value: 'love'),
    SelectorOption(label: '魔幻', value: 'fantasy'),
    SelectorOption(label: '科幻', value: 'sci_fi'),
  ];

  // TV 地区选项（与 TV 一致）
  final List<SelectorOption> _regionOptions = const [
    SelectorOption(label: '全部', value: 'all'),
    SelectorOption(label: '华语', value: 'chinese'),
    SelectorOption(label: '欧美', value: 'western'),
    SelectorOption(label: '国外', value: 'foreign'),
    SelectorOption(label: '韩国', value: 'korean'),
    SelectorOption(label: '日本', value: 'japanese'),
    SelectorOption(label: '中国大陆', value: 'mainland_china'),
    SelectorOption(label: '中国香港', value: 'hong_kong'),
    SelectorOption(label: '美国', value: 'usa'),
    SelectorOption(label: '英国', value: 'uk'),
    SelectorOption(label: '泰国', value: 'thailand'),
    SelectorOption(label: '中国台湾', value: 'taiwan'),
    SelectorOption(label: '意大利', value: 'italy'),
    SelectorOption(label: '法国', value: 'france'),
    SelectorOption(label: '德国', value: 'germany'),
    SelectorOption(label: '西班牙', value: 'spain'),
    SelectorOption(label: '俄罗斯', value: 'russia'),
    SelectorOption(label: '瑞典', value: 'sweden'),
    SelectorOption(label: '巴西', value: 'brazil'),
    SelectorOption(label: '丹麦', value: 'denmark'),
    SelectorOption(label: '印度', value: 'india'),
    SelectorOption(label: '加拿大', value: 'canada'),
    SelectorOption(label: '爱尔兰', value: 'ireland'),
    SelectorOption(label: '澳大利亚', value: 'australia'),
  ];

  // 电影地区选项（与 Movie 一致）
  final List<SelectorOption> _movieRegionOptions = const [
    SelectorOption(label: '全部', value: 'all'),
    SelectorOption(label: '华语', value: 'chinese'),
    SelectorOption(label: '欧美', value: 'western'),
    SelectorOption(label: '韩国', value: 'korean'),
    SelectorOption(label: '日本', value: 'japanese'),
    SelectorOption(label: '中国大陆', value: 'mainland_china'),
    SelectorOption(label: '美国', value: 'usa'),
    SelectorOption(label: '中国香港', value: 'hong_kong'),
    SelectorOption(label: '中国台湾', value: 'taiwan'),
    SelectorOption(label: '英国', value: 'uk'),
    SelectorOption(label: '法国', value: 'france'),
    SelectorOption(label: '德国', value: 'germany'),
    SelectorOption(label: '意大利', value: 'italy'),
    SelectorOption(label: '西班牙', value: 'spain'),
    SelectorOption(label: '印度', value: 'india'),
    SelectorOption(label: '泰国', value: 'thailand'),
    SelectorOption(label: '俄罗斯', value: 'russia'),
    SelectorOption(label: '加拿大', value: 'canada'),
    SelectorOption(label: '澳大利亚', value: 'australia'),
    SelectorOption(label: '爱尔兰', value: 'ireland'),
    SelectorOption(label: '瑞典', value: 'sweden'),
    SelectorOption(label: '巴西', value: 'brazil'),
    SelectorOption(label: '丹麦', value: 'denmark'),
  ];

  // 年代选项（与 TV 一致）
  final List<SelectorOption> _yearOptions = const [
    SelectorOption(label: '全部', value: 'all'),
    SelectorOption(label: '2020年代', value: '2020s'),
    SelectorOption(label: '2025', value: '2025'),
    SelectorOption(label: '2024', value: '2024'),
    SelectorOption(label: '2023', value: '2023'),
    SelectorOption(label: '2022', value: '2022'),
    SelectorOption(label: '2021', value: '2021'),
    SelectorOption(label: '2020', value: '2020'),
    SelectorOption(label: '2019', value: '2019'),
    SelectorOption(label: '2010年代', value: '2010s'),
    SelectorOption(label: '2000年代', value: '2000s'),
    SelectorOption(label: '90年代', value: '1990s'),
    SelectorOption(label: '80年代', value: '1980s'),
    SelectorOption(label: '70年代', value: '1970s'),
    SelectorOption(label: '60年代', value: '1960s'),
    SelectorOption(label: '更早', value: 'earlier'),
  ];

  // 平台选项（与 TV 一致）
  final List<SelectorOption> _platformOptions = const [
    SelectorOption(label: '全部', value: 'all'),
    SelectorOption(label: '腾讯视频', value: 'tencent'),
    SelectorOption(label: '爱奇艺', value: 'iqiyi'),
    SelectorOption(label: '优酷', value: 'youku'),
    SelectorOption(label: '湖南卫视', value: 'hunan_tv'),
    SelectorOption(label: 'Netflix', value: 'netflix'),
    SelectorOption(label: 'HBO', value: 'hbo'),
    SelectorOption(label: 'BBC', value: 'bbc'),
    SelectorOption(label: 'NHK', value: 'nhk'),
    SelectorOption(label: 'CBS', value: 'cbs'),
    SelectorOption(label: 'NBC', value: 'nbc'),
    SelectorOption(label: 'tvN', value: 'tvn'),
  ];

  // 排序选项（与 TV/Movie 一致）
  final List<SelectorOption> _sortOptions = const [
    SelectorOption(label: '综合排序', value: 'T'),
    SelectorOption(label: '近期热度', value: 'U'),
    SelectorOption(label: '首映时间', value: 'R'),
    SelectorOption(label: '高分优先', value: 'S'),
  ];

  String _selectedCategoryValue = '每日放送'; // 默认选中每日放送
  String _selectedWeekday = DateTime.now().weekday.toString(); // 默认选中当前星期

  // 番剧筛选状态
  String _selectedAnimeType = 'all';
  String _selectedAnimeRegion = 'all';
  String _selectedAnimeYear = 'all';
  String _selectedAnimePlatform = 'all';
  String _selectedAnimeSort = 'T';

  // 剧场版筛选状态
  String _selectedMovieType = 'all';
  String _selectedMovieRegion = 'all';
  String _selectedMovieYear = 'all';
  String _selectedMovieSort = 'T';

  final ScrollController _scrollController = ScrollController();
  final List<DoubanMovie> _animeList = [];
  final List<BangumiItem> _bangumiList = [];
  int _page = 0;
  final int _pageLimit = 25;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAnimeData(isRefresh: true);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!mounted) return;

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      
      // 每日放送不需要加载更多
      if (_selectedCategoryValue == '每日放送') {
        return;
      }
      
      // 如果内容不足以滚动（maxScrollExtent <= 0），直接尝试加载更多
      if (position.maxScrollExtent <= 0) {
        // 检查是否有更多数据且当前不在加载中
        if (_hasMore && !_isLoading && !_isLoadingMore && _animeList.isNotEmpty) {
          _loadMoreAnimeData();
        }
        return;
      }
      
      // 正常滚动情况：当滚动到距离底部50像素内时触发加载
      const double threshold = 50.0;
      if (position.pixels >= position.maxScrollExtent - threshold) {
        _loadMoreAnimeData();
      }
    }
  }

  Future<void> _loadMoreAnimeData() async {
    if (!mounted) return;
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (_selectedCategoryValue == '每日放送') return; // Bangumi 数据不支持分页

    setState(() {
      _isLoadingMore = true;
    });

    // 获取豆瓣数据（与 _fetchAnimeData 中的逻辑相同）
    String categoryValue;
    String regionValue;
    String yearValue;
    String platformValue;
    String sortValue;
    String kind;
    String format;

    if (_selectedCategoryValue == '番剧') {
      categoryValue = _selectedAnimeType;
      regionValue = _selectedAnimeRegion;
      yearValue = _selectedAnimeYear;
      platformValue = _selectedAnimePlatform;
      sortValue = _selectedAnimeSort;
      kind = 'tv';
      format = '电视剧';
    } else { // 剧场版
      categoryValue = _selectedMovieType;
      regionValue = _selectedMovieRegion;
      yearValue = _selectedMovieYear;
      platformValue = 'all';
      sortValue = _selectedMovieSort;
      kind = 'movie';
      format = '';
    }

    // 转换参数为中文标签
    if (regionValue != 'all') {
      final regionOptions = _selectedCategoryValue == '番剧' ? _regionOptions : _movieRegionOptions;
      regionValue = regionOptions
          .firstWhere((e) => e.value == regionValue)
          .label;
    }
    
    if (yearValue != 'all') {
      yearValue = _yearOptions
          .firstWhere((e) => e.value == yearValue)
          .label;
    }
    
    if (categoryValue != 'all') {
      final typeOptions = _selectedCategoryValue == '番剧' ? _animeTypeOptions : _movieTypeOptions;
      categoryValue = typeOptions
          .firstWhere((e) => e.value == categoryValue)
          .label;
    }

    if (_selectedCategoryValue == '番剧' && platformValue != 'all') {
      platformValue = _platformOptions
          .firstWhere((e) => e.value == platformValue)
          .label;
    }
    
    final params = _selectedCategoryValue == '番剧' 
        ? DoubanRecommendsParams(
            kind: kind,
            category: '动画',
            label: categoryValue,
            format: format,
            region: regionValue,
            year: yearValue,
            platform: platformValue,
            sort: sortValue,
            pageLimit: _pageLimit,
            page: _page,
          )
        : DoubanRecommendsParams(
            kind: kind,
            category: '动画',
            label: categoryValue,
            format: format,
            region: regionValue,
            year: yearValue,
            sort: sortValue,
            pageLimit: _pageLimit,
            page: _page,
          );
    
    final result = await DoubanService.fetchDoubanRecommends(
      context,
      params,
    );
    if (mounted) {
      setState(() {
        if (result.success && result.data != null) {
          _animeList.addAll(result.data!);
          _page++;
          if (result.data!.isEmpty) {
            _hasMore = false;
          }
        }
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _fetchAnimeData({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      if (isRefresh) {
        _animeList.clear();
        _bangumiList.clear();
        _page = 0;
        _hasMore = true;
      }
      _errorMessage = null;
    });

    if (_selectedCategoryValue == '每日放送') {
      // 获取 Bangumi 数据
      final weekdayInt = int.parse(_selectedWeekday);
      final result = await BangumiService.getCalendarByWeekday(context, weekdayInt);
      if (mounted) {
        setState(() {
          if (result.success && result.data != null) {
            _bangumiList.clear();
            _bangumiList.addAll(
              result.data!.where((item) => item.images.bestImageUrl.isNotEmpty).toList()
            );
            _hasMore = false; // Bangumi 数据不支持分页
          } else {
            _errorMessage = result.message ?? '加载失败';
          }
          _isLoading = false;
        });
      }
    } else {
      // 获取豆瓣数据
      String categoryValue;
      String regionValue;
      String yearValue;
      String platformValue;
      String sortValue;
      String kind;
      String format;

      if (_selectedCategoryValue == '番剧') {
        categoryValue = _selectedAnimeType;
        regionValue = _selectedAnimeRegion;
        yearValue = _selectedAnimeYear;
        platformValue = _selectedAnimePlatform;
        sortValue = _selectedAnimeSort;
        kind = 'tv';
        format = '电视剧';
      } else { // 剧场版
        categoryValue = _selectedMovieType;
        regionValue = _selectedMovieRegion;
        yearValue = _selectedMovieYear;
        platformValue = 'all';
        sortValue = _selectedMovieSort;
        kind = 'movie';
        format = '';
      }

      // 转换地区参数为中文标签
      if (regionValue != 'all') {
        final regionOptions = _selectedCategoryValue == '番剧' ? _regionOptions : _movieRegionOptions;
        regionValue = regionOptions
            .firstWhere((e) => e.value == regionValue)
            .label;
      }
      
      // 转换年代参数为中文标签
      if (yearValue != 'all') {
        yearValue = _yearOptions
            .firstWhere((e) => e.value == yearValue)
            .label;
      }
      
      // 转换类型参数为中文标签
      if (categoryValue != 'all') {
        final typeOptions = _selectedCategoryValue == '番剧' ? _animeTypeOptions : _movieTypeOptions;
        categoryValue = typeOptions
            .firstWhere((e) => e.value == categoryValue)
            .label;
      }

      // 转换平台参数为中文标签（仅番剧需要）
      if (_selectedCategoryValue == '番剧' && platformValue != 'all') {
        platformValue = _platformOptions
            .firstWhere((e) => e.value == platformValue)
            .label;
      }
      
      final params = _selectedCategoryValue == '番剧' 
          ? DoubanRecommendsParams(
              kind: kind,
              category: '动画',
              label: categoryValue,
              format: format,
              region: regionValue,
              year: yearValue,
              platform: platformValue,
              sort: sortValue,
              pageLimit: _pageLimit,
              page: _page,
            )
          : DoubanRecommendsParams(
              kind: kind,
              category: '动画',
              label: categoryValue,
              format: format,
              region: regionValue,
              year: yearValue,
              sort: sortValue,
              pageLimit: _pageLimit,
              page: _page,
            );
      
      final result = await DoubanService.fetchDoubanRecommends(
        context,
        params,
      );
      if (mounted) {
        setState(() {
          if (result.success && result.data != null) {
            _animeList.addAll(result.data!);
            _page++;
            // 只有当返回的数据为空时才停止分页
            if (result.data!.isEmpty) {
              _hasMore = false;
            }
          } else {
            _errorMessage = result.message ?? '加载失败';
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshAnimeData() async {
    await _fetchAnimeData(isRefresh: true);
  }

  void _onVideoTap(VideoInfo videoInfo) {
    if (_selectedCategoryValue == '剧场版') {
      // 剧场版，传递 title 和 stype=movie
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            title: videoInfo.title,
            stype: 'movie',
            year: videoInfo.year,
          ),
        ),
      );
    } else {
      // 每日放送或番剧，只传递 title
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            title: videoInfo.title,
            year: videoInfo.year,
          ),
        ),
      );
    }
  }

  void _handleMenuAction(VideoInfo videoInfo, VideoMenuAction action) {
    switch (action) {
      case VideoMenuAction.play:
        _onVideoTap(videoInfo);
        break;
      case VideoMenuAction.doubanDetail:
        _launchURL('https://movie.douban.com/subject/${videoInfo.id}/');
        break;
      default:
        break;
    }
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StyledRefreshIndicator(
      onRefresh: _refreshAnimeData,
      refreshText: '刷新动漫数据...',
      primaryColor: const Color(0xFF27AE60),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildFilterSection(),
            const SizedBox(height: 16),
            _selectedCategoryValue == '每日放送' 
                ? BangumiGrid(
                    bangumiItems: _bangumiList,
                    isLoading: _isLoading && _bangumiList.isEmpty,
                    errorMessage: _errorMessage,
                    onVideoTap: _onVideoTap,
                    onGlobalMenuAction: (videoInfo, action) {
                      _handleMenuAction(videoInfo, action);
                    },
                    contentType: 'anime',
                  )
                : DoubanMoviesGrid(
                    movies: _animeList,
                    isLoading: _isLoading && _animeList.isEmpty,
                    errorMessage: _errorMessage,
                    onVideoTap: _onVideoTap,
                    onGlobalMenuAction: (videoInfo, action) {
                      _handleMenuAction(videoInfo, action);
                    },
                    contentType: 'anime',
                  ),
            // 底部指示器 - 加载更多或到底提示
            if (_selectedCategoryValue == '每日放送')
              // Bangumi 数据无需加载更多，直接显示底部指示器
              (_bangumiList.isNotEmpty && !_isLoading)
                  ? _buildEndOfListIndicator()
                  : const SizedBox(height: 50)
            else if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: PulsingDotsIndicator(),
              )
            else if (!_hasMore && _animeList.isNotEmpty && !_isLoading)
              _buildEndOfListIndicator()
            else
              const SizedBox(height: 50), // 占位符保持间距
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '动漫',
            style: FontUtils.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 20, // 固定高度确保一致性
            child: Text(
              _selectedCategoryValue == '每日放送' 
                  ? '来自 Bangumi 的精选内容'
                  : '来自豆瓣的精选内容',
              style: FontUtils.poppins(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    final themeService = Provider.of<ThemeService>(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? Colors.white.withOpacity(0.1)
            : Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterRow(
            '分类',
            _animePrimaryOptions,
            _selectedCategoryValue,
            (newValue) {
              setState(() {
                _selectedCategoryValue = newValue;
                // 重置筛选为默认值
                _selectedWeekday = DateTime.now().weekday.toString();
                _selectedAnimeType = 'all';
                _selectedAnimeRegion = 'all';
                _selectedAnimeYear = 'all';
                _selectedAnimePlatform = 'all';
                _selectedAnimeSort = 'T';
                _selectedMovieType = 'all';
                _selectedMovieRegion = 'all';
                _selectedMovieYear = 'all';
                _selectedMovieSort = 'T';
              });
              _fetchAnimeData(isRefresh: true);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 66,
            child: _buildSecondaryFilterSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryFilterSection() {
    if (_selectedCategoryValue == '每日放送') {
      return _buildWeekdayFilterSection();
    } else if (_selectedCategoryValue == '番剧') {
      return _buildAnimeFilterSection();
    } else { // 剧场版
      return _buildMovieFilterSection();
    }
  }

  Widget _buildWeekdayFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '星期',
          style: FontUtils.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SimpleTabSwitcher(
            tabs: _weekdayOptions.map((e) => e.label).toList(),
            selectedTab: _weekdayOptions.firstWhere((e) => e.value == _selectedWeekday).label,
            onTabChanged: (newLabel) {
              final newValue = _weekdayOptions.firstWhere((e) => e.label == newLabel).value;
              setState(() {
                _selectedWeekday = newValue;
              });
              _fetchAnimeData(isRefresh: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnimeFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '筛选',
          style: FontUtils.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill('类型', _animeTypeOptions, _selectedAnimeType, (v) {
                  setState(() => _selectedAnimeType = v);
                  _fetchAnimeData(isRefresh: true);
                }),
                _buildFilterPill('地区', _regionOptions, _selectedAnimeRegion, (v) {
                  setState(() => _selectedAnimeRegion = v);
                  _fetchAnimeData(isRefresh: true);
                }),
                _buildFilterPill('年代', _yearOptions, _selectedAnimeYear, (v) {
                  setState(() => _selectedAnimeYear = v);
                  _fetchAnimeData(isRefresh: true);
                }),
                _buildFilterPill('平台', _platformOptions, _selectedAnimePlatform, (v) {
                  setState(() => _selectedAnimePlatform = v);
                  _fetchAnimeData(isRefresh: true);
                }),
                _buildFilterPill('排序', _sortOptions, _selectedAnimeSort, (v) {
                  setState(() => _selectedAnimeSort = v);
                  _fetchAnimeData(isRefresh: true);
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMovieFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '筛选',
          style: FontUtils.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill('类型', _movieTypeOptions, _selectedMovieType, (v) {
                  setState(() => _selectedMovieType = v);
                  _fetchAnimeData(isRefresh: true);
                }),
                _buildFilterPill('地区', _movieRegionOptions, _selectedMovieRegion, (v) {
                  setState(() => _selectedMovieRegion = v);
                  _fetchAnimeData(isRefresh: true);
                }),
                _buildFilterPill('年代', _yearOptions, _selectedMovieYear, (v) {
                  setState(() => _selectedMovieYear = v);
                  _fetchAnimeData(isRefresh: true);
                }),
                _buildFilterPill('排序', _sortOptions, _selectedMovieSort, (v) {
                  setState(() => _selectedMovieSort = v);
                  _fetchAnimeData(isRefresh: true);
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPill(String title, List<SelectorOption> options,
      String selectedValue, ValueChanged<String> onSelected) {
    final selectedOption = options.firstWhere((e) => e.value == selectedValue,
        orElse: () => options.first);
    bool isDefault = selectedValue == 'all' ||
        (title == '排序' && selectedValue == 'T');

    return FilterPillHover(
      isPC: DeviceUtils.isPC(),
      isDefault: isDefault,
      title: title,
      selectedOption: selectedOption,
      onTap: () {
        _showFilterOptions(context, title, options, selectedValue, onSelected);
      },
    );
  }

  void _showFilterOptions(
      BuildContext context,
      String title,
      List<SelectorOption> options,
      String selectedValue,
      ValueChanged<String> onSelected) {
    showFilterOptionsSelector(
      context: context,
      title: title,
      options: options,
      selectedValue: selectedValue,
      onSelected: onSelected,
    );
  }

  Widget _buildFilterRow(
    String title,
    List<SelectorOption> items,
    String selectedValue,
    Function(String) onItemSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: FontUtils.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CapsuleTabSwitcher(
            tabs: items.map((e) => e.label).toList(),
            selectedTab: items.firstWhere((e) => e.value == selectedValue).label,
            onTabChanged: (newLabel) {
              final newValue = items.firstWhere((e) => e.label == newLabel).value;
              onItemSelected(newValue);
            },
          ),
        ),
      ],
    );
  }


  Widget _buildEndOfListIndicator() {
    final themeService = Provider.of<ThemeService>(context);
    final totalCount = _selectedCategoryValue == '每日放送' ? _bangumiList.length : _animeList.length;
    final contentType = _selectedCategoryValue == '每日放送' ? '个番剧' : 
                       _selectedCategoryValue == '番剧' ? '部番剧' : '部动画电影';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 2,
            decoration: BoxDecoration(
              color: themeService.isDarkMode
                  ? Colors.white.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '已经到底啦~',
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode
                  ? Colors.white.withOpacity(0.6)
                  : Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '共 $totalCount $contentType',
            style: FontUtils.poppins(
              fontSize: 12,
              color: themeService.isDarkMode
                  ? Colors.white.withOpacity(0.4)
                  : Colors.grey[500],
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}
