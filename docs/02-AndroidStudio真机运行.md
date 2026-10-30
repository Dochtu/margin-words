# 八、Android Studio 真机运行与验证说明

> 本文档只覆盖 **Android 真机**。全程**不需要** Xcode、CocoaPods、Apple 开发者账号，**不需要**创建 Android 模拟器（AVD）。
> 每一步都给出「预期结果」与「失败怎么办」，照着做即可，不需要额外搜索。

本文以 Windows + 本项目的实际配置为例：

| 项 | 本机示例值 | 你的机器上怎么查 |
| --- | --- | --- |
| Flutter SDK | `E:\flutter` | 终端 `where flutter` |
| Android SDK | `E:\SDK` | Android Studio → Settings → Languages & Frameworks → Android SDK → 顶部路径 |
| JDK | 17（`java -version` 显示 17.0.5） | 终端 `java -version` |
| 项目根目录 | `<你的路径>\wordbook`（含 `pubspec.yaml`） | 资源管理器能看到 `pubspec.yaml` |

---

## 8.1 环境准备与检查

### 8.1.1 必须安装的组件

| 组件 | 说明 | 是否需要 |
| --- | --- | --- |
| **Android Studio**（稳定版） | 只用来打开工程、连真机、点 Run、看 Logcat | ✅ 必须 |
| **Flutter SDK**（3.44.x 稳定版） | 本项目用 3.44.5 / Dart 3.12.2 验证 | ✅ 必须 |
| **Android SDK Platform** | 至少装 **API 36**（`compileSdk`/`targetSdk` 都是 36）；顺带装 API 33/34 便于排查 | ✅ 必须 |
| **Android SDK Platform-Tools**（含 `adb`） | 连真机、装 APK | ✅ 必须 |
| **Android SDK Command-line Tools** | `flutter doctor --android-licenses` 需要 | ✅ 必须 |
| **Android SDK Build-Tools** | 装 36.x（与 compileSdk 对齐）即可 | ✅ 必须 |
| **JDK 17** | AGP 9 要求 JDK 17+；Android Studio 自带 JBR 17 也可 | ✅ 必须（用 AS 内置即可） |
| **Android Emulator / 系统镜像** | — | ❌ **不需要，不要装** |
| **Xcode / CocoaPods** | 本项目无 iOS 目录 | ❌ **不需要** |

安装位置：Android Studio → `Settings`（macOS 为 `Preferences`）→ `Languages & Frameworks` → `Android SDK`
→ `SDK Platforms` 勾选 **Android 16 (API 36)**；`SDK Tools` 勾选 **Android SDK Platform-Tools**、**Android SDK Command-line Tools (latest)**、**Android SDK Build-Tools**。

> **预期结果**：`SDK Tools` 列表里 Platform-Tools、Command-line Tools、Build-Tools 都显示 Installed；`SDK Platforms` 里 API 36 显示 Installed。
> **失败怎么办**：勾选后点 `Apply`，若下载失败，`Settings → HTTP Proxy` 里配置公司/本地代理，或改用国内镜像源（见 8.1.4）。

### 8.1.2 在 Android Studio 里安装 Flutter 与 Dart 插件

1. 打开 Android Studio → 菜单 `File` → `Settings`（macOS：`Android Studio` → `Settings`）。
2. 左侧选 `Plugins`，切到 `Marketplace` 标签。
3. 搜索框输入 **Flutter**，点 `Install`（会连带安装 **Dart** 插件）。
4. 安装完成后点 `Restart IDE` 重启。

