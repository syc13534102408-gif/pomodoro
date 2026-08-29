# 专注时光（松果）Android 端

网页端番茄钟的 Flutter 移植版，功能与网页端对齐，数据与网页端通过 Cloudflare Worker 互通。

## 功能

- 专注 / 短休息 / 长休息，第 4、8、12 次专注后自动进入长休息
- 计划时长到点后**不自动结束**，继续累计专注时长并显示 `+MM:SS`，点击「完成并开始休息」才记录
- 专注完成后自动开始休息；休息结束回到专注但不自动开始
- 重置丢弃当前会话，不写入统计
- 专注事件管理：新增、重命名、改色、删除（删除不影响历史统计）
- 每日 To-do 清单，长按照项可一键设为当前专注事件
- 手动补记已完成事件；最近完成记录可删除
- 统计页：周一到周日柱状图，同一天按任务颜色堆叠，含图例与事件分布
- 今日目标、本周目标、连续专注天数
- 结束通知 + 三音提示音
- 安卓前台服务常驻通知：锁屏与后台可见剩余时间，进程被杀后可自动恢复
- 云端同步：与网页端共用一个同步码，支持上传、恢复与冲突检测
- 单一会话状态机，不会出现两个「进行中」

## 数据与同步

- 本机数据存 `shared_preferences`，键为 `pine-pomodoro`
- 记录结构与网页端一致：记录用任务名关联，状态为 `in_progress / completed / manual / paused / interrupted`
- 云端同步地址：`https://pine-pomodoro-reminders.pine-pomodoro-reminders.workers.dev`
- 上传会剔除推送订阅与进行中会话；恢复会保留本机的这两项

## 构建

工具链位于仓库根目录 `tools/`（Flutter、JDK 17、Android SDK 不随 Git 提交）。

```bash
export PATH="$PWD/../tools/flutter/bin:$PATH"
export JAVA_HOME="$PWD/../tools/jdk/jdk-17.0.13.jdk"

flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

产物：`build/app/outputs/flutter-apk/app-release.apk`，仅含 `arm64-v8a`，`minSdkVersion 24`。

## 真机注意事项

- OPPO Find X9 Pro 首次安装需允许「安装未知应用」
- 在设置页打开提醒后，进入「后台常驻通知」把应用加入电池优化白名单
- `path_provider_android` 被固定在 2.2.23：2.3.x 引入的 `jni` 原生模块会把 CMake 产物写回只读的 pub 缓存，导致构建失败

## 已知限制

- 本机环境无法生成 macOS 桌面端（缺 CocoaPods，系统 Ruby 2.6 缺少 Xcode 头文件），UI 需在真机上验收
- 云端同步接口需从移动网络访问；本机到 Cloudflare Workers 边缘节点被网络阻断，未能在本机联调
