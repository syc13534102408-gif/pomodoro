# 专注时光（松果）· 安卓 + macOS 端

网页端番茄钟的 Flutter 移植版（v1.1.0+3），安卓与 macOS 桌面共用一套代码。
数据与网页端通过**腾讯云同步后端**互通（同码互通，本地优先）。

> 项目级文档见 [`../docs/`](../docs/)；本文只讲本模块特有的内容。

## 功能

- 专注 / 短休息 / 长休息，**每第 4 个番茄**自动进入长休息
- 计划时长到点后**不自动结束**，继续累计并显示 `+MM:SS`，点「完成」才记录
- 专注完成后自动开始休息；重置丢弃当前会话、不写入统计
- 专注事件管理（增删改、配色、删除不影响历史统计）、今日清单、手动补记
- 统计页：周堆叠柱状图（自绘 `BrickBars`）、本月回顾、事件构成、连续天数
- 今日目标（分钟，旧「次」数据自动迁移）、本周目标（次）
- 结束通知 + 三音提示音；安卓前台服务常驻通知（锁屏倒计时，系统 Chronometer 渲染）
- 云端同步：手动上传/恢复 + 自动同步 + 冲突弹窗（绝不静默覆盖）
- UI：方案 D「扁平积木」（仅浅色），规格见 [`../docs/design/`](../docs/design/)

## 数据与同步

- 本机数据存 `shared_preferences`，键 `pine-pomodoro`（兼容旧键 `pomodoro_data`）
- 同步后端：腾讯云 SCF + COS，地址常量在 `lib/src/cloud_sync.dart` 的 `CloudSync.defaultBaseUrl`
  （与网页端 `index.html` 的 `DEFAULT_SYNC_URL` 必须保持一致，改其一必改其二）
- 上传净荷剔除进行中会话与同步状态本身；冲突用 `baseUpdatedAt` + 409 检测
- 详细约定见 [`../docs/05-数据流与接口约定.md`](../docs/05-数据流与接口约定.md)

## 构建

工具链位于仓库根目录 `tools/`（Flutter 3.47.1、JDK 17、Android SDK，不随 Git 提交）。

```bash
export JAVA_HOME="$PWD/../tools/jdk/jdk-17.0.13.jdk"
F=$PWD/../tools/flutter/bin/flutter

$F pub get
../tools/flutter/bin/dart analyze    # flutter analyze 的 LSP 在本机会崩，用这个
$F test                              # 25 项，应全绿
$F build apk --release --target-platform android-arm64   # 约 19MB
```

产物：`build/app/outputs/flutter-apk/app-release.apk`（仅 `arm64-v8a`）。

- 安装：`../tools/android-sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk`
- **release 当前使用 debug 签名**（本地分发），上架前需换正式签名
- macOS 桌面版：`$F build macos --release`（需 CocoaPods；**Release 沙箱保持关闭**，见
  [`../docs/03`](../docs/03-环境搭建与常用命令.md)）

## 真机注意事项（OPPO Find X9 Pro / ColorOS）

- 首次安装需允许「安装未知应用」
- 开启提醒后，进「后台常驻通知」把应用加入电池优化白名单
- 锁屏倒计时由系统 Chronometer 渲染，进程被冻结时仍在走表；但通知到达可能受系统冻结影响，必要时加自启动白名单

## 已知限制

- `path_provider_android` 固定 2.2.23（2.3.x 的 `jni` 模块会写坏 pub 缓存），勿升级
- 深色模式未设计（`ThemeMode.light` 刻意固定），启动屏已用 `values-night` 统一米黄底
- 网页端与本端的云净荷 schema 不完全一致，靠缺省补齐；统一 schema 是未做事项
