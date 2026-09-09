# 交付说明：安卓端通知功能增强（v1.2.0+4）

- 日期：2026-09-08
- 平台：松果 / 专注时光 · 安卓端（Flutter `pomodoro_app/`）
- 版本：`versionCode=4 / versionName=1.2.0`（原 1.1.0+3，已 bump 以支持覆盖安装）
- 签名：项目内固定 keystore（SHA-1 `848e1ab3...`，与历史所有已装包一致）

## 本轮 6 项改动（用户确认方案全部落地）

| # | 需求 | 实现 |
|---|------|------|
| P0-1 | 系统级到点闹钟 | `zonedSchedule` id 911 预排计划结束时刻（`exactAllowWhileIdle`，未授权自动降级 `inexact`）；暂停/切模式/丢弃/完成/关闭通知开关/会话清空时撤销；专注与休息都排；幂等防重复 |
| P0-2 | 权限时机 | 首次开始专注即请求通知权限 + 精确闹钟权限（不再只依赖设置页）；Android 13+ 已拒绝后系统不重复弹窗 |
| P3 | 锁屏完整显示 | 锁屏/通知栏标题含当前专注任务名（如「松果 · 专注：数学真题」）；不做隐私隐藏（用户明确要求）；进程重启恢复路径同样还原任务名 |
| P1 | 铃声策略 | Android 到点铃声统一走系统通知音（频道 `pine_alert`），不再叠加 asset 提示音防双响；桌面/macOS 维持 chime |
| P1 | 点击/action | 911 到点通知点击回首页（含冷启动分支）；带「忽略」动作（只撤该条、不动会话状态） |
| P2 | 决策纯函数 | 新增 `notification_policy.dart` 纯函数层 + 22 条单测；`notifyEnabled=false` 全链路静默 |

## 附带加固（QA 评审提出）

- **A1 防闪断**：到点翻转（超时运行中）不立即撤销 911，避免已送达横幅被闪撤 / pending 闹钟被提前撤导致无声；撤销只发生在用户主动动作或关开关。
- **A2 补偿去重**：冷启动恢复「超时运行中」会话的补弹提醒按 `recordId@锚点时刻` 持久化去重，同一段超时跨冷启动只补一次。
- **AndroidManifest**：补 `USE_EXACT_ALARM`（计时类应用可安装即授权）+ flutter_local_notifications 的 ScheduledNotificationReceiver / ActionBroadcastReceiver / ScheduledNotificationBootReceiver（支持系统重启后自动恢复调度）。

## 质量结果（QA fresh-eyes 最终回归，另经主理人在最终工作树复核）

- `flutter test`：**55/55 通过**（原 30 + focus_record_roundtrip 5 + notification_policy 22 + notify_alarm_boundary 3…，以实际计数为准）
- `flutter analyze`：**No issues found（0 error / 0 warning）**
- 智能路由判定：NoOne
- 中途曾出现「两套实现并行写入致编译失败」的流程事故，已收敛为 design-1 唯一口径并在最终工作树复核通过后重建产物

## 产物

`outputs/松果-v1.2.0-通知增强-2026-09-08.apk`（54.7MB）
- 签名 SHA-1 `848e1ab3183c1080d2301536c42d1db873471415` = 已装旧包同一把 key → **可直接覆盖安装，数据不丢**
- versionCode 4 > 3（设备现装），正常升级路径

## 真机待验证（自动化测不到的平台行为）

1. 前台进程存活时到点：911 横幅完整保留不被闪撤；「忽略」只撤 911、不影响锁屏 5150 倒计时通知
2. 进程被系统杀掉后到点：是否准时弹出（exact 授权 vs inexact 延迟）；锁屏息屏长时间（Doze）场景
3. 重启手机后已排闹钟是否自动恢复（依赖插件 boot receiver）
4. 锁屏标题含任务名在 ColorOS 等各家 OEM 的可见性；精确闹钟授权页在 Android 12/13/14/15 的表现
5. 已知窄缝（低概率）：inexact 降级 + 进程被杀 + 延迟送达前冷启动，理论上可能补弹 910 后又收到迟到的 911（双响一次）；A2 已限流到每段超时一次

## 说明

- 到点通知仅带「忽略」动作；暂停/开始休息等控制按钮按约定降级未做（成本高），后续可迭代
- Android 到点铃声走系统 `pine_alert` 频道声音，不受 App 内「完成提示音」开关控制（该开关控制 asset 三音/桌面）；需彻底静音请在系统通知设置里关 pine_alert 声音
