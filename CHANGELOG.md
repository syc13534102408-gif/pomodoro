# 更新日志（CHANGELOG）

> 本文档由 2026-09-09 的文档整理建立，合并了原 `outputs/` 下 4 份过程报告的要点
> （原文已移入 `docs/archive/outputs-*.md`，细节以原文为准）。
> 版本号以 `pomodoro_app/pubspec.yaml` 为准；更早的历史见 git 提交记录。

## 2026-09-09 · macOS 后台可见性（未发版）

- **新增悬浮置顶计时窗**（`macos/Runner/FloatingTimerPanel.swift`）：阶段 + 已专注大字 + 进度条，
  可拖动、右键菜单、位置与开关存 UserDefaults，无进行中会话自动隐藏。
  `level = .statusBar` + `.fullScreenAuxiliary` **实测可显示在全屏 App 之上**。
- **菜单栏常驻文案改为「已专注时长」**（原为剩余时间；剩余挪到下拉菜单），新增 `SessionView.elapsedText`。
- **禁用 App Nap**（`AppDelegate.beginActivity`）：修复窗口不可见时定时器被系统节流、后台计时变慢的问题。
- 文档体系整理：`docs/01-07` 规范化、新建本文件、历史快照归档。
- 产物：`outputs/松果-专注时光-macOS-悬浮计时-2026-09-09.zip`（已实机验收）。

## v1.2.0+4（2026-09-08 · 安卓）

### 通知功能增强（6 项）

| 需求 | 实现 |
|---|---|
| 系统级到点闹钟 | `zonedSchedule` id 911 预排计划结束时刻（`exactAllowWhileIdle`，未授权自动降级 inexact）；暂停/切模式/丢弃/完成/关开关时撤销 |
| 权限时机 | 首次开始专注即请求通知权限 + 精确闹钟权限 |
| 锁屏完整显示 | 锁屏/通知栏标题含当前专注任务名 |
| 铃声策略 | Android 到点铃声统一走系统通知音（频道 `pine_alert`），不再叠加 asset 提示音防双响 |
| 点击/action | 到点通知点击回首页；带「忽略」动作（只撤该条、不动会话） |
| 决策纯函数 | 新增 `notification_policy.dart` + 单测；`notifyEnabled=false` 全链路静默 |

附带加固：**防闪断**（到点翻转不立即撤销 911）、**补偿去重**（恢复超时会话的补弹提醒按 `recordId@锚点` 去重）、
Manifest 补 `USE_EXACT_ALARM` 与三个开机恢复 Receiver。
真机待验证清单（Doze、重启恢复、OEM 锁屏可见性等 5 项）见 `docs/archive/outputs-delivery-notifications-2026-09-08.md`。

### Bug 修复（3 个，根因速记）

| 问题 | 根因 | 修复 |
|---|---|---|
| 最近记录完成时间显示 00:00 | `FocusRecord.fromMap()` 只解析 `date`，忽略已写入的 `at` 字段 | 优先解析 `at`，缺失安全回退 `date`，统一 `.toLocal()`；磁盘旧数据自愈，无需迁移 |
| 「完成时间」显示的是开始时刻 | `engine.complete()` 未把 `at` 推进到完成瞬间 | `complete()` 时 `copyWith(at: now)`；`dayKey` 归属仍按开始日 |
| 月历打卡底色深浅不可辨 | 四档松绿 α36/80/140/200 叠米白底，最低档与"无记录"同色 | 重映射 α90/150/205/240，档间差 ≥55 |

### 已知边界

- 存量旧记录的 `at`（= 开始时刻）无法还原为完成时刻，自本轮起新记录即正确。
- 网页端仍以开始时刻存 `at` 并当完成时间渲染，待对齐（见下方后续建议 P0-2）。

## v1.1.0+3 及更早（2026-09-08 前）

- 方案 D「扁平积木」UI 重构（安卓端，权威规格见 `docs/design/UI重构执行路径-扁平积木-2026-09-08.md`）
- 锁屏倒计时改系统 Chronometer 渲染（ColorOS 冻结下仍走表）
- 云同步后端由 Cloudflare Workers 迁移至腾讯云 SCF + COS
- macOS 桌面版从 0 到可构建运行（独立桌面 UI、菜单栏计时、本月回顾）
- 详见 git 提交历史与 `docs/archive/`。

## 后续建议（自 2026-09-08 系统评估，按优先级）

完整分析见 `docs/archive/outputs-pinecone-review-2026-09-08.md`，此处仅留决策要点：

**P0**：① 代码推送远端（已完成 2026-09-09 前半，推送待代理）；② 网页端 `complete()` 时间口径对齐安卓（`at` 写完成瞬间）；③ release 签名决策（当前 debug 签名，仅个人分发）；④ 按方案 D 走查清单系统性真机走查一轮。

**P1**：① 计时页每秒重建隔离（当前整页 setState，专注 3 小时 ≈ 1 万次整页 build）；② 两端云净荷 schema 统一（先出字段对照矩阵 + merge 单测）；③ 自动备份增强（节流上传 + 设置页显示最近备份时间）；④ macOS 到点提醒实机验证（通知授权）后出正式包；⑤ 网页端 Playwright 冒烟 3~5 条主链路。

**P2**：月历翻月/点日明细、数据导出 JSON/CSV、同步码重置、409 记录级合并、R8 缩包（需验证 `path_provider_android 2.2.23` override 兼容性）、深色模式（需拍板，默认不做）。

**明确不做**：SQLite 化存储、实时多端同步、增量同步协议、fl_chart 图表库。
