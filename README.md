<div align="center">

# 🥳MoodPet

**一个住在手机里的情绪伙伴，Everything is Plugin。**

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg?style=flat-square)](https://www.gnu.org/licenses/agpl-3.0)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev)
[![Material Design 3](https://img.shields.io/badge/Material_Design-3_Expressive-7E57C2?style=flat-square)](https://m3.material.io)
[![Riverpod](https://img.shields.io/badge/Riverpod-2.6-4C5DF9?style=flat-square)](https://riverpod.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Wear%20OS%20%7C%20Windows%20%7C%20Linux%20%7C%20macOS-5C6BC0?style=flat-square)](#)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-FF8A65?style=flat-square)](https://github.com/Tangmjiu/moodpet/pulls)

[功能](#-它能做什么) · [快速开始](#-快速开始) · [插件系统](#-插件系统) · [插件市场](#-插件市场) · [技术栈](#-技术栈) · [文档](#-文档) · [贡献](#-贡献)

</div>

---

MoodPet 不是一个聊天机器人。它是一个**容器**——伙伴的性格、情绪表达、声音、UI 风格，全都由插件定义。你可以给伙伴换一个性格，就像换一个主题；你可以给它加一个 TTS 引擎，就像装一个 App。

默认只装了一个伙伴：小黄脸 🎈。它温暖、共情、善于倾听。但你可以从插件市场装更多的 Friend——一只叫小柴的柴犬、一个动漫角色、任何你想要的性格。你也可以装 Application 插件扩展容器本身——给伙伴加上语音、换一个渲染器、覆盖某个 UI 页面。

## ✨ 它能做什么

- 🎭 **情绪伙伴** — 和一个有性格的伙伴聊天，它用 emoji、颜色、震动来表达情绪
- 🧩 **一切皆插件** — 伙伴的性格（Friend）、容器的能力（Application）、一键套装（整合包），全是插件
- 🛒 **插件市场** — 基于 GitHub 的零服务器成本市场，PR 合并即上架，下拉刷新即见
- 📴 **离线也能用** — 没配 LLM 也能聊，Friend 插件自带关键词情绪词库
- 📱 **多平台** — Android、Wear OS、Windows、Linux、macOS
- 🎨 **Material Design 3 Expressive** — Claymorphism 设计语言，暖桃种子色，弹簧物理动画

## 🚀 快速开始

### 环境要求

| 依赖 | 版本 |
| --- | --- |
| Flutter | 3.44+ |
| Dart | 3.12+ |
| Android Studio / VS Code | 最新稳定版 |

### 运行

```bash
git clone https://github.com/Tangmjiu/moodpet.git
cd moodpet
flutter pub get
flutter run
```

首次启动会自动提取默认伙伴（小黄脸 🎈）到本地插件目录。去设置里配一个 LLM provider 就能开始聊了——不配也能用，走离线关键词模式。

### 配 LLM

**设置 → AI 服务 → 选一个 provider → 填 API Key**

支持 OpenAI / Claude / Gemini 协议，也支持自定义 base URL 接兼容接口。

不配也没关系——离线模式下伙伴用 Friend 插件自带的 `emoji_mapping.json` 做关键词匹配，一样能回应，只是没有 LLM 的自由对话能力。

## 🧩 插件系统

MoodPet 有三种插件：

| 类型 | 做什么 | 含代码 | 同时激活 |
| --- | --- | --- | --- |
| 🎭 **Friend** | 定义伙伴性格、情绪、说话风格 | 否 | 1 个 |
| ⚡ **Application** | 扩展容器能力（TTS、语音识别、UI 覆盖） | 是 | 多个 |
| 📦 **Pack** | 一组 Friend + Application 的打包套装 | 否 | — |

### Friend — 纯文本就能做一个新伙伴

Friend 不含可执行代码。它是一组纯文本和 JSON：

- `system_prompt.txt` — 定义伙伴性格和响应规则（喂给 LLM）
- `emoji_mapping.json` — 离线模式的关键词情绪映射
- `identity.json` — 展示信息（名字、emoji、标语）

会写 Markdown 就能做一个新伙伴。不需要会编程。

### Application — 扩展容器本身

Application 可以包含可执行代码（Dart / Python / 二进制），能覆盖容器的 TTS、记忆、渲染等内置服务。通过 `manifest.json` 的 `overrides` 字段声明接管哪个服务。

## 🛒 插件市场

市场是一个 GitHub 仓库：[Tangmjiu/moodpet-plugin-market](https://github.com/Tangmjiu/moodpet-plugin-market)。

没有服务器，没有数据库，没有 CDN 账单。仓库的目录结构就是索引——`friend/` 目录下有哪些 `.meta.json`，市场里就有哪些 Friend。

```
plugin-market/
├── friend/          # Friend 插件
├── application/     # Application 插件
└── packs/           # 整合包
```

客户端通过 GitHub API 拉目录列表（5 分钟缓存），通过 `raw.githubusercontent.com` 下载插件包（CDN 加速，无限速）。PR 合并即上架，所有客户端下拉刷新即见。

### 发布插件

```
1. Fork 市场仓库
2. 在对应目录加三个文件：插件包 + .meta.json + 预览图
3. 提 PR
4. GitHub Actions 自动验证格式
5. 审核通过 → 合并 → 上架
```

详见[插件市场文档](#-文档)。

## 🎨 技术栈

<div align="center">

| 领域 | 技术 |
| --- | --- |
| 框架 | Flutter 3.44 + Dart 3.12 |
| 设计 | Material Design 3 Expressive |
| 状态管理 | Riverpod 2.6 |
| 设计语言 | Claymorphism — 柔软 3D、大圆角、弹簧动画 |
| 网络 | http（LLM 调用 + GitHub 市场数据） |
| 存储 | shared_preferences + path_provider |
| 解压 | archive（插件包 ZIP） |
| Markdown | flutter_markdown（伙伴回复渲染） |

</div>

暖桃种子色 `#E8A87C`、24–32px 圆角、双层柔阴影、弹簧物理动画。伙伴的情绪颜色会动态渲染到首页背景，让整个界面跟着它的心情呼吸。

## 📂 项目结构

```
lib/
├── app.dart                        # App shell + M3 主题 + Claymorphism tokens
├── main.dart                       # 入口
├── core/
│   ├── agent/                      # LLM agent（PocketClaw）+ 多协议 HTTP 客户端
│   ├── market/                     # 插件市场数据层
│   │   ├── market_config.dart         # 仓库坐标 + URL 构建
│   │   ├── market_cache.dart          # TTL 缓存（内存 + 磁盘）
│   │   ├── market_repository.dart     # GitHub 网络层
│   │   ├── market_providers.dart      # Riverpod providers
│   │   └── update_checker.dart        # 版本更新检测
│   ├── models/                     # 数据模型（manifest、emotion、provider config）
│   ├── plugin/                     # 插件系统
│   │   ├── plugin_manager.dart         # 插件注册表 + enable/disable
│   │   ├── plugin_loader.dart          # 扫描 + 解析 manifest
│   │   ├── plugin_installer.dart       # 下载 + 解压 + 安装
│   │   ├── pack_installer.dart         # 整合包展开
│   │   └── plugin_paths.dart           # 目录路径
│   ├── storage/                    # 对话记录 + 设置持久化
│   └── utils/                      # 工具函数
└── features/
    ├── home/                       # 首页（伙伴 + 语音输入）
    ├── market/                     # 插件市场（浏览 + 详情 + 安装）
    ├── plugins/                    # 插件管理
    └── settings/                   # 设置（provider、对话记录、日志）
```

## 📖 文档

完整技术文档包括两部分：

| 面向 | 内容 |
| --- | --- |
| **插件开发者** | 怎么写 Friend / Application / 整合包，怎么打包上架 |
| **容器开发者** | 市场数据层 API、安装器、Provider、UI 完整参考 |

https://moodpetdocs.mjiutang.top

## 🛠️ 开发

```bash
# 跑测试
flutter test

# 静态分析
flutter analyze

# 构建 APK
flutter build apk
```

## 🤝 贡献

欢迎 PR。无论是修 bug、加功能、写插件、改文档，都欢迎。

- 代码 PR 提到 `main` 分支
- 插件 PR 提到 [moodpet-plugin-market](https://github.com/Tangmjiu/moodpet-plugin-market)
- 大改动先开 Issue 讨论一下

## 📦 相关仓库

| 仓库 | 说明 |
| --- | --- |
| [moodpet](https://github.com/Tangmjiu/moodpet) | Flutter 客户端（本仓库） |
| [moodpet-plugin-market](https://github.com/Tangmjiu/moodpet-plugin-market) | 插件市场仓库（GitHub 分发） |

## 📄 协议

本项目采用 [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0) 协议。

简单说：你可以用、可以改、可以分发，但你分发的版本也必须开源，且通过网络提供服务也要开源。详见 [LICENSE](LICENSE)。

---

<div align="center">

如果这个项目对你有帮助，给个 ⭐ 让更多人看到。

</div>