> **预期结果**：重启后新建项目向导里出现 `New Flutter Project`；`Settings → Languages & Frameworks` 下出现 `Flutter` 一项。
> **失败怎么办**：Marketplace 打不开是网络问题，可在 `Settings → Appearance & Behavior → System Settings → HTTP Proxy` 配代理后重试；或从 [plugins.jetbrains.com](https://plugins.jetbrains.com) 下载 Flutter 插件 zip，用 `Plugins → ⚙ → Install Plugin from Disk...` 本地安装。

### 8.1.3 命令行验证环境

打开终端（AS 底部 `Terminal` 即可），执行：

```bash
flutter doctor -v
```

逐项检查（**只关心这四项**）：

| 检查项 | 期望 | 不期望看到 |
| --- | --- | --- |
| `Flutter` | 版本 3.44.x，channel stable | 无 |
| `Android toolchain` | 显示 SDK 路径与「All Android licenses accepted」 | `Android license status unknown`、`Unable to locate Android SDK` |
| `Android Studio` | 显示版本与路径 | 无 |
| `Connected device` | 显示你的真机型号（连上后才有） | — |
| `Xcode` / `CocoaPods` | 在 Windows 上通常显示未安装 | **可以忽略** |
| `Android Emulator` / `AVD` | — | **不作为运行前提，可忽略** |

若提示许可未接受：

```bash
flutter doctor --android-licenses
```

一路输入 `y` 接受全部许可，然后重新 `flutter doctor`。

> **预期结果**：`flutter doctor` 中 `Android toolchain` 为 ✅，`[!]` 只出现在 iOS 相关项上。
> **失败怎么办**：
> - 提示 `Unable to locate Android SDK` → 执行 `flutter config --android-sdk "E:\SDK"`（换成你的实际路径），或设置环境变量 `ANDROID_HOME`。
> - 提示 `cmdline-tools component is missing` → 在 SDK Manager 的 `SDK Tools` 里勾选并安装 **Android SDK Command-line Tools (latest)**，再重跑 `flutter doctor --android-licenses`。
> - 提示 `Java version` 不满足 → 见 8.5 表格第 8 条。

### 8.1.4 在 Android Studio 中指定 Flutter SDK 路径

`File` → `Settings` → `Languages & Frameworks` → `Flutter`：

- **Flutter SDK path**：填 `E:\flutter`（换成你的实际路径）
- 点 `Apply`，下方应显示 Flutter 与 Dart 的版本号

> **预期结果**：显示 `Flutter version 3.44.5`、`Dart version 3.12.2`，无红色报错。
> **失败怎么办**：路径必须指向 **Flutter SDK 根目录**（里面能看到 `bin\flutter.bat`），不是 `bin` 也不是 `packages`；Windows 路径不要带尾部反斜杠。

### 8.1.5 国内镜像（可选，网络慢时强烈建议）

在 Windows「系统属性 → 环境变量 → 用户变量」里新增：

| 变量名 | 值 |
| --- | --- |
| `PUB_HOSTED_URL` | `https://pub.flutter-io.cn` |
| `FLUTTER_STORAGE_BASE_URL` | `https://storage.flutter-io.cn` |

设置后**重启 Android Studio**（或至少重开 Terminal），再执行 `flutter pub get`。

> **预期结果**：`flutter pub get` 在 1–2 分钟内完成。
> **失败怎么办**：镜像偶尔不稳定，删掉这两个变量再试官方源；或在 `%USERPROFILE%\.pub-cache` 目录上确认有写权限。

---

## 8.2 打开项目与依赖同步

### 8.2.1 正确打开方式

1. Android Studio → `File` → `Open`。
2. 选择**包含 `pubspec.yaml` 的项目根目录**（即 `...\wordbook`），**不要**只选 `wordbook\android`。
3. 弹窗询问是否信任项目 → `Trust Project`。

> **预期结果**：左侧 Project 面板能看到 `lib/`、`android/`、`pubspec.yaml`、`docs/`；顶部出现 Flutter 工具栏（设备下拉框 + Run ▶）。
> **失败怎么办**：
> - 只看到 `android` 一堆 Gradle 文件、没有 Flutter 工具栏 → 你打开的是子目录，`File → Close Project` 后重新打开根目录。
> - 没有 Flutter 工具栏 → 插件没装好，回到 8.1.2。

### 8.2.2 Pub get

打开项目后 AS 一般会自动执行。若没有：

- 方式 A：在 Project 面板右键 `pubspec.yaml` → `Pub: Get Dependencies`
- 方式 B：底部 Terminal：

```bash
flutter pub get
```

> **预期结果**：`Got dependencies!`，项目根目录出现 `pubspec.lock` 与 `.dart_tool/package_config.json`。
> **失败怎么办**（常见三种）：
> 1. **`The current Dart SDK version is ... because wordbook requires SDK version >=3.12.0`**
>    → Flutter 版本太低。`flutter --version` 确认 ≥ 3.44.x，否则升级 Flutter SDK。
> 2. **版本解析冲突 / `version solving failed`**
>    → 本项目依赖全部精确锁定，正常不会冲突。若你手动改过版本：`flutter clean` → 删除 `pubspec.lock` → `flutter pub get`。
> 3. **下载超时 / `SocketException`**
>    → 配 8.1.5 的镜像，或配代理后 `File → Invalidate Caches and Restart`。

### 8.2.3 Gradle 同步

首次打开会提示 `Gradle sync`，点 `Sync Now`（或点顶部出现的 `Sync Project with Gradle Files`）。

本项目使用的组合（**已验证可构建**）：

| 组件 | 版本 | 配置文件 |
| --- | --- | --- |
| Gradle | 9.1.0 | `android/gradle/wrapper/gradle-wrapper.properties` |
| AGP | 9.0.1 | `android/settings.gradle.kts` |
| Kotlin | 2.3.20 | `android/settings.gradle.kts` |
| compileSdk / targetSdk | 36 | `android/app/build.gradle.kts` |
| minSdk | 26（Android 8.0） | `android/app/build.gradle.kts` |

> **预期结果**：底部 `Build` 窗口显示 `BUILD SUCCESSFUL` / `Gradle sync finished`，`External Libraries` 里出现 Flutter 与各插件。
> **失败怎么办**：
> - **`flutter.sdk not set in local.properties`** → 见下方 8.2.4。
> - **下载 Gradle 发行版很慢或失败** → 见下方 8.2.5。
> - **`Could not determine java version`** → 见 8.5 表格第 8 条。

### 8.2.4 关于 `android/local.properties`

这个文件是**本机路径配置**，不参与版本管理，内容形如：

```properties
sdk.dir=E\:\\SDK
flutter.sdk=E\:\\flutter
```

- 如果换到另一台电脑，**必须改成那台机器的实际路径**（`sdk.dir` 是 Android SDK，`flutter.sdk` 是 Flutter SDK）。
- 文件丢了也不要紧：`flutter pub get` 或 `flutter run` 会自动重新生成；也可手动按上面的格式新建。

> **预期结果**：Gradle sync 不再报 `flutter.sdk not set`。
> **失败怎么办**：路径中的 `\` 要写成 `\\`（或直接用正斜杠 `E:/SDK`）；路径不要包含中文。

### 8.2.5 首次同步要下载 Gradle（唯一的大文件）

`gradle-wrapper.properties` 里**已经预置了腾讯镜像**（国内实测 1.3MB/s 左右，约 1–2 分钟）：

```properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-9.1.0-bin.zip
```

如果你在海外或公司内网访问镜像困难，改成官方源（一样能用，只是国内会非常慢）：

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.1.0-bin.zip
```

- 版本必须是 **9.1.0 或更高**：AGP 9.0.1 会显式校验，低于 9.1.0 直接报
  `Minimum supported Gradle version is 9.1.0. Current version is 9.0.0`。
- 也可在 `Settings → Build, Execution, Deployment → Build Tools → Gradle` 里把 `Gradle distribution` 改为
  `Local installation` 指向本机已解压的 Gradle 9.1+（例如 `E:\gradle-9.1`），完全跳过下载。

> **预期结果**：`%USERPROFILE%\.gradle\wrapper\dists\gradle-9.1.0-bin\` 下出现解压后的目录；Sync 继续进行。
> **失败怎么办**：删掉该目录下未完成的 `*.part` / 临时文件夹后重试；或临时用手机热点；或按上面改用本地 Gradle。

> **补充 1**：本项目已在 `android/settings.gradle.kts` 与 `android/build.gradle.kts` 里**预置了阿里云 Maven 镜像**（并保留 `google()` / `mavenCentral()` 兜底），
> 因此插件和依赖的下载通常不会再出现 `Remote host terminated the handshake` 这类超时。
> 如果你在海外或公司内网，删掉那几行 `maven("https://maven.aliyun.com/...")` 即可。

> **补充 2**：`android/gradle.properties` 里有一行 `kotlin.incremental=false`。
> 这是为**项目路径含空格**（例如 `G:\Vibe coding\wordbook`）准备的：Kotlin 2.3 在 Windows 上写增量缓存时，
> 遇到带空格的路径会报 `Could not close incremental caches ... caches-jvm/jvm/kotlin`。
> 关掉后构建稳定，只影响原生部分的全量编译速度，**Dart 热重载不受影响**。
> 如果你的项目路径不含空格、且想恢复增量编译，删掉这一行即可。

---

## 8.3 真机连接与识别（重点）

### 8.3.1 手机端：打开开发者选项与 USB 调试

1. `设置` → `关于手机` → 连续点击 **版本号** 7 次（部分机型在 `设置 → 我的设备 → 全部参数` 里）。
2. 返回 `设置` → `系统` → `开发者选项`（部分机型在 `设置 → 更多设置`）。
3. 打开 **USB 调试**。

各品牌额外注意（这些开关不在原生 Android 里，缺了会「安装失败」）：

| 品牌 | 需要额外打开的开关 |
| --- | --- |
| 小米 / Redmi（MIUI、HyperOS） | `开发者选项` → **USB 安装**、**USB 调试（安全设置）**；必要时关闭 **MIUI 优化**（部分版本在 `开发者选项` 底部） |
| OPPO / 一加 / realme（ColorOS） | `开发者选项` → **USB 调试** + **禁止权限监控**（否则安装时无响应） |
| vivo / iQOO（OriginOS） | `开发者选项` → **USB 调试** + **USB 安装** |
| 华为 / 荣耀（HarmonyOS / MagicOS） | `开发者选项` → **USB 调试** + **仅充电时允许 ADB 调试** |
| 三星 | `开发者选项` → **USB 调试**（One UI 可能还需 `设置 → 生物识别与安全 → 其他安全设置 → 自动拦截器` 关闭） |

> **预期结果**：`开发者选项` 里 USB 调试开关为蓝色/绿色。
> **失败怎么办**：找不到开发者选项 → 确认点的是「版本号」而不是「Android 版本」；企业/MDM 管理的手机可能被禁用，换一台个人手机。

### 8.3.2 USB 连接与模式切换

1. 用**支持数据传输**的 USB 线连接电脑（很多赠品线只能充电）。
2. 手机下拉通知栏，点 USB 通知，选择 **文件传输 / MTP**（**不要**选「仅充电」）。

> **预期结果**：手机上出现「允许 USB 调试吗？」弹窗（见 8.3.3），电脑能访问手机存储。
> **失败怎么办**：换线、换 USB 口（优先主板后置口，不用 hub）、换手机试，确认是线/口的问题。

### 8.3.3 驱动与授权（Windows）

1. 连接后手机弹出 **「允许 USB 调试吗？」**，勾选 **「始终允许使用这台计算机进行调试」**，点 **允许**。
2. 若无弹窗：拔插一次、或在 `开发者选项` 里点 **「撤销 USB 调试授权」** 后重插。
3. 若「设备管理器」出现带黄色感叹号的未知设备：
   - 安装手机厂商 USB 驱动（小米助手 / OPPO 助手 / 华为手机助手等自带），或
   - 安装 Google USB Driver：SDK Manager → `SDK Tools` → 勾选 **Google USB Driver** → 安装，然后在设备管理器里右键未知设备 → 更新驱动 → 手动选择 `SDK\extras\google\usb_driver`。

> **预期结果**：设备管理器 `Android Device` / `便携设备` 下能看到手机，无感叹号。
> **失败怎么办**：Windows 11 可能需要在「设置 → 隐私和安全性 → 设备安全性 → 内核隔离」里允许该驱动；公司电脑若无管理员权限，换个人电脑。

### 8.3.4 验证连接（关键一步）

终端执行：

```bash
adb devices
```

期望输出（**状态必须是 `device`**）：

```
List of devices attached
8A2X0T5R9K      device
```

| 输出 | 含义 | 处理 |
| --- | --- | --- |
| `xxxx    device` | 正常 | 继续 8.3.5 |
| `xxxx    unauthorized` | 未授权 | 看手机屏幕有无授权弹窗；有则勾「始终允许」并允许；无则 `开发者选项 → 撤销 USB 调试授权` 后重插 |
| `xxxx    offline` | 连接异常 | `adb kill-server` 然后 `adb start-server`，再 `adb devices`；仍 offline 就重插线 |
| 列表为空 | 完全没识别到 | 依次排查：USB 线是否数据线 → USB 模式是否「文件传输」→ 是否开了 USB 调试 → 驱动 → 换口/换线 |
| `adb: command not found` | adb 不在 PATH | 用完整路径 `<SDK>\platform-tools\adb.exe`，或把该目录加进 PATH |

补充命令（当 `adb devices` 反复异常时）：

```bash
adb kill-server
adb start-server
adb devices
```

> **预期结果**：设备序列号后跟 `device`。
> **失败怎么办**：上面表格逐条排除；`adb devices` 权限问题在 Linux/macOS 上需要 `sudo`，Windows 不需要。

### 8.3.5 在 Android Studio 中确认设备

看顶部工具栏的设备下拉框（Run 按钮左边）：

- 应出现你的手机型号，例如 `Xiaomi 13 (Android 14)`。

若没出现：

1. 先跑 `flutter devices`，它会列出 Flutter 识别到的设备及 ID；
2. 检查 `Run` → `Edit Configurations...` → 目标配置里 **Target** 是否选了真机（`Open select device dialog` / 具体机型）；
3. 点设备下拉框右侧的 `Refresh`；
4. 仍不行 → `File → Invalidate Caches / Restart`。

> **预期结果**：设备下拉框能看到真机型号并已勾选；`Run ▶` 按钮为可点击状态（绿色）。
> **失败怎么办**：**不要**去创建 AVD。`Run` 灰色 99% 是「没有可用设备」，回到 8.3.4 把 `adb devices` 修到 `device` 状态即可。

### 8.3.6 无线调试（可选，Android 11+）

1. 手机与电脑连**同一个 Wi-Fi**。
2. `开发者选项` → **无线调试** → 打开 → 点「使用配对码配对设备」，记下 **IP:端口** 与 **6 位配对码**。
3. 电脑执行：

```bash
adb pair 192.168.1.20:37123      # 换成手机显示的配对地址
# 输入 6 位配对码
adb connect 192.168.1.20:5555    # 换成手机无线调试页显示的 IP:端口
adb devices
```

> **预期结果**：`adb devices` 出现 `192.168.1.20:5555  device`，AS 设备下拉框里也能选。
> **失败怎么办**：路由器开启了 AP 隔离会导致连不上，改用 USB；配对端口每次开启都会变，注意重新查看。

**再次强调**：全程不需要启动任何模拟器。如果设备列表里只有「Create New Device / 无设备」，请回到 8.3.4 排查真机连接。

---

## 8.4 运行与热重载

### 8.4.1 两种运行方式

**方式 A（推荐，Android Studio 内）**

1. 顶部设备下拉框选中你的真机；
2. 点 **Run ▶**（或 `Shift + F10`）；
3. 首次会触发 Gradle 构建 + 安装 APK，通常在 1–5 分钟。

**方式 B（终端）**

```bash
flutter devices                 # 拿到设备 ID，例如 8A2X0T5R9K
flutter run -d 8A2X0T5R9K
```

> **预期结果**：Build 窗口最后出现 `BUILD SUCCESSFUL`，手机上自动打开「错题单词本」，显示「今日回顾」页，底部有 今日 / 全部 / 我的 三个 tab。
> **失败怎么办**：
> - `Run ▶` 灰色 → 见 8.3.5（没选中设备）。
> - 手机没弹安装确认 → 部分机型需手动允许「安装未知来源应用」，在手机弹窗里点允许。
> - 安装报 `INSTALL_FAILED_USER_RESTRICTED` → 打开「USB 安装」开关（见 8.3.1 品牌表）。

### 8.4.2 首次运行的正常现象

| 现象 | 说明 |
| --- | --- |
| 手机弹出「是否安装此应用」 | 正常，点「继续安装」/「允许」 |
| 首次启动白屏 1–2 秒 | Flutter 引擎初始化 + 首次建库，正常 |
| 首次进入「拍照识别」点拍照，弹出相机权限 | 正常，这是**运行时**申请，不是启动时 |
| 首次使用 OCR 稍慢（1–3 秒） | ML Kit 首次加载模型，之后就快了 |

### 8.4.3 热重载 / 热重启

| 操作 | AS 快捷键 | 终端 | 效果 |
| --- | --- | --- | --- |
| 热重载 Hot Reload | 点 ⚡ 图标（`Ctrl + \`） | 按 `r` | 保留当前页面状态，只重编译改动 |
| 热重启 Hot Restart | 点 ↻ 图标（`Ctrl + Shift + \`） | 按 `R` | 重建整个 Widget 树，状态清空（数据库数据不受影响） |
| 完全重跑 | 再点 Run ▶ | `q` 退出后重跑 | 重新安装启动 |

注意：

- **改了原生代码**（`android/` 下的 Kotlin、Manifest、`build.gradle.kts`）→ 热重载无效，必须**停止后重新 Run**。
- 热重载依赖 USB/无线连接稳定；连接断开时 AS 会提示设备丢失，重新连接后点 Run 即可。
- 数据是否保留：热重载/热重启**都不会**清数据库；只有「卸载应用」或「设置里清空数据」才会删。

### 8.4.4 为什么必须真机验证

以下四类问题**只有真机能暴露**，模拟器结果不能替代：

1. **相机**：模拟器只有虚拟场景，无法验证对焦、反光、倾斜的真实 OCR 效果；
2. **相册 / 权限**：Android 13+ Photo Picker、14+「仅选中的照片」、各厂商权限二次管控，模拟器行为不一致；
3. **权限弹窗文案与「不再询问」**：真机上拒绝两次后才会进入永久拒绝，模拟器常常一次就永久拒绝；
4. **SQLite 持久化**：真机杀进程、切后台被回收、重启手机后数据是否还在，必须实测。

---

## 8.5 常见真机运行错误与排查

| # | 现象 | 原因 | 解决步骤 |
| --- | --- | --- | --- |
| 1 | `adb devices` 列表为空 | 线只能充电 / USB 模式是「仅充电」/ 未开 USB 调试 / 驱动缺失 | ①换数据线 → ②通知栏切「文件传输」→ ③确认 USB 调试已开 → ④设备管理器装驱动 → ⑤换 USB 口（不用 hub） |
| 2 | `adb devices` 显示 `unauthorized` | 手机没点「允许 USB 调试」 | 看手机屏幕弹窗勾「始终允许」→ 允许；无弹窗则 `开发者选项 → 撤销 USB 调试授权` 后重插；再不行 `adb kill-server && adb start-server` |
| 3 | `adb devices` 显示 `offline` | adb 服务状态错乱 / 连接不稳定 | `adb kill-server` → `adb start-server` → `adb devices`；仍 offline 重插线或重启手机 |
| 4 | AS 设备下拉框看不到真机、`Run ▶` 灰色 | AS 没识别到设备 / 未选目标 | 终端 `flutter devices` 确认能看到 → 点下拉框刷新 → `Edit Configurations → Target` 选真机 → `File → Invalidate Caches / Restart`；**不要**去建 AVD |
| 5 | 设备管理器出现「未知 Android 设备」/ 黄色感叹号 | 缺厂商 USB 驱动 | 装手机厂商助手（小米/OPPO/华为手机助手）或 SDK Manager 里装 **Google USB Driver**，再手动更新驱动指向 `SDK\extras\google\usb_driver` |
| 6 | 安装失败：`INSTALL_FAILED_USER_RESTRICTED` | 厂商 ROM 禁止 USB 安装 | 小米：开发者选项 → **USB 安装** + **USB 调试（安全设置）**，必要时关 **MIUI 优化**；OPPO/realme：关闭**权限监控**；vivo：打开 **USB 安装** |
| 7 | `flutter doctor` 报 `Android license status unknown` | SDK 许可未接受 | `flutter doctor --android-licenses`，一路 `y`；若报 `cmdline-tools component is missing`，先在 SDK Manager 装 **Command-line Tools (latest)** |
| 8 | Gradle sync 失败：`Could not determine java version` / `Unsupported class file major version` | JDK 版本不对（AGP 9 需 JDK 17+，且不能是 JDK 21 混用） | `File → Project Structure → SDK Location → Gradle JDK` 选 **Embedded JDK 17** 或本机 JDK 17；终端 `java -version` 确认 17；`File → Invalidate Caches / Restart` |
| 9 | `Pub get failed` / `version solving failed` | SDK 约束不满足 / 手动改了版本号 / 缓存损坏 | 确认 Flutter ≥3.44；`flutter clean` → 删 `pubspec.lock` → `flutter pub get`；配国内镜像（8.1.5） |
| 10 | Gradle sync 卡在下载 / `Could not download gradle-9.1.0-bin.zip` | 网络到 services.gradle.org 不通 | `gradle-wrapper.properties` 已默认用腾讯镜像；若你改回了官方源又很慢，改回镜像（见 8.2.5），或改用本地 Gradle 9.1 |
| 10.1 | `Minimum supported Gradle version is 9.1.0. Current version is 9.0.0` | Gradle 版本低于 AGP 9.0.1 要求 | 把 `distributionUrl` 改成 `gradle-9.1.0-bin.zip`（或更高），再 `cd android && gradlew --stop` 后重新 Sync |
| 11 | 编译报 `AndroidManifest.xml` 权限/属性冲突（如 `uses-sdk:minSdkVersion 21 cannot be smaller than 26`） | 某插件要求更高 minSdk，或 Manifest 写错 | 保持 `android/app/build.gradle.kts` 中 `minSdk = 26`；不要手写 `<uses-sdk>`；改完 `Build → Clean Project` 再 Run |
| 12 | 运行到拍照时闪退（`SecurityException: Permission Denial ... CAMERA`） | 只在 Manifest 声明了 CAMERA，但运行时没申请 | 本项目已在点拍照时用 `permission_handler` 申请；若你改过代码，确认 `Permission.camera.request()` 在 `pickImage` **之前**执行 |
| 13 | 识别时提示「网络不可用」 | 手机无网 / 代理拦截 / 缺少 INTERNET 权限 | 确认 Manifest 有 `<uses-permission android:name="android.permission.INTERNET"/>`；手机关掉 VPN 或用可用网络；只有「提取」这一步需要联网，可点「改用本地规则识别」 |
| 14 | 安装后点图标就闪退 | 启动期异常（数据库/SDK/插件初始化） | AS 底部 `Logcat` 过滤 `package:com.lz.wordbook` 或 `level:error`，看第一条 `E/AndroidRuntime` 堆栈；常见：`minSdk` 太低、`local.properties` 路径错导致插件未注册、存储空间不足。也可 `adb logcat -s flutter` 看 Dart 异常 |
| 15 | 热重载后界面没变化 | 只改了原生代码 / 改了 `main()` 顶层结构 | 原生改动必须重新 Run；Dart 改动若涉及全局初始化，按 `R` 热重启 |
| 16 | Gradle 报 `Remote host terminated the handshake` / `Could not GET 'https://...'`，但浏览器能打开该网址 | 本机代理软件（Clash / v2ray 等）已关闭或端口变了，而 Gradle 仍指向旧代理 | 打开 `C:\Users\<你>\.gradle\gradle.properties`，检查 `systemProp.http(s).proxyHost/Port`：代理已关就**注释掉这 6 行**；端口变了就改成实际端口（Clash Verge 默认 mixed-port `7897`）；改完 `cd android && gradlew --stop` 再 Sync |
| 17 | `Could not close incremental caches ... caches-jvm/jvm/kotlin` | 项目路径含空格 / 上次构建被强制中断，Kotlin 增量缓存写不进去 | 本项目已在 `android/gradle.properties` 加了 `kotlin.incremental=false`；若仍出现，`flutter clean` 后重跑，或把项目移到不含空格与中文的路径（如 `D:\wordbook`） |
| 18 | `Failed to find target with hash string 'android-37' in: <SDK>` / `Dependency requires compileSdk 37` | 某个 Android 依赖把 `compileSdk` 抬到了 37（Android 17），而本机只有 36 | 本项目已把 `permission_handler` 锁在 `12.0.1` 以保持在 compileSdk 36；如果你手动升级了它而报此错，二选一：① 回退到 `12.0.1`；② 在 `android/app/build.gradle.kts` 写 `compileSdk = 37`，并用 SDK Manager 安装 **Android 17 (API 37)** |

> 快速定位闪退：`adb logcat -c`（清空）→ 复现闪退 → `adb logcat -d | findstr "AndroidRuntime"`，或在 AS 的 Logcat 里选设备 + `com.lz.wordbook` 进程。

---

## 8.6 真机运行验收清单

按顺序逐项确认，全部打勾即代表项目在真机上跑通：

- [ ] `flutter doctor` 中 **Android toolchain** 无红色错误项（iOS 项可忽略）
- [ ] `adb devices` 能看到真机，状态为 **device**
- [ ] Android Studio 顶部设备下拉框已选中真机，`Run ▶` 可点击
- [ ] Android Studio 中 **Pub get** 成功完成（出现 `pubspec.lock`）
- [ ] **Gradle sync** 成功（`BUILD SUCCESSFUL`）
- [ ] 点 Run 后 APK 成功安装并在真机启动，**无红屏、无启动崩溃**
- [ ] 三个 tab（今日 / 全部 / 我的）可正常切换，无报错
- [ ] 点「拍照识别」→「拍一张照片」，真机弹出 **相机权限** 弹窗；点拒绝后出现解释文案与「去系统设置」入口
- [ ] 允许相机后，真机相机可拍照并返回识别流程
- [ ] 点「从相册选择」，真机相册/图片选择器可打开并选图
- [ ] 完成一次 **拍照 → OCR → 确认编辑（改一个释义、删一条）→ 保存**
- [ ] 保存后自动回到「今日」并看到刚保存的单词，`共 N 个` 数字正确
- [ ] 今日页翻卡：点击卡片能翻面；点「已掌握」「仍不熟」能切到下一张；走到最后出现完成页
- [ ] 「全部」页：搜索关键词能过滤；切换「已掌握/仍不熟」结果正确；选日期区间能过滤；切换排序生效
- [ ] 列表长释义点击可展开/收起，行不对齐/不溢出
- [ ] 编辑一个单词并保存后，列表与今日页同步更新
- [ ] **完全关闭应用（从最近任务划掉）后重新打开，SQLite 中的单词仍然存在**
- [ ] 切换手机深色模式，应用跟随变色且无白块、无文字不可读
- [ ] 系统字号调到最大，主要页面不溢出（可上下滚动查看）
- [ ] 飞行模式下仍能打开应用、浏览/复习/编辑已有单词（只有识别的大模型步骤会失败并给出提示）

---

## 附：模型配置在哪里（Key 不进源码）

App 内没有配置入口，**源码里也不写 Key**。Key 放在本地 `config/app_config.json`（已 gitignore），运行时注入。

### 1. 本地配置文件

复制 `config/app_config.example.json` 为 `config/app_config.json`：

```json
{
  "LLM_BASE_URL": "https://api.deepseek.com/v1",
  "LLM_API_KEY": "sk-你的Key",
  "LLM_MODEL": "deepseek-flash",
  "LLM_TIMEOUT": "25",
  "AGENT_BASE_URL": "http://192.168.1.100:8787"
}
```

`config/app_config.json` 已在 `.gitignore` 里，不要提交。

### 2. 在 Android Studio 里注入

`Run` → `Edit Configurations...` → 选中 `main.dart` → **Additional run args**：

```text
--dart-define-from-file=config/app_config.json
```

点 `Apply`，之后每次 Run 都会带上。只填文件、不加这个参数，App 读不到，会显示未配置。

> 如果 AS 报 `The --dart-define-from-file file does not exist`，说明工作目录不对，改成绝对路径。

### 3. 代码里的兜底

`lib/core/app_config.dart` 只保留非敏感兜底：

- `_codeBaseUrl` / `_codeModel`：接口地址与模型名；
- `_codeAgentBaseUrl`：默认 `http://127.0.0.1:8787`（USB + adb reverse）；
- `_codeApiKey`：**空字符串**，必须靠上面的配置文件注入。

JSON 键名 = `String.fromEnvironment` 的参数名，大小写要一致。

### 注意点

1. **改完要重新 Run**（热重载不会重新读取 `fromEnvironment`，因为它编译期就固化了）。
2. **不填 Key 也能用**：识别会自动降级为本地规则解析；智能体服务仍可单独使用。
3. **不要把 `config/app_config.json` 或 `agent/.env` 提交到公开仓库**；也不要把 Key 写回 `app_config.dart` 的 `defaultValue`。
4. 要发给别人用，建议走代理（客户端只填代理地址，Key 放服务端）。

### 填了 Key 但 App 里还是"未配置"，怎么查

按顺序看这 5 条，基本能覆盖全部情况：

| # | 原因 | 判断方法 | 解决 |
| --- | --- | --- | --- |
| 1 | **只改了 `config/app_config.json`，但没加 run 参数** —— 这个文件不会自动加载 | `dart run tool/config_check.dart` 看「地址来源」是不是"代码（app_config.dart）"、Key 是不是"未配置" | 在 `Run → Edit Configurations → Additional run args` 加 `--dart-define-from-file=config/app_config.json` |
| 2 | **改完只做了热重载** | 热重载不会重新读取 `fromEnvironment` | 停止后重新 Run（或点 ↻ 热重启也不够，必须重新构建） |
| 3 | **跑的是旧安装包** | 之前用别的配置装过 | 重新 Run 覆盖安装；手机上确认版本时间是新的 |
| 4 | **JSON 里键名写错/漏了** | 诊断里显示"未读取到" | 键名必须是 `LLM_BASE_URL` / `LLM_API_KEY` / `LLM_MODEL`，大小写一致 |
| 5 | **把智能体地址填成了大模型地址** | 诊断里提示"地址填错了" | 智能体是 `http://电脑IP:8787`（LangGraph 服务），不是 `https://api.xxx.com/v1` |
| 6 | **智能体填了 127.0.0.1，但没做端口转发** | 诊断里提示"需要先执行 adb reverse" | 终端执行 `adb reverse tcp:8787 tcp:8787`（每次插拔 USB 后都要执行）；或改填电脑局域网 IP |
| 7 | **地址对，但仍连不上智能体** | 服务没启动 / 防火墙拦截 / 不同 Wi-Fi | 先在电脑上 `curl http://IP:8787/health`；再按 `agent/README.md` 放行 8787 端口；手机与电脑连同一 Wi-Fi |
| 8 | **服务起不来，报 `ModuleNotFoundError: No module named 'langgraph'`** | 依赖装到了另一个 Python（电脑上常有多套） | `python -c "import sys;print(sys.executable)"` 确认解释器，再用同一个 python 执行 `python -m pip install -r requirements.txt`；或直接双击 `agent/start.bat` |

三种自查手段（从快到慢）：

1. **命令行**（不启动 App）：

   ```bash
   dart run tool/config_check.dart
   dart run tool/config_check.dart --define=LLM_MODEL=test-model
   ```

   输出里看 `llm=ready/not-ready`、`key=...`、`agent=...`。

2. **Logcat**：过滤 `AppConfig`，启动时会打一行

   ```text
   [AppConfig] llm=ready base=... model=... key=sk-****（长度 N）/... agent=...
   ```

3. **没有 App 内配置页**：配置只从代码兜底或 `--dart-define` 读取，App 里不显示、不修改。

> 规则：**注入值为空 = 没配置**。源码里不再有真实 Key，所以不会出现"JSON 留空却回落到代码 Key"的情况；Key 必须通过 `--dart-define-from-file` 注入。

### 与旧版本的差异

旧版本有「我的 → 识别设置 → 大模型识别」表单，可以在手机上填 Key。**该入口已移除**：

| 项 | 旧 | 新 |
| --- | --- | --- |
| Key / 模型 / Base URL | App 内表单填写，存 SharedPreferences | `config/app_config.json`（gitignored）+ `--dart-define-from-file` 注入；`app_config.dart` 只放非敏感兜底 |
| 智能体地址 | App 内表单填写 | 同上（`AGENT_BASE_URL` / `_codeAgentBaseUrl` 兜底） |
| 「允许上传照片识别圈选」 | 在智能体设置页 | 改为代码常量 `lib/core/app_config.dart` 的 `_codeAllowVision`（App 内无开关） |
| 换手机/重装 | 需要重新填 | 配置随构建注入；换机需要重新提供本地 `config/app_config.json`，不随源码走 |
