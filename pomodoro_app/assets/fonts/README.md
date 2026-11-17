# 打包字体（P5 批次 3.5）

来源为 Google Fonts 官方仓库，未修改、未子集化的 Noto 简体中文可变字体（思源同源版）。

| 文件 / Flutter 注册名 | 官方来源 | 字重轴 | SHA-256 |
|---|---|---|---|
| NotoSerifSC-wght.ttf / Noto Serif SC | https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf | 200–900 | 050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9 |
| NotoSansSC-wght.ttf / Noto Sans SC | https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf | 100–900 | a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da |

字体许可分别为同目录 `OFL.txt`（宋体）和 `NotoSansSC-OFL.txt`（黑体），从各字体官方目录取得并随应用打包。
两文件覆盖本项目使用的 400/500/600 等字重。注册名是实际打包族名；标题和正文的系统回退链在 `PineText` 中定义。

文件共 42,897,812 字节（约 40.9 MiB）。本批接受该资源体积；APK 增量未经打包实测，不把估算当成实际 APK 大小。
下载校验：完整长度为 25,125,512 / 17,772,300 字节；fontTools 逐表校验及中文字符覆盖通过。
