# 错题单词本 · margin-words

> 一个只在 Android 真机上运行的**本地单词错题本**：拍照 → 对话式提取 → 每日翻卡回顾。
> 点开即用、无需登录、不采集个人信息，数据只保存在手机本地的 SQLite 中。

---

## 一、项目简介

**错题单词本**（仓库名 `margin-words`，应用名 `wordbook`）解决的是"做完英语阅读/试卷，把生词抄进本子"这件事的自动化：用手机拍下题目或笔记，用一句自然语言说清"要哪些词"（例如"只要名词"、"去掉人名"、"前 10 个"、"只提取我画圈的单词"），智能体读图筛词后直接写入单词本，之后按遗忘节奏翻卡回顾。

### 核心能力

| 能力 | 说明 |
| --- | --- |
| 对话式提取 | 发照片 + 一句话要求，多轮追问可在同一批候选词上反复筛选 |
| 本地 OCR | Google ML Kit 离线文字识别（拉丁字母），不联网 |
| 每日回顾 | 翻卡式复习，按添加日期分组；另有"全部单词"列表与搜索 |
| 词条管理 | 增删改、释义、音标（可联网校验补全，失败静默降级） |
| 全程离线存储 | SQLite + 应用私有目录，图片可选留档 |
| 隐私优先 | 无账号体系、无统计数据上传；照片默认仅在需要圈选时发给视觉模型，可一键关闭 |

### 技术栈

| 层 | 选型 |
| --- | --- |
| 客户端 | Flutter 3.44.5（stable） / Dart 3.12.2，仅 `android/` 平台 |
| 状态管理 | `provider` 6.1.5 |
| 本地存储 | `sqflite` 2.4.5（SQLite） + `shared_preferences` 2.5.6 |
| 识别 | `google_mlkit_text_recognition` 0.17.1（离线 OCR） + OpenAI 兼容大模型 |
| 相机/权限 | `image_picker` 1.2.4 / `permission_handler` 12.0.1 |
| 原生构建 | Gradle 9.1.0 / AGP 9.0.1 / Kotlin 2.3.20 / JDK 17 |
| 智能体服务 | Python 3.10+ · FastAPI · LangGraph · langchain-openai（独立进程，可选） |

### 基本信息

| 项目 | 值 |
| --- | --- |
| 应用名 | 错题单词本 |
| 包名 / applicationId | `com.lz.wordbook` |
| 最低系统 | Android 8.0（API 26） |
| 目标 / 编译 SDK | 36 |
| 版本 | 1.0.0+1 |
| 平台目录 | 仅 `android/`，无 iOS 目录，不需要模拟器 |

---

## 二、环境配置

### 1. 必备环境

| 依赖 | 版本要求 | 校验命令 |
| --- | --- | --- |
| Flutter SDK | ≥ 3.44.0（推荐 3.44.5 stable） | `flutter --version` |
| Dart SDK | ≥ 3.12.0（随 Flutter 提供） | `dart --version` |
| JDK | 17（Gradle 9.x 要求） | `java -version` |
| Android SDK | Platform 36 + Build-Tools + Platform-Tools | Android Studio → SDK Manager |
| Android Studio | 任意近期版本（含 Android Gradle Plugin 9 支持） | — |
| Python（可选） | 3.10 ~ 3.13，仅在跑智能体服务时需要 | `python --version` |

> 不需要 Xcode、CocoaPods、Apple 账号，也不需要创建 AVD 模拟器——本项目只面向 Android 真机。

初始化依赖：

```bash
flutter pub get
```

### 2. 模型配置（Key 不进源码）

**App 内没有 Key 输入框，源码里也不写 Key。** 所有凭证通过编译期注入传入：

1. 复制配置模板：

   ```bash
   cp config/app_config.example.json config/app_config.json
   ```

2. 在 `config/app_config.json` 中填入 `LLM_BASE_URL` / `LLM_API_KEY` / `LLM_MODEL` / `LLM_TIMEOUT` / `AGENT_BASE_URL`；
3. 在 Android Studio 的 `Run → Edit Configurations → Additional run args` 加入：

   ```text
   --dart-define-from-file=config/app_config.json
   ```

