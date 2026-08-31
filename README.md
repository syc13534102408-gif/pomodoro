# pomodoro

GitHub Pages deployment files are in the repository root. Open the Pages settings and publish the `main` branch from `/ (root)`.

## 同步后端现状

- **云端同步**（上传/恢复/自动同步）：腾讯云 SCF + COS，函数 URL：
  `https://1478270344-dtbqag7t8b.ap-guangzhou.tencentscf.com`（国内网络可直连）。
  代码在 `tencent-sync/`，部署见 `tencent-sync/README.md`，函数地址已写入 `tencent-sync/.last-url`。
- **后台提醒**（Web Push）：仍走 Cloudflare Worker（Durable Objects 精确定时），与同步地址相互独立。
- 网页端与安卓端的同步服务地址分别是 `index.html` 的 `DEFAULT_SYNC_URL` 与
  `pomodoro_app/lib/src/cloud_sync.dart` 的 `CloudSync.defaultBaseUrl`。

## 安卓 APK 构建（本机已知问题）

工作区目录存在删除/写入保护，`flutter build apk` 在 `.dart_tool/hooks_runner` 和 `build/reports`
处会报 `Unable to open file ... for writing snapshot` / `Operation not permitted`，**无解（环境限制）**。

绕法：把工程复制到 `/tmp` 再构建（SDK 路径在 `android/local.properties` 里指向本项目的 `tools/`，复制后无需改动）：

```bash
rm -rf /tmp/pine-app && mkdir -p /tmp/pine-app
rsync -a --exclude build --exclude .dart_tool --exclude .gradle pomodoro_app/ /tmp/pine-app/
cd /tmp/pine-app
/path/to/wo-xi/tools/flutter/bin/flutter build apk --release --split-per-abi
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```
