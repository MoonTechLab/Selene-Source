import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/search_result.dart';
import '../models/douban_movie.dart';
import '../utils/image_url.dart';

class PlayerDetailsPanel extends StatelessWidget {
  final ThemeData theme;
  final DoubanMovieDetails? doubanDetails;
  final SearchResult? currentDetail;
  final bool showCloseButton;
  final bool showTitle;

  const PlayerDetailsPanel({
    super.key,
    required this.theme,
    this.doubanDetails,
    this.currentDetail,
    this.showCloseButton = true,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: showCloseButton 
            ? (isDarkMode ? const Color(0xFF1c1c1e) : Colors.white)
            : Colors.transparent,
      ),
      child: Column(
        children: [
          // 标题栏
          if (showTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '详情',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (showCloseButton)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),
          if (!showTitle)
            const SizedBox(height: 8),
          Expanded(
            child: doubanDetails != null
                ? _buildDoubanDetailsPanel(context, isDarkMode)
                : _buildCurrentDetailPanel(context, isDarkMode),
          ),
        ],
      ),
    );
  }

  /// 构建豆瓣详情面板
  Widget _buildDoubanDetailsPanel(BuildContext context, bool isDarkMode) {
    final String title = doubanDetails!.title;
    final String cover = doubanDetails!.poster;
    final String year = doubanDetails!.year;
    final String? rate = doubanDetails!.rate;
    final List<String> genres = doubanDetails!.genres;
    final List<String> directors = doubanDetails!.directors;
    final List<String> writers = doubanDetails!.screenwriters;
    final List<String> actors = doubanDetails!.actors;
    final String summary = doubanDetails!.summary ?? '暂无简介';
    final List<String> countries = doubanDetails!.countries;
    final List<String> languages = doubanDetails!.languages;
    final String? duration = doubanDetails!.duration;
    final String? originalTitle = doubanDetails!.originalTitle;
    final int? totalEpisodes = doubanDetails!.totalEpisodes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主要信息区域
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧封面
              _buildCoverImage(context, cover, 'douban', isDarkMode),
              const SizedBox(width: 16),
              // 右侧信息
              Expanded(
                child: SizedBox(
                  height: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // 标题
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 原标题
                      if (originalTitle != null &&
                          originalTitle.isNotEmpty &&
                          originalTitle != title)
                        Text(
                          originalTitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const Spacer(),
                      // 底部信息区域
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (countries.isNotEmpty || languages.isNotEmpty)
                            Text(
                              [
                                if (countries.isNotEmpty) countries.join(' | '),
                                if (languages.isNotEmpty) languages.join(' | '),
                              ].join(' | '),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            year,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (duration != null && duration.isNotEmpty) ...[
                            Text(
                              duration,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (totalEpisodes != null && totalEpisodes > 1) ...[
                            Text(
                              '全$totalEpisodes集',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 评分
              if (rate != null && rate.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      rate,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildStarRating(rate, isDarkMode),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 标签区域
          if (genres.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '风格',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: genres
                      .map((genre) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.grey[700]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              genre,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDarkMode
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // 制作信息
          if (directors.isNotEmpty || writers.isNotEmpty || actors.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '制作信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                _buildProductionInfo(directors, writers, actors, isDarkMode),
              ],
            ),
          const SizedBox(height: 16),
          // 简介
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '简介',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建当前详情面板（基于currentDetail）
  Widget _buildCurrentDetailPanel(BuildContext context, bool isDarkMode) {
    final String title = currentDetail?.title ?? '暂无标题';
    final String cover = currentDetail?.poster ?? '';
    final String year = currentDetail?.year ?? '未知年份';
    final String summary = currentDetail?.desc ?? '暂无简介';
    final String? sourceName = currentDetail?.sourceName;
    final String? class_ = currentDetail?.class_;
    final List<String> episodes = currentDetail?.episodes ?? [];
    final int totalEpisodes = episodes.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主要信息区域
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧封面
              _buildCoverImage(context, cover, currentDetail?.source, isDarkMode),
              const SizedBox(width: 16),
              // 右侧信息
              Expanded(
                child: SizedBox(
                  height: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // 标题
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // 底部信息区域
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (sourceName != null && sourceName.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: isDarkMode
                                        ? Colors.grey[600]!
                                        : Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sourceName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDarkMode
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            year,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (totalEpisodes > 1)
                            Text(
                              '全$totalEpisodes集',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 分类信息
          if (class_ != null && class_.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '分类',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: class_
                      .split(',')
                      .map((category) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.grey[700]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              category.trim(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDarkMode
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // 简介
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '简介',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, String cover, String? source, bool isDarkMode) {
    return SizedBox(
      width: 120,
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: cover.isNotEmpty
            ? FutureBuilder<String>(
                future: getImageUrl(cover, source),
                builder: (context, snapshot) {
                  final String imageUrl = snapshot.data ?? cover;
                  final headers = getImageRequestHeaders(imageUrl, source);

                  return CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: 120,
                    height: 160,
                    cacheKey: imageUrl,
                    httpHeaders: headers,
                    memCacheWidth: (120 * MediaQuery.of(context).devicePixelRatio).round(),
                    memCacheHeight: (160 * MediaQuery.of(context).devicePixelRatio).round(),
                    placeholder: (context, url) => Container(
                      width: 120,
                      height: 160,
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 120,
                      height: 160,
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                      child: const Icon(Icons.movie, size: 50),
                    ),
                    fadeInDuration: const Duration(milliseconds: 200),
                    fadeOutDuration: const Duration(milliseconds: 100),
                  );
                },
              )
            : Container(
                width: 120,
                height: 160,
                color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                child: const Icon(Icons.movie, size: 50),
              ),
      ),
    );
  }

  Widget _buildStarRating(String rate, bool isDarkMode) {
    try {
      final rating = double.parse(rate);
      final double fiveStarRating = rating / 2.0;
      final int fullStars = fiveStarRating.floor();
      final bool hasHalfStar = (fiveStarRating - fullStars) >= 0.5;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          if (index < fullStars) {
            return const Icon(Icons.star, color: Colors.orange, size: 16);
          } else if (index == fullStars && hasHalfStar) {
            return Icon(Icons.star_half, color: Colors.grey[400], size: 16);
          } else {
            return Icon(Icons.star, color: Colors.grey[400], size: 16);
          }
        }),
      );
    } catch (e) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (index) => Icon(Icons.star, color: Colors.grey[400], size: 16),
        ),
      );
    }
  }

  Widget _buildProductionInfo(
    List<String> directors,
    List<String> writers,
    List<String> actors,
    bool isDarkMode,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (directors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
                children: [
                  const TextSpan(
                    text: '导演: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: directors.join(' / ')),
                ],
              ),
            ),
          ),
        if (writers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
                children: [
                  const TextSpan(
                    text: '编剧: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: writers.join(' / ')),
                ],
              ),
            ),
          ),
        if (actors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
                children: [
                  const TextSpan(
                    text: '主演: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: actors.join(' / ')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
