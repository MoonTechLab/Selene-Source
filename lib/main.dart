import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/user_data_service.dart';
import 'services/api_service.dart';
import 'services/theme_service.dart';
import 'services/douban_cache_service.dart';
import 'services/local_mode_storage_service.dart';
import 'services/subscription_service.dart';
import 'dart:io' show Platform;
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:media_kit/media_kit.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit (用于 PC 端播放器)
  MediaKit.ensureInitialized();

  // 初始化 macOS 窗口配置
  if (Platform.isMacOS) {
    await WindowManipulator.initialize(enableWindowDelegate: true);
    // 设置标题栏为透明，让菜单栏颜色跟随主题
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.enableFullSizeContentView();
    // 隐藏标题栏中的 Title
    await WindowManipulator.hideTitle();
  }

  // 初始化豆瓣缓存服务
  final cacheService = DoubanCacheService();
  await cacheService.init();

  // 启动定期清理
  cacheService.startPeriodicCleanup();

  runApp(const HeinTVApp());

  // 初始化 Windows 窗口配置
  if (Platform.isWindows) {
    doWhenWindowReady(() {
      final win = appWindow;
      const initialSize = Size(1024, 600);
      const minSize = Size(1024, 600);
      win.minSize = minSize;
      win.size = initialSize;
      win.alignment = Alignment.center;
      win.title = "HeinTV";
      win.show();
    });
  }
}

class HeinTVApp extends StatelessWidget {
  const HeinTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeService(),
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'HeinTV',
            debugShowCheckedModeBanner: false,
            theme: themeService.lightTheme,
            darkTheme: themeService.darkTheme,
            themeMode: themeService.themeMode,
            home: const AppWrapper(),
            builder: (context, child) {
              // 为 Windows 平台改善字体渲染
              if (Platform.isWindows) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: child!,
                );
              }
              return child!;
            },
          );
        },
      ),
    );
  }
}

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() async {
    try {
      // 检查是否是本地模式
      final isLocalMode = await UserDataService.getIsLocalMode();

      if (isLocalMode) {
        // 本地模式：尝试刷新订阅内容
        try {
          final subscriptionUrl =
              await LocalModeStorageService.getSubscriptionUrl();
          if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
            final response = await http.get(Uri.parse(subscriptionUrl));
            if (response.statusCode == 200) {
              final content =
                  await SubscriptionService.parseSubscriptionContent(
                      response.body);
              if (content != null) {
                if (content.searchResources != null && content.searchResources!.isNotEmpty) {
                  await LocalModeStorageService.saveSearchSources(
                      content.searchResources!);
                }
                if (content.liveSources != null && content.liveSources!.isNotEmpty) {
                  await LocalModeStorageService.saveLiveSources(
                      content.liveSources!);
                }
              }
            }
          }
        } catch (e) {
          // 刷新失败也继续进入首页
        }

        // 无论刷新成功与否，都进入首页
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      }

      // 检查是否有自动登录所需的数据
      final hasAutoLoginData = await UserDataService.hasAutoLoginData();

      if (!hasAutoLoginData) {
        // 如果没有自动登录数据，直接进入登录页
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // 服务器模式：尝试自动登录
      final loginResult = await ApiService.autoLogin();

      if (mounted) {
        if (loginResult.success) {
          // 自动登录成功，进入首页
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          // 自动登录失败，进入登录页
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // 发生异常，进入登录页
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return Scaffold(
            body: Container(
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
                          Color(0xFFe6f3fb),
                          Color(0xFFeaf3f7),
                          Color(0xFFf7f7f3),
                          Color(0xFFe9ecef),
                          Color(0xFFdbe3ea),
                          Color(0xFFd3dde6),
                        ],
                        stops: [0.0, 0.18, 0.38, 0.60, 0.80, 1.0],
                      ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                          themeService.isDarkMode
                              ? const Color(0xFFffffff)
                              : const Color(0xFF2c3e50)),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '正在检查登录状态...',
                      style: TextStyle(
                        fontSize: 16,
                        color: themeService.isDarkMode
                            ? const Color(0xFFffffff)
                            : const Color(0xFF2c3e50),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return const LoginScreen();
  }
}