4. 重新 Run（`String.fromEnvironment` 是编译期常量，热重载不会重新读取）。

也可用命令行等价方式：

```bash
flutter run --dart-define-from-file=config/app_config.json
```

自查当前生效的配置（地址、模型、Key 掩码、来源）：

```bash
dart run tool/config_check.dart
```

`lib/core/app_config.dart` 只保留非敏感兜底（Base URL、模型名、智能体地址），`_codeApiKey` 恒为空字符串。

### 3. 智能体服务配置（可选）

```bash
cd agent
python -m pip install -r requirements.txt
```

复制 `agent/.env.example` 为 `agent/.env` 并填写 `AGENT_API_KEY` 等变量（该文件已被 `.gitignore` 排除）。随后启动：

```bash
# 方式一：双击 agent/start.bat（自动检查依赖 + 启动 + 打印局域网地址）

# 方式二：手动
python -m uvicorn app:app --host 0.0.0.0 --port 8787
```

最后把 `config/app_config.json` 的 `AGENT_BASE_URL` 改为 `http://电脑局域网IP:8787`（USB 调试可用 `adb reverse tcp:8787 tcp:8787`，地址填 `http://127.0.0.1:8787`）。

> 不启动智能体服务时，拍照提取功能会明确提示"没连上智能体"；未配置 LLM Key 时，文字 → 单词结构会自动降级为本地规则解析。

---

## 三、使用步骤

### 1. 在 Android Studio 中运行

1. `File > Open` → 选择**包含 `pubspec.yaml` 的根目录**（不要只打开 `android/`）；
2. 等待 Pub get 与 Gradle Sync 完成（首次会下载 Gradle 与依赖，约 3–10 分钟）；
3. 手机开启「开发者选项 → USB 调试」，用 USB 线连接电脑，连接模式选「文件传输」；
4. 终端执行 `adb devices`，确认设备状态为 `device`；
5. 在 AS 顶部设备下拉框选中真机，点击 ▶ Run。

### 2. 命令行运行

```bash
flutter devices                      # 确认真机已识别
flutter run --dart-define-from-file=config/app_config.json
flutter build apk --release --dart-define-from-file=config/app_config.json
```

### 3. 验证与测试

```bash
flutter analyze                      # 静态检查
flutter test                         # 单元测试（test/parsing_test.dart）
dart run tool/smoke_check.dart       # 不依赖 flutter test 的冒烟脚本
```

### 4. 典型使用流程

1. 打开 App → 首页「今天」标签查看待复习词条；
2. 进入「提取单词」聊天页 → 拍照/选图 → 输入一句要求（如"只保留我不认识的，前 10 个"）→ 确认导入；
3. 对结果不满意可继续追问（如"再把 Tom 去掉"），在同一批候选词上重筛；
4. 在「全部单词」中搜索、编辑、删除；每日回到「今天」翻卡复习。

---

## 四、目录结构

```text
wordbook/
├── android/                     # 唯一原生工程（权限声明、Gradle 配置、图标资源）
├── agent/                       # LangGraph 智能体服务（Python，可选）
│   ├── .env.example             # 环境变量模板（可提交）
│   ├── .env                     # 实际凭证（已 gitignore）
│   ├── app.py                   # FastAPI 入口
│   ├── graph.py                 # LangGraph 图编排（读图 → 筛词 → 动作）
│   ├── chat.py / tools.py       # 对话与工具定义
│   └── start.bat                # Windows 一键启动
├── assets/                      # 图标预览图
├── config/
│   ├── app_config.example.json  # 模型/Key 配置模板（可提交）
│   └── app_config.json          # 本地实际配置（已 gitignore，不提交）
├── docs/                        # 交付文档（产品设计 / 真机运行 / 界面改版）
├── lib/
│   ├── main.dart                # 启动与依赖注入（Provider）
│   ├── app.dart                 # MaterialApp、主题、中文本地化
│   ├── core/                    # 主题、配置、日期、文本清洗
│   ├── data/                    # SQLite 建库、DAO、模型、设置存储
│   ├── services/                # OCR、LLM 调用、JSON 容错、权限、音标校验
│   ├── state/                   # WordStore / SettingsStore（ChangeNotifier）
│   └── ui/                      # pages + widgets
├── test/parsing_test.dart       # 纯逻辑单元测试（清洗 / JSON 容错 / 本地解析）
├── tool/
│   ├── config_check.dart        # 配置自查脚本
│   ├── smoke_check.dart         # 冒烟脚本
│   └── make_icon.py             # 图标生成脚本
├── pubspec.yaml                 # 依赖（全部精确版本号）
└── README.md
```

