#!/bin/bash
# 编译并打包 一次便签 (oncenotes), 安装到 /Applications
#
# 命名约定:
#   显示名(包名)  = 一次便签.app     ← Finder 里看到的
#   技术名        = oncenotes        ← 可执行文件/进程名/bundle id
#   SwiftPM target 仍叫 StickyNotes  ← 改动最小, 对外不可见
set -e
cd "$(dirname "$0")"

BUNDLE_NAME="一次便签"           # 装到 /Applications 下的名字 (Finder 显示这个)
TECH_NAME="oncenotes"             # 可执行文件 / 进程名
LEGACY_NAMES=("StickyNotes")      # 历史包名, 安装时清掉

echo "==> 编译 (release)..."
swift build -c release

APP="build/$BUNDLE_NAME.app"
echo "==> 打包 $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/StickyNotes "$APP/Contents/MacOS/$TECH_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> 签名 (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "==> 安装到 /Applications ..."
pkill -x "$TECH_NAME" 2>/dev/null || true
for old in "${LEGACY_NAMES[@]}"; do pkill -x "$old" 2>/dev/null || true; done
sleep 0.5
# 清掉历史安装与同义包, 免得两个 App 抢同一个 stickynotes:// 协议
for old in "${LEGACY_NAMES[@]}" "$TECH_NAME"; do rm -rf "/Applications/$old.app"; done
rm -rf "/Applications/$BUNDLE_NAME.app"
cp -R "$APP" /Applications/

echo "✅ 完成! 运行: open '/Applications/$BUNDLE_NAME.app'"
