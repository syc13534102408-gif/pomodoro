# 松果番茄钟 · 初始发布快照（仅存档）

> ⚠️ 本目录是项目早期的「独立发布包」快照，**不是当前发布流程**。
> 现状：网页版直接用**仓库根目录**的 `index.html` / `sw.js` 发布到 GitHub Pages
> （推 `main` 分支即可），本目录的内容不会被执行。
> 当前部署与同步说明见 [`../README.md`](../README.md) 与 [`../docs/03-环境搭建与常用命令.md`](../docs/03-环境搭建与常用命令.md)。

## 当年的部署流程（仅历史记录，勿照做）

1. 在 GitHub 新建一个仓库，例如 `pomodoro`。
2. 上传本目录中的 `index.html`。
3. 打开仓库 `Settings` -> `Pages`。
4. 选择 `Deploy from a branch`，分支选 `main`，目录选 `/ (root)`。
5. 保存并等待部署完成。

网页会获得一个 HTTPS 地址，例如：

`https://你的用户名.github.io/pomodoro/`

首次打开后，在“数据与提醒”中点击“开启结束提醒”，并允许浏览器通知。
