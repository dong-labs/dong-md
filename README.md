<div align="center">

# 麻雀 MD · Sparrow MD

### 阅读 Markdown，就这么简单。

轻量的 Android 端 Markdown 阅读器 · Just read it.

**秒开 · 无账号 · 无联网权限需求 · 开源免费**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android-green.svg)](https://www.pgyer.com/maquemd-android)
[![Downloads](https://img.shields.io/badge/download-%E8%92%B2%E5%85%AC%E8%8B%B1-F59E0B.svg)](https://www.pgyer.com/maquemd-android)

[⬇ 下载](#下载安装) · [✨ 功能](#功能) · [🖥️ 桌面版 Sparrow](https://github.com/maoruibin/sparrow) · [🌐 官网](https://blog.gudong.site/sparrow/)

</div>

---

## 解决什么问题

微信、飞书里收到一个 `.md` 文件——点开，要么打不开，要么一堆 `#` 号星号糊一脸。

**麻雀 MD 就是干这个的**：文件管理器、聊天App、分享菜单里，任何文本文件直接用麻雀打开，干干净净渲染成能读的样子。读完关掉，不多停留一秒。

> 工具是伺候你的，不是你伺候工具。

## 功能

- **📖 智能识别**：Markdown / HTML / JSON / 纯文本自动分类渲染，不挑食
- **🔗 深度系统集成**：注册 80+ 种文件扩展名，文件管理器「打开方式」、微信/飞书分享直达
- **📄 HTML 渲染**：WebView 渲染 HTML 文件，样式完整保留
- **🕘 阅读历史**：自动记录（内容去重、字数/大小），最近读过的随手再开
- **📤 分享转发**：把文件分享给别人，一条链路打通
- **🌗 亮暗主题**：跟随系统
- **🪶 极简克制**：打开即读，没有编辑器、没有账号、没有多余按钮

## 下载安装

**方式一 · 蒲公英（推荐）**：[www.pgyer.com/maquemd-android](https://www.pgyer.com/maquemd-android)

**方式二 · GitHub Releases**：从 [Releases](https://github.com/dong-labs/dong-md/releases) 下载 APK 安装包

> 首次安装需允许「安装未知来源应用」。应用无联网权限需求，你的文件不出手机。

## 麻雀家族

| | 桌面 | 手机 |
| :--- | :--- | :--- |
| 名字 | 麻雀 Sparrow | 麻雀 MD · Sparrow MD |
| 定位 | Markdown 编辑器（读 + 写） | Markdown 阅读器（专注读） |
| 平台 | macOS / Windows | Android |
| 仓库 | [maoruibin/sparrow](https://github.com/maoruibin/sparrow) | 本仓库 |

**桌面写，手机读**——同一只麻雀，跟着你走。

## 品牌故事

> 麻雀啄窗，咚咚作响。咚咚家的鸟各司其职：仓咚咚、听咚咚、梦咚咚在云端，麻雀飞向了你的屏幕——先是口袋里的手机（麻雀 MD），后来又落上了桌面（麻雀 Sparrow）。麻雀虽小，飞得远。

## 开发

```bash
flutter pub get
flutter run          # 连接 Android 设备/模拟器
flutter build apk    # 出 release APK（无签名配置时自动 debug 签名）
```

发布流程：推 `v*` tag → CI 自动构建 APK 并附到 GitHub Release。

> 签名说明：正式签名走本地 `android/key.properties`（不入库），CI 与本地无签名环境自动降级 debug 签名，保证可构建可安装。

## 技术栈

Flutter · Dart · Kotlin（原生 MethodChannel） · WebView · flutter_markdown

## 开源协议

[MIT](./LICENSE) © 2026 gudong
