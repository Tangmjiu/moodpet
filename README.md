# MoodPet

> 一个住在手机里的情绪伙伴，一切皆插件。

MoodPet 是一个开源的情感陪伴应用。它不只是一个聊天机器人——它是一个"容器"，伙伴的性格、情绪表达、声音、甚至 UI 风格，全都由插件定义。你可以给伙伴换一个性格，就像换一个主题；你可以给它加一个 TTS 引擎，就像装一个 App。

## 它能做什么

- **情绪伙伴**：和一个有性格的伙伴聊天，它会用 emoji、颜色、震动来表达情绪
- **一切皆插件**：伙伴的性格（Friend）、容器的能力（Application）、一键套装（整合包），全是插件
- **插件市场**：基于 GitHub 的零服务器成本市场，PR 合并即上架，下拉刷新即见
- **离线也能用**：没配 LLM 也能聊——Friend 插件自带关键词情绪词库
- **多平台**：Android、Wear OS、Windows、Linux、macOS

## 截图

<!-- TODO: 补截图 -->

## 快速开始

### 环境要求

- Flutter 3.44+
- Dart 3.12+
- Android Studio / VS Code

### 运行

```bash
git clone https://github.com/Tangmjiu/moodpet.git
cd moodpet
flutter pub get
flutter run
```

首次启动会自动提取默认伙伴（小黄脸 🎈）到本地插件目录。去设置里配一个 LLM provider 就能开始聊了——不配也能用，走离线关键词模式。

### 配 LLM

设置 → AI 服务 → 选一个 provider → 填 API Key。支持 OpenAI / Claude / Gemini 协议，也支持自定义 base URL 接兼容接口。

不配也没关系——离线模式下伙伴用 Friend 插件自带的 `emoji_mapping.json` 做关键词匹配，一样能回应，只是没有 LLM 的自由对话能力。

## 插件系统

MoodPet 有三种插件：

| 类型 | 做什么 | 含代码 | 同时激活 |
| --- | --- | --- | --- |
| **Friend** | 定义伙伴性格、情绪、说话风格 | 否 | 1 个 |
| **Application** | 扩展容器能力（TTS、语音识别、UI 覆盖） | 是 | 多个 |
| **Pack** | 一组 Friend + Application 的打包套装 | 否 | — |

Friend 是纯文本和 JSON——`system_prompt.txt` 定义性格，`emoji_mapping.json` 定义离线情绪映射，`identity.json` 定义展示信息。不需要写代码就能做一个新伙伴。

Application 可以包含可执行代码（Dart / Python / 二进制），能覆盖容器的 TTS、记忆、渲染等内置服务。

### 插件市场

市场是一个 GitHub 仓库：[Tangmjiu/moodpet-plugin-market](https://github.com/Tangmjiu/moodpet-plugin-market)。没有服务器，没有数据库。仓库的目录结构就是索引——`friend/` 目录下有哪些 `.meta.json`，市场里就有哪些 Friend。

客户端通过 GitHub API 拉目录列表，通过 `raw.githubusercontent.com` 下载插件包。缓存策略让 API 调用频率远低于限速阈值。

想发布自己的插件？Fork 市场仓库，加文件，提 PR。CI 自动验证格式，合并即上架。详见 [插件市场文档](#文档)。

## 技术栈

- **Flutter** + **Material Design 3 Expressive**
- **Riverpod** 状态管理
- **Claymorphism** 设计语言——柔软 3D、大圆角、弹簧动画
- **archive** 解压插件包
- **http** 网络请求
- **shared_preferences** 本地持久化

设计语言是 Claymorphism：暖桃种子色（#E8A87C）、24–32px 圆角、双层柔阴影、弹簧物理动画。伙伴的情绪颜色会动态渲染到首页背景，让整个界面跟着它的心情呼吸。

## 项目结构

```
lib/
├── app.dart                    # App shell + M3 主题 + Claymorphism tokens
├── main.dart                   # 入口
├── core/
│   ├── agent/                  # LLM agent（PocketClaw）+ 多协议 HTTP 客户端
│   ├── market/                 # 插件市场数据层
│   │   ├── market_config.dart     # 仓库坐标 + URL 构建
│   │   ├── market_cache.dart      # TTL 缓存（内存 + 磁盘）
│   │   ├── market_repository.dart # GitHub 网络层
│   │   ├── market_providers.dart  # Riverpod providers
│   │   └── update_checker.dart    # 版本更新检测
│   ├── models/                 # 数据模型（manifest、emotion、provider config）
│   ├── plugin/                 # 插件系统
│   │   ├── plugin_manager.dart     # 插件注册表 + enable/disable
│   │   ├── plugin_loader.dart      # 扫描 + 解析 manifest
│   │   ├── plugin_installer.dart   # 下载 + 解压 + 安装
│   │   ├── pack_installer.dart     # 整合包展开
│   │   └── plugin_paths.dart       # 目录路径
│   ├── storage/                # 对话记录 + 设置持久化
│   └── utils/                  # 工具函数
├── features/
│   ├── home/                   # 首页（伙伴 + 语音输入）
│   ├── market/                 # 插件市场（浏览 + 详情 + 安装）
│   ├── plugins/                # 插件管理
│   └── settings/               # 设置（provider 配置、对话记录、日志）
└── ...
```

## 文档

完整的技术文档包括插件开发指南和容器集成参考：

- **插件开发者**：怎么写 Friend / Application / 整合包，怎么打包上架
- **容器开发者**：市场数据层 API、安装器、Provider、UI 的完整参考

文档站用 Starlight Material Design 3 主题构建，部署在 [moodpet.dev](https://moodpet.dev)（或见 `moodpet-docs` 目录本地构建）。

## 开发

```bash
# 跑测试
flutter test

# 静态分析
flutter analyze

# 构建 APK
flutter build apk
```

## 相关仓库

| 仓库 | 说明 |
| --- | --- |
| [moodpet](https://github.com/Tangmjiu/moodpet) | Flutter 客户端（本仓库） |
| [moodpet-plugin-market](https://github.com/Tangmjiu/moodpet-plugin-market) | 插件市场仓库（GitHub 分发） |

## 协议

MIT
