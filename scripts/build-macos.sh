#!/bin/bash
# macOS 出包 + 安装一体脚本（含 .symlinks/Pods 修复，rsync 后必须执行）
set -e
export LANG=en_US.UTF-8
F=~/Documents/Codex/2026-08-13/pinecone/tools/flutter/bin/flutter
OUT=~/Documents/Codex/2026-08-13/pinecone/outputs
APP=~/Documents/Codex/2026-08-13/pinecone/pomodoro_app

rsync -a --delete --exclude build --exclude .dart_tool --exclude .gradle \
  "$APP/" /tmp/pine-macos/

# 重建插件符号链接（rsync --delete 会用工作区可能缺失的版本覆盖）
python3 - <<'PYEOF'
import json, os
dep = json.load(open('/tmp/pine-macos/.flutter-plugins-dependencies'))
base = '/tmp/pine-macos/macos/.symlinks/plugins'
os.makedirs(base, exist_ok=True)
for p in dep['plugins']['macos']:
    dst = os.path.join(base, p['name'])
    if os.path.lexists(dst): os.remove(dst)
    os.symlink(os.path.abspath(p['path']), dst)
print('symlinks:', len(dep['plugins']['macos']), '个已重建')
PYEOF

# 清掉上次构建的 DerivedData 缓存：Xcode/SDK 升级后旧 .pcm 预编译模块
# 会全部失效（报 "module file not found"），增量缓存反而变成污染源。
# 全量编译多花 1-2 分钟，换稳定。
rm -rf /tmp/pine-macos/build

cd /tmp/pine-macos/macos
/opt/homebrew/bin/pod install >/dev/null 2>&1
cd /tmp/pine-macos

# 依赖已在本机 pub-cache 里时，不联网解析——2026-10-25 有一次 pub.dev 域名解析失败，
# 整轮打包白跑。先离线 pub get，再让 build 跳过隐式 pub get。
"$F" pub get --offline >/dev/null 2>&1 || "$F" pub get >/dev/null
"$F" build macos --release --no-pub

cd /tmp/pine-macos
ditto -c -k --sequesterRsrc --keepParent "build/macos/Build/Products/Release/pinecore.app" \
  "$OUT/pinecore-macos-$(date +%F).zip"

# 直接安装到「应用程序」并重启新版（数据在 ~/Library/Preferences，不受影响）
# 同时匹配新旧可执行名：产物名改过，旧实例（产物名改动之前的构建）可执行名仍是 pomodoro_app，
# 只杀 pomodoro_app 或只杀 pinecore 都会漏，导致两个实例同时跑、两个菜单栏计时器。
pkill -f "MacOS/(pinecore|pomodoro_app)" 2>/dev/null || true
sleep 2
rsync -a --delete build/macos/Build/Products/Release/pinecore.app/ \
  "/Applications/pinecore.app/"
open "/Applications/pinecore.app"
echo "✅ 完成：新包已构建、归档并安装到 /Applications 后启动"