### 文档索引

| 文档 | 内容 |
| --- | --- |
| [docs/01-产品与技术设计.md](docs/01-产品与技术设计.md) | 页面与导航、数据库表结构与 SQL、识别流程、提示词与 JSON 容错、权限方案、验收标准、风险与替代方案 |
| [docs/02-AndroidStudio真机运行.md](docs/02-AndroidStudio真机运行.md) | 在 Android Studio 中从零连接真机运行的完整步骤（含 18 条常见错误排查表） |
| [docs/03-界面改版与智能体接入.md](docs/03-界面改版与智能体接入.md) | 视觉体系（配色/圆角/描边 token）、LangGraph 图设计、接口契约、降级策略 |
| [agent/README.md](agent/README.md) | 智能体服务的启动、环境变量、接口与自测方法 |

---

## 五、敏感信息与安全

本项目遵循"**凭证不入库**"原则，仓库中不包含任何真实 Key、Token 或密码。

| 敏感项 | 存放位置 | 是否提交 |
| --- | --- | --- |
| 大模型 API Key（App 端） | `config/app_config.json` → 编译期注入 | 否（`.gitignore` 已排除） |
| 智能体 API Key（服务端） | `agent/.env` | 否 |
| Android 签名文件 | `*.jks` / `*.keystore` / `key.properties` | 否 |
| SDK 本地路径 | `android/local.properties` | 否 |
| 运行时抓取数据 | `agent/recovered_words.json` | 否 |
| 模板文件 | `config/app_config.example.json`、`agent/.env.example` | 是（仅占位符） |

注意事项：

- 不要使用 `git add -f` 强制添加被忽略的配置文件；
- 若曾误提交过凭证，仅删除文件不够——必须**在服务商侧吊销并重新签发**，再清理 Git 历史；
- 正式对外分发时应改为「客户端只持会话 token、Key 放服务端」的代理架构（详见 `docs/01` 风险表）。

---

## 六、离线 / 联网边界

| 功能 | 是否联网 |
| --- | --- |
| 打开应用、今日回顾、全部回顾、编辑删除 | 完全离线 |
| 拍照 / 相册选图、图片 → 文字（ML Kit） | 完全离线 |
| 文字 → 单词结构（大模型） | 需要联网；未配置 Key 时降级为本地规则解析 |
| 对话式提取（智能体服务） | 需要局域网内可达的 Python 服务 |
| 音标补全（dictionaryapi.dev，可关闭） | 需要联网，失败静默跳过 |

图片默认仅在「只提取我画圈的单词」这类需求下发给视觉模型；若要求图片完全不出手机，可将 `lib/core/app_config.dart` 中 `_codeAllowVision` 改为 `false`（圈选类要求会退化为按全部文字处理）。

---

## 七、常见问题

| 现象 | 原因与处理 |
| --- | --- |
| App 显示"未配置模型" | 只填了 `config/app_config.json` 但没加 `--dart-define-from-file` 参数 |
| `ModuleNotFoundError: No module named 'langgraph'` | 依赖装到了另一个 Python；用 `python -c "import sys;print(sys.executable)"` 确认真实解释器后，用同一个 python 执行 `python -m pip install -r requirements.txt` |
| Kotlin 增量缓存报错 `Could not close incremental caches` | 项目路径含空格所致，`android/gradle.properties` 已设 `kotlin.incremental=false` 规避 |
| Gradle Sync 卡住 | 首次同步需下载 Gradle 与依赖，建议配置镜像或代理后重试 |

---

## 八、许可

本项目为个人学习与自用项目，未附开源许可证。如需复用，请先与作者联系。
