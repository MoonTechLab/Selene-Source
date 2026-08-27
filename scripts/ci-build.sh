#!/bin/bash
# Selene CI 构建脚本
# 自动检测输出路径、依赖版本，减少上游变更导致的 CI 挂掉

set -e

PLATFORM="$1"
if [ -z "$PLATFORM" ]; then
  echo "Usage: $0 <linux|android|ios|macos>"
  exit 1
fi

log() { echo -e "\033[1;34m[CI]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

# 从 pubspec.yaml 读版本
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d'+' -f1)
log "Version: $VERSION"

# 通用：查找构建产物（递归搜索，不硬编码路径）
find_artifact() {
  local pattern="$1"
  local found
  found=$(find build -name "$pattern" -type f 2>/dev/null | head -1)
  if [ -z "$found" ]; then
    # 尝试目录
    found=$(find build -name "$pattern" -type d 2>/dev/null | head -1)
  fi
  echo "$found"
}

build_linux() {
  log "Building Linux..."
  flutter build linux --release

  # 动态查找 bundle 目录和可执行文件
  local bundle_dir
  bundle_dir=$(find build/linux -name "bundle" -type d 2>/dev/null | head -1)
  [ -z "$bundle_dir" ] && err "Cannot find Linux bundle directory"

  local binary
  binary=$(find "$bundle_dir" -maxdepth 1 -type f -executable 2>/dev/null | head -1)
  [ -z "$binary" ] && err "Cannot find Linux binary in $bundle_dir"

  log "Found binary: $binary"
  cd "$bundle_dir"
  tar czf "selene-linux.tar.gz" "$(basename "$binary")"
  log "Packed: selene-linux.tar.gz"
}

build_android() {
  log "Building Android..."
  
  # 动态读取 NDK 版本（从 build.gradle 或 local.properties）
  local ndk_version
  ndk_version=$(grep -oP 'ndkVersion\s*=\s*"\K[^"]+' android/app/build.gradle 2>/dev/null || \
                grep -oP 'ndk\.version\s*=\s*\K\S+' android/local.properties 2>/dev/null || \
                echo "")
  
  if [ -n "$ndk_version" ]; then
    log "NDK version from project: $ndk_version"
    yes | sdkmanager --licenses 2>/dev/null || true
    sdkmanager --install "ndk;$ndk_version" 2>/dev/null || true
  fi

  flutter build apk --release \
    --split-per-abi \
    --obfuscate \
    --split-debug-info=build/app/outputs/symbols \
    --target-platform android-arm64,android-arm

  log "Android APKs:"
  ls -la build/app/outputs/flutter-apk/*.apk 2>/dev/null
}

build_ios() {
  log "Building iOS..."
  flutter build ios --release --no-codesign

  local app_dir
  app_dir=$(find build/ios -name "Runner.app" -type d 2>/dev/null | head -1)
  [ -z "$app_dir" ] && err "Cannot find Runner.app"

  cd "$(dirname "$app_dir")"
  mkdir -p Payload
  cp -r Runner.app Payload/
  zip -r "../../../selene-ios.ipa" Payload/
  rm -rf Payload
  log "Packed: selene-ios.ipa"
}

build_macos() {
  log "Building macOS..."
  flutter build macos --release

  local app_dir
  app_dir=$(find build/macos -name "selene.app" -o -name "Selene.app" -o -name "Runner.app" 2>/dev/null | head -1)
  [ -z "$app_dir" ] && err "Cannot find macOS .app"

  hdiutil create -volname "Selene" \
    -srcfolder "$app_dir" \
    -ov -format UDZO \
    selene-macos.dmg
  log "Packed: selene-macos.dmg"
}

case "$PLATFORM" in
  linux)   build_linux ;;
  android) build_android ;;
  ios)     build_ios ;;
  macos)   build_macos ;;
  *)       err "Unknown platform: $PLATFORM" ;;
esac

log "Done: $PLATFORM"
