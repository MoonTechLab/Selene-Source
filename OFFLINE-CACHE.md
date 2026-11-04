# Selene 离线缓存版（Fork）

本仓库 fork 自 [MoonTechLab/Selene-Source](https://github.com/MoonTechLab/Selene-Source)，
在原作者代码基础上**新增了「手机本地离线缓存 + 离线观看」功能**。

- 原作者仓库：https://github.com/MoonTechLab/Selene-Source
- 本项目（fork）：https://github.com/daiwenwen3/Selene-Source
- 基础提交：`9ad75545be1ef112ba9a44a8d1022219aef4a597`（上游 `main`）

> 上游 `MoonTechLab/Selene` 只是发布仓库（仅 README），真实源码在 `Selene-Source`。

---

## 一、这个版本加了什么

### 1. 本地离线缓存

- 在**选集界面**直接点某一集右下角的下载图标即可缓存该集
- 支持**一键缓存全集**（逐集排队，不会同时开几十个连接）
- 支持 AES-128 加密的 HLS（自动取 key、按 RFC 8216 推导 IV、处理 key 轮换）
- 支持 `#EXT-X-BYTERANGE`、fMP4（`#EXT-X-MAP`）
- 断点续传：中断后重进 app 可继续，已完成分片不重复下载

### 2. 离线观看

- 「我的下载」按**剧集分组**展示，一部剧一张卡片，可展开看逐集
- 播放时自动优先使用本地文件（`media_kit` + `file://`）
- **飞行模式下冷启动也能进 app**：登录请求打不通但本地有旧 cookie 时，
  不再把用户挡在登录页

### 3. 性能

- HLS 分片 AES 解密改用 **T 表实现**，700KB 分片从 995ms 降到 5.7ms
- 下载进度落盘与 UI 通知节流，缓存时界面不再卡顿
- 索引数据模型与 IO 分离（`offline_models.dart`），可脱离 Flutter 单测

---

## 二、改动清单

### 新增文件

```
lib/services/offline_aes.dart               AES-128-CBC 解密（零依赖自实现）
lib/services/offline_models.dart            数据模型 + 分组聚合（纯 Dart）
lib/services/offline_m3u8_parser.dart       HLS 播放列表解析
lib/services/offline_storage_service.dart   缓存索引持久化
lib/services/offline_download_service.dart  下载核心（并发/续传/解密）
lib/services/offline_manager.dart           门面 + ChangeNotifier
lib/screens/downloads_screen.dart           「我的下载」按剧集分组
```

### 修改文件

| 文件 | 改动 |
| --- | --- |
| `lib/main.dart` | 初始化 `OfflineManager`；离线启动分支 |
| `lib/services/api_service.dart` | 新增 `autoLoginEx()`，区分「网络不可达」与「凭据被拒」 |
| `lib/screens/player_screen.dart` | 选集卡片缓存角标、缓存全集、离线优先播放、`initialEpisode` 参数 |
| `lib/widgets/player_episodes_panel.dart` | 面板内每集缓存按钮、缓存全集入口 |
| `lib/widgets/user_menu.dart` | 菜单项「我的下载」 |

### 测试

`tools_test/` 下的逻辑测试**不依赖 Flutter**，可直接 `dart run`：

```bash
cd tools_test
node gen_pc.js                                  # 生成 package_config
dart run test_offline_aes.dart                  # NIST/FIPS 官方 AES 向量
dart run test_offline_aes_diff.dart             # T 表 vs 参考实现交叉验证
dart run test_offline_m3u8.dart                 # 播放列表解析 26 项
dart run test_offline_grouping.dart             # 下载页分组聚合
node gen_hls_fixture.js && dart run test_hls_pipeline.dart   # 端到端解密
```

---

## 三、构建

### 环境要求

Flutter 会校验工具链最低版本，上游配置需要调整才能构建：

| 位置 | 上游 | 需要改成 |
| --- | --- | --- |
| `android/gradle/wrapper/gradle-wrapper.properties` | 8.12 | **8.14** |
| `android/settings.gradle.kts` AGP | 8.9.1 | **8.11.1** |
| `android/settings.gradle.kts` Kotlin | 2.1.0 | **2.2.20** |

> `android/local.properties` 未提交（含本机 SDK 路径），首次构建时 Flutter 会自动生成。

### 命令

```bash
flutter pub get
flutter build apk --release --target-platform=android-arm64 --split-per-abi
```

### 签名

沿用上游行为：缺 `android/key.properties` 时回退到 **debug 签名**。
因此不能覆盖安装官方正式包（签名不同），需要先卸载。

---

## 四、已构建的 APK

见本仓库 [Releases](../../releases) 页面。

| 版本 | 包名 | 说明 |
| --- | --- | --- |
| 标准版 | `org.moontechlab.selene` | 与官方版包名相同，需先卸载官方版 |
| 共存版 | `org.moontechlab.selene.coexist` | 桌面名「Selene 离线版」，可与官方版同时安装 |

两个版本功能一致，共存版仅 `applicationId` 加 `.coexist` 后缀。

---

## 五、已知限制

- **不支持 `SAMPLE-AES`**（付费 DRM），仅支持 `AES-128` 与未加密的 HLS
- 合并产物是分片顺序拼接的 `.ts` / fMP4；源站分片时间戳不连续时个别播放器可能跳帧
- 缓存位于 app 私有目录 `getApplicationDocumentsDirectory()/offline`，
  Android 11+ 免存储权限，**卸载 app 会一并清除**
- 纯离线模式下「换源」「搜索」「豆瓣详情」等联网区块仍会失败或为空
- 离线启动依赖上次成功登录留下的 cookie；若服务器 session 已过期且用户断网，
  仍可进首页看缓存，但联网后会被要求重新登录

---

## 六、许可与致谢

本仓库是 [MoonTechLab/Selene-Source](https://github.com/MoonTechLab/Selene-Source)
的衍生作品，**遵循原项目相同的许可协议**。原项目版权归原作者所有。

离线缓存功能的实现参考了 [MoonTV](https://github.com/daiwenwen3/MoonTV)
的 `src/lib/m3u8-downloader.ts` 算法思路（选档递归、AES key 处理、byte-range 分块）。
