# P5 批次三暗色离屏预览

在仓库的 `pomodoro_app/` 运行：

```sh
../tools/flutter/bin/flutter test --no-pub test/preview/ui_reset_preview.dart
```

预览直接渲染真实组件与 `LedgerPage`，不启动桌面应用、不读取用户存储，也不发起网络请求。样本时间固定为 2026-11-16 14:30，包含运行中的会话、跨日完成记录、无任务记录、往期与未来日程。默认测试收集不包含这个显式执行文件。

中文字体沿用现有 macOS 离屏预览传统，从 `/System/Library/Fonts/Supplemental/Arial Unicode.ttf` 加载。按钮继承预览主题字体，Material 图标使用仓库 Flutter SDK 自带字体；字体不作为产品资源打包。

PNG 使用 2 倍像素输出到仓库根 `outputs/ui-reset-preview/`：

- `components-dark.png`：组件总览，800×1900 逻辑尺寸。
- `v2-records-360-dark.png` / `v5-schedule-360-dark.png`：360×800，Android。
- `v2-records-500-dark.png` / `v5-schedule-500-dark.png`：500×640，macOS 最小档。
- `v2-records-960-dark.png` / `v5-schedule-960-dark.png`：960×720，macOS 宽档。

`outputs/` 按仓库现有规则忽略；源码与复现说明提交，PNG 保留为本机人工审美验收产物。可滚动记录在画面底部的后续条目需要滚动阅读，不表示字段被省略。新测试另行断言首条双时间字段、日期选择、首条日程及固定动作的视口可见性。
