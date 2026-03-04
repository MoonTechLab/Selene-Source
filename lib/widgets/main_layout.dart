import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:heintv/services/search_service.dart';
import 'package:heintv/services/user_data_service.dart';
import '../services/theme_service.dart';
import '../services/api_service.dart';
import '../utils/device_utils.dart';
import '../utils/font_utils.dart';
import 'user_menu.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'windows_title_bar.dart';

class MainLayout extends StatefulWidget {
  final Widget content;
  final int currentBottomNavIndex;
  final Function(int) onBottomNavChanged;
  final String selectedTopTab;
  final Function(String) onTopTabChanged;
  final bool isSearchMode;
  final VoidCallback? onSearchTap;
  final VoidCallback? onHomeTap;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final String? searchQuery;
  final Function(String)? onSearchQueryChanged;
  final Function(String)? onSearchSubmitted;
  final VoidCallback? onClearSearch;
  final bool showBottomNav;

  const MainLayout({
    super.key,
    required this.content,
    required this.currentBottomNavIndex,
    required this.onBottomNavChanged,
    required this.selectedTopTab,
    required this.onTopTabChanged,
    this.isSearchMode = false,
    this.onSearchTap,
    this.onHomeTap,
    this.searchController,
    this.searchFocusNode,
    this.searchQuery,
    this.onSearchQueryChanged,
    this.onSearchSubmitted,
    this.onClearSearch,
    this.showBottomNav = true,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isSearchButtonPressed = false;
  bool _showUserMenu = false;

  // 用于跟踪底部导航栏按钮的 hover 状态
  int? _hoveredNavIndex;

  // 用于跟踪搜索按钮的 hover 状态
  bool _isSearchButtonHovered = false;

  // 用于跟踪主题切换按钮的 hover 状态
  bool _isThemeButtonHovered = false;

  // 用于跟踪用户按钮的 hover 状态
  bool _isUserButtonHovered = false;

  // 用于跟踪返回按钮的 hover 状态
  bool _isBackButtonHovered = false;

  // 用于跟踪搜索框内清除按钮的 hover 状态
  bool _isClearButtonHovered = false;

  // 用于跟踪搜索框内搜索按钮的 hover 状态
  bool _isSearchSubmitButtonHovered = false;

  // 搜索建议相关状态
  List<String> _searchSuggestions = [];
  Timer? _debounceTimer;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _fetchSearchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _searchSuggestions = [];
            });
            _removeOverlay();
          }
        });
      }
      return;
    }

    final currentQuery = query;
    final isLocalMode = await UserDataService.getIsLocalMode();
    final isLocalSearch = await UserDataService.getLocalSearch();

    List<String> suggestionResults;
    if (isLocalMode || isLocalSearch) {
      suggestionResults = await SearchService.searchRecommand(query.trim());
    } else {
      suggestionResults = await ApiService.getSearchSuggestions(query.trim());
    }

    // 检查搜索框内容是否已变化
    if (!mounted ||
        widget.searchQuery != currentQuery ||
        suggestionResults.isEmpty) {
      return;
    }

    // 使用 post-frame callback 确保在正确的时机更新状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.searchQuery != currentQuery) {
        return;
      }

      if (suggestionResults.isNotEmpty) {
        setState(() {
          _searchSuggestions = suggestionResults.take(8).toList();
        });
        // 再次使用 post-frame callback 显示 overlay
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _searchSuggestions.isNotEmpty) {
            _showSuggestionsOverlay();
          }
        });
      } else {
        setState(() {
          _searchSuggestions = [];
        });
        _removeOverlay();
      }
    });
  }

  void _onSearchQueryChanged(String query) {
    // 使用 post-frame callback 来调用父组件回调，避免在 build 期间触发 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSearchQueryChanged?.call(query);
    });

    // 取消之前的防抖计时器
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      // 使用 post-frame callback 来清除建议
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _searchSuggestions = [];
          });
          _removeOverlay();
        }
      });
      return;
    }

    // 设置新的防抖计时器（500ms）
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && query == widget.searchQuery) {
        _fetchSearchSuggestions(query);
      }
    });
  }

  void _showSuggestionsOverlay() {
    _removeOverlay();

    if (_searchSuggestions.isEmpty) {
      return;
    }

    final themeService = Provider.of<ThemeService>(context, listen: false);
    final isTablet = DeviceUtils.isTablet(context);

    // 计算建议框宽度
    // 平板模式：屏幕宽度的 50%
    // 移动端：屏幕宽度 - 左右padding(32) - 右侧按钮宽度(32*2) - 按钮间距(12) - 按钮与搜索框间距(16)
    final screenWidth = MediaQuery.of(context).size.width;
    final suggestionWidth =
        isTablet ? screenWidth * 0.5 : screenWidth - 32 - 16 - 32 - 12 - 32;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: suggestionWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 42), // 紧贴搜索框
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: themeService.isDarkMode
                ? const Color(0xFF1e1e1e)
                : Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: _searchSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _searchSuggestions[index];
                  return InkWell(
                    onTap: () {
                      widget.searchController?.text = suggestion;
                      widget.onSearchSubmitted?.call(suggestion);
                      _removeOverlay();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.search,
                            size: 16,
                            color: themeService.isDarkMode
                                ? const Color(0xFF666666)
                                : const Color(0xFF95a5a6),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: FontUtils.poppins(
                                fontSize: 14,
                                color: themeService.isDarkMode
                                    ? const Color(0xFFffffff)
                                    : const Color(0xFF2c3e50),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Theme(
          data: themeService.isDarkMode
              ? themeService.darkTheme
              : themeService.lightTheme,
          child: Scaffold(
            resizeToAvoidBottomInset: !widget.isSearchMode,
            body: Stack(
              children: [
                // 主要内容区域
                Column(
                  children: [
                    // 主内容区域（包含header和content）
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: themeService.isDarkMode
                              ? const Color(0xFF000000) // 深色模式纯黑色
                              : null,
                          gradient: themeService.isDarkMode
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFe6f3fb), // 浅色模式渐变
                                    Color(0xFFeaf3f7),
                                    Color(0xFFf7f7f3),
                                    Color(0xFFe9ecef),
                                    Color(0xFFdbe3ea),
                                    Color(0xFFd3dde6),
                                  ],
                                  stops: [0.0, 0.18, 0.38, 0.60, 0.80, 1.0],
                                ),
                        ),
                        child: Column(
                          children: [
                            // Windows 自定义标题栏
                            if (Platform.isWindows)
                              WindowsTitleBar(
                                customBackgroundColor: widget.isSearchMode
                                    ? (themeService.isDarkMode
                                        ? const Color(0xFF121212)
                                        : const Color(0xFFf5f5f5))
                                    : null,
                              ),
                            // 固定 Header
                            _buildHeader(context, themeService),
                            // 主要内容区域
                            Expanded(
                              child: widget.content,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 底部导航栏（可选）
                    if (widget.showBottomNav) _buildBottomNavBar(themeService),
                  ],
                ),
                // 用户菜单覆盖层 - 现在会覆盖整个屏幕包括navbar
                if (_showUserMenu)
                  UserMenu(
                    isDarkMode: themeService.isDarkMode,
                    onClose: () {
                      setState(() {
                        _showUserMenu = false;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ThemeService themeService) {
    final isTablet = DeviceUtils.isTablet(context);

    // macOS 下需要额外的顶部 padding 来避免与透明标题栏重叠
    // Windows 下不需要额外 padding，因为自定义标题栏已经占据了空间
    final topPadding = DeviceUtils.isMacOS()
        ? MediaQuery.of(context).padding.top + 32
        : Platform.isWindows
            ? 8.0
            : MediaQuery.of(context).padding.top + 8;

    return Container(
      padding: EdgeInsets.only(
        top: topPadding,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: widget.isSearchMode
            ? themeService.isDarkMode
                ? const Color(0xFF121212)
                : const Color(0xFFf5f5f5)
            : themeService.isDarkMode
                ? const Color(0xFF1e1e1e).withOpacity(0.9)
                : Colors.white.withOpacity(0.8),
      ),
      child: widget.isSearchMode
          ? _buildSearchHeader(context, themeService, isTablet)
          : _buildNormalHeader(context, themeService),
    );
  }

  Widget _buildNormalHeader(BuildContext context, ThemeService themeService) {
    return SizedBox(
      height: 40, // 固定高度，与搜索框高度一致
      child: Stack(
        children: [
          // 左侧搜索图标
          Positioned(
            left: 0,
            top: 4,
            child: MouseRegion(
              cursor: DeviceUtils.isPC()
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onEnter: DeviceUtils.isPC()
                  ? (_) {
                      setState(() {
                        _isSearchButtonHovered = true;
                      });
                    }
                  : null,
              onExit: DeviceUtils.isPC()
                  ? (_) {
                      setState(() {
                        _isSearchButtonHovered = false;
                      });
                    }
                  : null,
              child: GestureDetector(
                onTap: () {
                  // 防止重复点击
                  if (_isSearchButtonPressed) return;

                  setState(() {
                    _isSearchButtonPressed = true;
                  });

                  widget.onSearchTap?.call();

                  // 延迟重置按钮状态，防止快速重复点击
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      setState(() {
                        _isSearchButtonPressed = false;
                      });
                    }
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DeviceUtils.isPC() && _isSearchButtonHovered
                        ? (themeService.isDarkMode
                            ? const Color(0xFF333333)
                            : const Color(0xFFe0e0e0))
                        : Colors.transparent,
                  ),
                  child: Center(
                    child: Icon(
                      LucideIcons.search,
                      color: themeService.isDarkMode
                          ? const Color(0xFFffffff)
                          : const Color(0xFF2c3e50),
                      size: 24,
                      weight: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 完全居中的 Logo
          Center(
            child: GestureDetector(
              onTap: widget.onHomeTap,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'HeinTV',
                style: FontUtils.sourceCodePro(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: themeService.isDarkMode
                      ? Colors.white
                      : const Color(0xFF2c3e50),
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          // 右侧按钮组
          Positioned(
            right: 0,
            top: 4,
            child: _buildRightButtons(themeService),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(
      BuildContext context, ThemeService themeService, bool isTablet) {
    final searchBoxWidget = CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        decoration: BoxDecoration(
          color:
              themeService.isDarkMode ? const Color(0xFF1e1e1e) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) {
              // 失焦时关闭建议框
              _removeOverlay();
            }
          },
          child: TextField(
            controller: widget.searchController,
            focusNode: widget.searchFocusNode,
            autofocus: false,
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.text,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: '搜索电影、剧集、动漫...',
              hintStyle: FontUtils.poppins(
                color: themeService.isDarkMode
                    ? const Color(0xFF666666)
                    : const Color(0xFF95a5a6),
                fontSize: 14,
              ),
              suffixIcon: SizedBox(
                width: isTablet ? 80 : 80, // 固定宽度确保按钮位置一致
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    // 搜索按钮 - 固定在右侧
                    Positioned(
                      right: isTablet ? 8 : 12,
                      child: MouseRegion(
                        cursor:
                            (widget.searchQuery?.trim().isNotEmpty ?? false) &&
                                    DeviceUtils.isPC()
                                ? SystemMouseCursors.click
                                : MouseCursor.defer,
                        onEnter: DeviceUtils.isPC() &&
                                (widget.searchQuery?.trim().isNotEmpty ?? false)
                            ? (_) {
                                setState(() {
                                  _isSearchSubmitButtonHovered = true;
                                });
                              }
                            : null,
                        onExit: DeviceUtils.isPC() &&
                                (widget.searchQuery?.trim().isNotEmpty ?? false)
                            ? (_) {
                                setState(() {
                                  _isSearchSubmitButtonHovered = false;
                                });
                              }
                            : null,
                        child: GestureDetector(
                          onTap:
                              (widget.searchQuery?.trim().isNotEmpty ?? false)
                                  ? () {
                                      _removeOverlay();
                                      widget.onSearchSubmitted
                                          ?.call(widget.searchQuery!);
                                    }
                                  : null,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.all(isTablet ? 6 : 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: DeviceUtils.isPC() &&
                                      _isSearchSubmitButtonHovered &&
                                      (widget.searchQuery?.trim().isNotEmpty ??
                                          false)
                                  ? (themeService.isDarkMode
                                      ? const Color(0xFF333333)
                                      : const Color(0xFFe0e0e0))
                                  : Colors.transparent,
                            ),
                            child: Icon(
                              LucideIcons.search,
                              color: (widget.searchQuery?.trim().isNotEmpty ??
                                      false)
                                  ? const Color(0xFF27ae60)
                                  : themeService.isDarkMode
                                      ? const Color(0xFFb0b0b0)
                                      : const Color(0xFF7f8c8d),
                              size: isTablet ? 18 : 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 清除按钮 - 在搜索按钮左侧（仅在有内容时显示）
                    Positioned(
                      right: isTablet ? 42 : 44,
                      child: Visibility(
                        visible: widget.searchQuery?.isNotEmpty ?? false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: MouseRegion(
                          cursor: DeviceUtils.isPC()
                              ? SystemMouseCursors.click
                              : MouseCursor.defer,
                          onEnter: DeviceUtils.isPC()
                              ? (_) {
                                  setState(() {
                                    _isClearButtonHovered = true;
                                  });
                                }
                              : null,
                          onExit: DeviceUtils.isPC()
                              ? (_) {
                                  setState(() {
                                    _isClearButtonHovered = false;
                                  });
                                }
                              : null,
                          child: GestureDetector(
                            onTap: () {
                              _removeOverlay();
                              widget.onClearSearch?.call();
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: EdgeInsets.all(isTablet ? 6 : 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    DeviceUtils.isPC() && _isClearButtonHovered
                                        ? (themeService.isDarkMode
                                            ? const Color(0xFF333333)
                                            : const Color(0xFFe0e0e0))
                                        : Colors.transparent,
                              ),
                              child: Icon(
                                LucideIcons.x,
                                color: themeService.isDarkMode
                                    ? const Color(0xFFb0b0b0)
                                    : const Color(0xFF7f8c8d),
                                size: isTablet ? 18 : 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              isDense: true,
            ),
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode
                  ? const Color(0xFFffffff)
                  : const Color(0xFF2c3e50),
              height: 1.2,
            ),
            onSubmitted: (value) {
              _removeOverlay();
              widget.onSearchSubmitted?.call(value);
            },
            onChanged: _onSearchQueryChanged,
            onTap: () {
              // 聚焦时如果有内容，显示建议
              if (widget.searchQuery?.trim().isNotEmpty ?? false) {
                _fetchSearchSuggestions(widget.searchQuery!);
              }
            },
          ),
        ),
      ),
    );

    // 平板模式下居中
    if (isTablet) {
      return SizedBox(
        height: 40, // 固定高度
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 左侧返回按钮
            Positioned(
              left: 0,
              child: MouseRegion(
                cursor: DeviceUtils.isPC()
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                onEnter: DeviceUtils.isPC()
                    ? (_) {
                        setState(() {
                          _isBackButtonHovered = true;
                        });
                      }
                    : null,
                onExit: DeviceUtils.isPC()
                    ? (_) {
                        setState(() {
                          _isBackButtonHovered = false;
                        });
                      }
                    : null,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DeviceUtils.isPC() && _isBackButtonHovered
                          ? (themeService.isDarkMode
                              ? const Color(0xFF333333)
                              : const Color(0xFFe0e0e0))
                          : Colors.transparent,
                    ),
                    child: Center(
                      child: Icon(
                        LucideIcons.arrowLeft,
                        color: themeService.isDarkMode
                            ? const Color(0xFFffffff)
                            : const Color(0xFF2c3e50),
                        size: 24,
                        weight: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 搜索框在整个屏幕水平居中
            Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.5,
                child: searchBoxWidget,
              ),
            ),
            // 右侧按钮 - 垂直居中
            Positioned(
              right: 0,
              child: _buildRightButtons(themeService),
            ),
          ],
        ),
      );
    }

    // 非平板模式下，搜索框居左，右侧留出按钮空间
    return SizedBox(
      height: 40, // 固定高度
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: searchBoxWidget),
          const SizedBox(width: 16),
          _buildRightButtons(themeService),
        ],
      ),
    );
  }

  Widget _buildRightButtons(ThemeService themeService) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 深浅模式切换按钮
        MouseRegion(
          cursor:
              DeviceUtils.isPC() ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: DeviceUtils.isPC()
              ? (_) {
                  setState(() {
                    _isThemeButtonHovered = true;
                  });
                }
              : null,
          onExit: DeviceUtils.isPC()
              ? (_) {
                  setState(() {
                    _isThemeButtonHovered = false;
                  });
                }
              : null,
          child: GestureDetector(
            onTap: () {
              themeService.toggleTheme(context);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DeviceUtils.isPC() && _isThemeButtonHovered
                    ? (themeService.isDarkMode
                        ? const Color(0xFF333333)
                        : const Color(0xFFe0e0e0))
                    : Colors.transparent,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: child,
                    );
                  },
                  child: Icon(
                    themeService.isDarkMode
                        ? LucideIcons.sun
                        : LucideIcons.moon,
                    key: ValueKey(themeService.isDarkMode),
                    color: themeService.isDarkMode
                        ? const Color(0xFFffffff)
                        : const Color(0xFF2c3e50),
                    size: 24,
                    weight: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 用户按钮
        MouseRegion(
          cursor:
              DeviceUtils.isPC() ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: DeviceUtils.isPC()
              ? (_) {
                  setState(() {
                    _isUserButtonHovered = true;
                  });
                }
              : null,
          onExit: DeviceUtils.isPC()
              ? (_) {
                  setState(() {
                    _isUserButtonHovered = false;
                  });
                }
              : null,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showUserMenu = true;
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DeviceUtils.isPC() && _isUserButtonHovered
                    ? (themeService.isDarkMode
                        ? const Color(0xFF333333)
                        : const Color(0xFFe0e0e0))
                    : Colors.transparent,
              ),
              child: Center(
                child: Icon(
                  LucideIcons.user,
                  color: themeService.isDarkMode
                      ? const Color(0xFFffffff)
                      : const Color(0xFF2c3e50),
                  size: 24,
                  weight: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar(ThemeService themeService) {
    final List<Map<String, dynamic>> navItems = [
      {'icon': LucideIcons.house, 'label': '首页'},
      {'icon': LucideIcons.video, 'label': '电影'},
      {'icon': LucideIcons.tv, 'label': '剧集'},
      {'icon': LucideIcons.cat, 'label': '动漫'},
      {'icon': LucideIcons.clover, 'label': '综艺'},
      {'icon': LucideIcons.radio, 'label': '直播'},
    ];

    final isTablet = DeviceUtils.isTablet(context);

    return Container(
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? const Color(0xFF1e1e1e).withOpacity(0.9)
            : Colors.white.withOpacity(0.9),
        border: Border(
          top: BorderSide(
            color: themeService.isDarkMode
                ? const Color(0xFF333333).withOpacity(0.3)
                : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        left: 0,
        right: 0,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8, // 手动处理底部安全区域
      ),
      child: Row(
        mainAxisAlignment:
            isTablet ? MainAxisAlignment.center : MainAxisAlignment.spaceEvenly,
        children: [
          // 平板模式下添加左侧空白
          if (isTablet) const Spacer(flex: 3),

          // 导航按钮
          ...navItems.asMap().entries.expand((entry) {
            int index = entry.key;
            Map<String, dynamic> item = entry.value;
            bool isSelected =
                !widget.isSearchMode && widget.currentBottomNavIndex == index;
            bool isHovered = DeviceUtils.isPC() && _hoveredNavIndex == index;

            return [
              MouseRegion(
                cursor: DeviceUtils.isPC()
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                onEnter: DeviceUtils.isPC()
                    ? (_) {
                        setState(() {
                          _hoveredNavIndex = index;
                        });
                      }
                    : null,
                onExit: DeviceUtils.isPC()
                    ? (_) {
                        setState(() {
                          _hoveredNavIndex = null;
                        });
                      }
                    : null,
                child: GestureDetector(
                  onTap: () {
                    widget.onBottomNavChanged(index);
                  },
                  behavior: HitTestBehavior.opaque, // 确保整个区域都可以点击
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 16 : 12,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item['icon'],
                          color: isSelected
                              ? const Color(0xFF27ae60)
                              : isHovered
                                  ? const Color(0xFF52c77a) // hover 时的浅绿色
                                  : themeService.isDarkMode
                                      ? const Color(0xFFb0b0b0)
                                      : const Color(0xFF7f8c8d),
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['label'],
                          style: FontUtils.poppins(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected
                                ? const Color(0xFF27ae60)
                                : isHovered
                                    ? const Color(0xFF52c77a) // hover 时的浅绿色
                                    : themeService.isDarkMode
                                        ? const Color(0xFFb0b0b0)
                                        : const Color(0xFF7f8c8d),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 平板模式下在按钮之间添加间距
              if (isTablet && index < navItems.length - 1)
                const SizedBox(width: 36),
            ];
          }),

          // 平板模式下添加右侧空白
          if (isTablet) const Spacer(flex: 3),
        ],
      ),
    );
  }
}
