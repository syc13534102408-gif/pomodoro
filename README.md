# 松果 / 专注时光（Pomodoro）

「本地优先」的番茄钟：网页版（GitHub Pages）+ 安卓 App（Flutter）+ macOS 桌面版（同一套代码），
数据存本机，云端只做备份与跨设备搬运。

| 端 | 入口 | 状态 |
|---|---|---|
| 网页版 | `index.html` | 已上线 |
| 安卓 | `pomodoro_app/` | 功能完整（方案 D「扁平积木」UI，v1.2.0+4） |
| macOS 桌面 | 同上（`home_page.dart` 桌面分支） | 可构建运行，悬浮计时窗已实机验收 |
| 云同步后端 | `tencent-sync/`（腾讯云 SCF+COS） | 线上运行 |
| Web Push 后端 | `cloudflare-reminders/`（Cloudflare DO） | 仅网页端推送 |

## 功能特性

- **三种模式计时**：专注 / 短休息 / 长休息，每第 4 个番茄自动进长休息；
  计划时长到点**不自动结束**，继续累计 `+MM:SS`，由用户点「完成」才落记录
- **专注事件管理**：增删改、配色、删除不影响历史统计；今日清单（按天存储）；手动补记
- **统计**：今日/本周分钟、今日目标（分钟）与本周目标（次）、周堆叠柱状图（自绘）、本月回顾（月历打卡 + 事件分布）、连续天数
- **云端同步**：手动上传/恢复 + 自动同步（完成专注上传、回前台拉取），冲突 409 弹窗确认、绝不静默覆盖
- **提醒**：安卓本地通知 + 系统级到点闹钟 + 三音提示音 + 前台服务锁屏倒计时（系统 Chronometer 渲染）；
  macOS 菜单栏显示已专注时长 + 悬浮置顶计时窗（可跨全屏显示）
- **网页端**：单文件应用，Service Worker 接收后台提醒推送

## 快速开始

```bash
# 工具链在仓库内 tools/（不入库），首次需配置：
F=$PWD/tools/flutter/bin/flutter
$F config --android-sdk "$PWD/tools/android-sdk"
$F config --jdk-dir    "$PWD/tools/jdk/jdk-17.0.13.jdk"
cd pomodoro_app && $F pub get

# 日常（在 pomodoro_app/ 内）
$F test                              # 56 项用例 / 7 个文件
../tools/flutter/bin/dart analyze    # flutter analyze 的 LSP 在本机会崩，用这个
$F build apk --release --target-platform android-arm64
```

完整命令（含 macOS 构建、网页发布、后端部署、装到手机）见 **[docs/03](docs/03-环境搭建与常用命令.md)**。

## 目录结构

```
pinecone/
├── index.html / sw.js        # 网页版全部代码（单文件）+ Service Worker
├── pomodoro_app/             # ★ 安卓 + macOS 共用的 Flutter 工程
│   ├── lib/src/              # 逻辑层：engine(状态机)/models/storage/cloud_*/notifications/menu_bar_timer
│   ├── lib/pages/            # 表现层：home(含 macOS 桌面分支)/stats/settings
│   ├── android/  macos/      # 双端壳工程（macOS 含菜单栏与悬浮窗原生代码）
│   └── test/                 # 56 项单测
├── tencent-sync/             # 腾讯云同步后端（Node.js，deploy.py 部署）
├── cloudflare-reminders/     # Web Push 后端（Cloudflare Workers + DO + D1）
├── github-pages/             # 早期独立发布包快照（仅存档，不再使用）
├── docs/                     # ★ 项目文档（01-07 分章 + design 设计稿 + archive 历史快照）
├── outputs/                  # 交付物（gitignore，不入库）
└── tools/                    # 本机工具链：Flutter/JDK/Android SDK（gitignore）
```

## 📖 文档地图（接手先读这里）

| 文档 | 内容 | 什么时候读 |
|---|---|---|
| **[CHANGELOG](CHANGELOG.md)** | 版本时间线、bugfix 根因速记、后续建议 | 了解改了什么 |
| **[docs/01-项目概述与目标](docs/01-项目概述与目标.md)** | 背景、三端形态、产品目标、功能清单、访问地址 | 第一次接触项目 |
| **[docs/02-技术栈与目录结构](docs/02-技术栈与目录结构.md)** | 技术栈、依赖清单、完整目录树、入口文件速查 | 找文件、加依赖 |
| **[docs/03-环境搭建与常用命令](docs/03-环境搭建与常用命令.md)** | 工具链配置、分析/测试/构建/部署命令、git 状态 | 第一次跑起来、日常构建 |
| **[docs/04-核心架构与模块职责](docs/04-核心架构与模块职责.md)** | 分层架构、每个文件的职责与关键符号、依赖方向 | 改代码前 |
| **[docs/05-数据流与接口约定](docs/05-数据流与接口约定.md)** | 本地存储、状态机、云同步接口、净荷 schema、通知机制 | 动数据/同步/通知 |
| **[docs/06-编码规范与提交约定](docs/06-编码规范与提交约定.md)** | 代码规范、UI 红线、提交信息风格、敏感信息 | 写代码、提交 |
| **[docs/07-常见问题与注意事项](docs/07-常见问题与注意事项.md)** | 雷区清单、已知限制、当前待办 | 改任何代码前通读 |

设计文档：

| 文档 | 内容 |
|---|---|
| [docs/design/UI重构执行路径-扁平积木-2026-09-08.md](docs/design/UI重构执行路径-扁平积木-2026-09-08.md) | 方案 D「扁平积木」UI 规格：令牌、组件、页面结构树、走查清单（**当前 UI 的权威设计稿**） |
| [docs/design/方案E-UI设计方案-2026-09-08.md](docs/design/方案E-UI设计方案-2026-09-08.md) | 方案 E「松林手帐」UI 设计提案：方向三选一、信息架构、页面思路、令牌、交互、技术选型与分期（决策门 D0–D4，§12 已定稿） |
| [docs/design/方案E-执行路径-2026-09-08.md](docs/design/方案E-执行路径-2026-09-08.md) | 方案 E 自足式实施稿：令牌 v2、17 项纸面组件、页面结构树、P0–P9 分期与验收（**方案 E 实施时以此为准**） |
| [docs/design/mockups/方案E-视觉稿-v1.html](docs/design/mockups/方案E-视觉稿-v1.html) | 方案 E 高保真视觉稿：专注页三态 / 报告 / 设置 / 记录详情 sheet（浏览器打开） |

> 历史文档（2026-09-02 交接文档、2026-09-06 进度说明、2026-09-08 过程报告）已归档到
> [`docs/archive/`](docs/archive/)，**内容已过时，仅作快照参考**，事实以 `docs/` 为准。

## 🧭 三条最高原则

1. **本地优先**：断网必须可用，云端只是备份。
2. **到点不自动结束**：超时继续累计，用户点「完成」才落记录。
3. **改 UI 不碰逻辑层**：`engine/models/storage/cloud_*/notifications/menu_bar_timer` 的逻辑不动；视觉一律引用 `theme.dart` 令牌。

## 📍 当前状态（2026-09-09）

- 本地目录已由「番茄钟」更名为 `pinecone`（避免中文路径导致构建失败）
- 安卓端方案 D「扁平积木」UI 已重构完成；`dart analyze` 零告警
- macOS 悬浮计时窗 + 菜单栏已专注时长已实机验收（见 [CHANGELOG](CHANGELOG.md) 2026-09-09）
- 本地领先远端 22 个提交，推送需代理（见 docs/03 §4）
- 详细待办见 [docs/07 §6](docs/07-常见问题与注意事项.md)
