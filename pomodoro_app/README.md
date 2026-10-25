# 专注时光（松果）· 安卓 + macOS 端

Flutter 应用（**v1.3.13+14**），安卓与 macOS 桌面共用一套代码。
数据经**腾讯云同步后端**在两端互通（同码互通、本地优先）；网页端已于 2026-09-02 冻结。

> 项目级文档见 [`../docs/`](../docs/)；本文只讲本模块特有的内容。

## 功能

- 专注 / 短休息 / 长休息；**休息类型按本次实际专注时长**（≤70 分钟短休，>70 分钟长休，2026-10-09 起）
- 计划时长到点后**不自动结束**，继续累计并显示 `+MM:SS`，点「完成」才记录
- 专注完成后自动开始休息；重置丢弃当前会话、不写入统计；切换模式=挂起不打断
- **专注事件**：跨轮次累计容器（绑定任务 + 命名），记录带 `eventId`；改名（id 不变）/换绑/暂停/完成/删除只解除关联；
  统计页「事件进展」+ 独立「事件档案」（汇总 / 按任务构成 / 按时长排序）
- 日程：8 天排程可粘贴导入（`plan_import.dart`），多日分组 + 打勾不计时；手机「今日日程」卡、桌面信息卡一行；
  散文/网页计划可用「AI 解析」交给服务端抽取（`plan_remote.dart`，密钥不在客户端）
- 考试倒计时（专注页与桌面信息卡；仅本机，不上云）
- 今日清单、手动补记（可选过去任意日期）；全部记录可改时长/完成时刻/归属事件
- 统计页：周堆叠柱状图（自绘 `BrickBars`）、本月回顾（可翻月）、事件进展、任务构成、连续天数
- 今日目标（分钟，旧「次」数据自动迁移）、本周目标（次）；番茄 = 每 50 分钟 1 个（40 分钟进位）
- 结束通知 + 三音提示音；安卓前台服务常驻通知（锁屏倒计时，系统 Chronometer 渲染）；
  macOS 菜单栏显示已专注时长（离屏位图白字）+ 悬浮置顶计时窗（可跨全屏显示，见 `macos/Runner/FloatingTimerPanel.swift`）
- 云端同步：完成专注**必达上传** + 本地改动 20s 节流上传 + 前台上拉/巡检；冲突 409 弹窗（绝不静默覆盖）
- UI：**方案 E「松林手帐」**（仅浅色），令牌在 `lib/src/theme.dart`，规格见 [`../docs/design/`](../docs/design/)

## 数据与同步

- 本机数据存 `shared_preferences`，键 `pine-pomodoro`（兼容旧键 `pomodoro_data`）
- 同步后端：腾讯云 SCF + COS，地址常量在 `lib/src/cloud_sync.dart` 的 `CloudSync.defaultBaseUrl`
- 上传净荷剔除进行中会话、同步状态与考试倒计时；records / events 合并**按 id 并集**
- 冲突用 `baseUpdatedAt` + 409 检测；采用云端前自动写本机安全副本（`pine-safety-copy-*`，保留 3 份）
- 详细约定见 [`../docs/05-数据流与接口约定.md`](../docs/05-数据流与接口约定.md)

## 构建

工具链位于仓库根目录 `tools/`（Flutter 3.47.1、JDK 17、Android SDK，不随 Git 提交）。

```bash
export JAVA_HOME="$PWD/../tools/jdk/jdk-17.0.13.jdk"
F=$PWD/../tools/flutter/bin/flutter

$F pub get
../tools/flutter/bin/dart analyze    # flutter analyze 的 LSP 在本机会崩，用这个
$F --suppress-analytics test         # 179 项用例 / 23 个文件，应全绿
$F build apk --release --target-platform android-arm64   # 约 19MB
```

> `--suppress-analytics` 必须带：遥测日志写 `~/.dart-tool/`，受限环境下会在**成功之后**以 exit 1 退出。
> `flutter build apk` 需要可写 `~/.gradle`（Gradle wrapper 的 `.zip.lck`），否则报成"网络错误"。

产物：`build/app/outputs/flutter-apk/app-release.apk`（约 19.6MB；**以 `arm64-v8a` 为主**，
`armeabi-v7a` / `x86_64` 里只有两个几 KB 的存根库，不构成真机兼容）。

- 安装：`../tools/android-sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk`
- **release 当前使用 debug 签名**（本地分发），上架前需换正式签名
- macOS 桌面版：`bash ../scripts/build-macos.sh`（一条命令完成副本→pod→构建→归档→安装→重启；
  手工步骤与**Release 沙箱必须关闭**见 [`../docs/03`](../docs/03-环境搭建与常用命令.md)）

## 真机注意事项（OPPO Find X9 Pro / ColorOS）

- 首次安装需允许「安装未知应用」
- 开启提醒后，进「后台常驻通知」把应用加入电池优化白名单
- 锁屏倒计时由系统 Chronometer 渲染，进程被冻结时仍在走表；但通知到达可能受系统冻结影响，必要时加自启动白名单

## 已知限制

- `path_provider_android` 固定 2.2.23（2.3.x 的 `jni` 模块会写坏 pub 缓存），勿升级
- 深色模式未设计（`ThemeMode.light` 刻意固定），启动屏已用 `values-night` 统一米黄底
- macOS 到点提醒尚未实机验证（菜单栏/悬浮窗已验收）
