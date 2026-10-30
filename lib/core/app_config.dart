/// 全局配置：模型与智能体的唯一读取点。
///
/// 安全规则：**源码里不写 API Key**。Key 放在本地 `config/app_config.json`
/// （已加入 .gitignore），构建/运行时用
/// `--dart-define-from-file=config/app_config.json` 注入。
///
/// 读取优先级：
///   1. 编译期注入（`--dart-define` / `--dart-define-from-file=...`）
///   2. 下面的 `_code*` 常量（只放非敏感兜底：Base URL、模型名、智能体地址）
///
/// 注入值为空字符串时视为"没配置"，自动回落到代码兜底。
class AppConfig {
  const AppConfig._();

  // ======================================================================
  //  ① 代码内兜底：只放非敏感项
  // ======================================================================

  static const String _codeBaseUrl = 'https://api.deepseek.com/v1';
  /// 不要在源码里填真实 Key。留空，用 `--dart-define` 或
  /// `--dart-define-from-file=config/app_config.json` 注入。
  static const String _codeApiKey = '';
  /// DeepSeek-V4.1-Flash 的 API 名称就是 `deepseek-flash`
  /// （旧的 deepseek-chat / deepseek-v4-flash 已下线或被兼容转发到 V4.1-Flash）
  static const String _codeModel = 'deepseek-flash';
  /// 智能体服务地址。默认 USB + adb reverse（http://127.0.0.1:8787）。
  /// 局域网地址用 `--dart-define=AGENT_BASE_URL=http://电脑IP:8787` 覆盖，
  /// 或写进 config/app_config.json（已 gitignore）。
  static const String _codeAgentBaseUrl = 'http://127.0.0.1:8787';

  /// 是否允许把照片发给视觉模型。
  /// 只有「只提取我画圈的单词」这类要求才需要看原图；
  /// 设为 false 时照片不会离开手机，圈选类要求会退回按全部文字处理。
  static const bool _codeAllowVision = true;

  /// 是否用免费词典接口联网校验 / 补全音标（避免模型编造）
  static const bool _codeValidatePhoneticOnline = true;

  // ======================================================================
  //  ② 编译期注入（一般不用改这段）
  // ======================================================================

  static const String _envBaseUrl = String.fromEnvironment('LLM_BASE_URL');
  static const String _envApiKey = String.fromEnvironment('LLM_API_KEY');
  static const String _envModel = String.fromEnvironment('LLM_MODEL');
  static const String _envAgentBaseUrl =
      String.fromEnvironment('AGENT_BASE_URL');
  static const int _envTimeout = int.fromEnvironment('LLM_TIMEOUT', defaultValue: 0);

  /// 空字符串 → 用代码兜底；否则用注入值
  static const String llmBaseUrl =
      _envBaseUrl == '' ? _codeBaseUrl : _envBaseUrl;

  static const String llmApiKey = _envApiKey == '' ? _codeApiKey : _envApiKey;

  static const String llmModel = _envModel == '' ? _codeModel : _envModel;

  static const String agentBaseUrl =
      _envAgentBaseUrl == '' ? _codeAgentBaseUrl : _envAgentBaseUrl;

  /// 超时秒数：未注入或 <=0 时用 25
  static const int llmTimeoutSeconds = _envTimeout <= 0 ? 25 : _envTimeout;

  /// 是否允许把照片发给视觉模型（代码常量，App 内无开关）
  static const bool agentAllowVision = _codeAllowVision;

  /// 是否联网校验 / 补全音标（代码常量，App 内无开关）
  static const bool validatePhoneticOnline = _codeValidatePhoneticOnline;

  // ======================================================================
  //  派生状态（业务代码只读这些）
  // ======================================================================

  /// 大模型是否可用（三者都有值才算）
  static bool get llmReady =>
      llmApiKey.trim().isNotEmpty &&
      llmBaseUrl.trim().isNotEmpty &&
      llmModel.trim().isNotEmpty;

  /// 是否配置了智能体服务地址
  static bool get agentConfigured => agentBaseUrl.trim().isNotEmpty;

  /// 智能体地址是否"填错了"：填成了大模型接口（与大模型 Base URL 相同 / 带 /chat/completions）
  static bool get agentLooksLikeLlm {
    if (!agentConfigured) return false;
    final String agent = _normalize(agentBaseUrl);
    final String llm = _normalize(llmBaseUrl);
    if (agent == llm) return true;
    return agent.contains('/chat/completions');
  }

  /// 智能体地址是否填成了"本机回环地址"（手机访问不到电脑的 127.0.0.1）
  static bool get agentIsLoopback {
    if (!agentConfigured) return false;
    final String host = Uri.tryParse(agentBaseUrl.trim())?.host ?? '';
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '10.0.2.2'; // Android 模拟器里的宿主机别名，真机同样访问不到
  }

  /// 智能体配置的问题描述；没问题返回 null
  static String? get agentWarning {
    if (!agentConfigured) return null;
    if (agentLooksLikeLlm) {
      return '这是大模型接口地址，不是智能体服务。智能体要填 http://电脑IP:8787';
    }
    return null;
  }

  /// 智能体是否真正可用（只有"填成了大模型接口"才算错）
  static bool get agentReady => agentConfigured && !agentLooksLikeLlm;

  /// 非阻断的提示：用本机回环地址时必须配合 adb reverse，否则手机连不上
  static String? get agentHint {
    if (agentIsLoopback) {
      return '当前是手机本机地址，需要先执行 adb reverse tcp:8787 tcp:8787'
          '（每次重新插 USB 后都要执行一次）；或用电脑局域网 IP';
    }
    return null;
  }

  /// 展示用：打码后的 Key，便于确认"到底读到没读到"
  static String get apiKeyMasked {
    final String key = llmApiKey.trim();
    if (key.isEmpty) return '未读取到';
    if (key.length <= 8) return '${'•' * key.length}（长度 ${key.length}）';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}'
        '（长度 ${key.length}）';
  }

  /// 配置来源：区分"来自配置文件/命令行"还是"来自代码兜底"
  static String get apiKeySource {
    if (_envApiKey.isEmpty) {
      return _codeApiKey.isEmpty ? '未配置' : '代码（app_config.dart）';
    }
    return '配置文件 / 命令行注入';
  }

  static String get baseUrlSource =>
      _envBaseUrl == '' ? '代码（app_config.dart）' : '配置文件 / 命令行注入';

  static String get modelSource =>
      _envModel == '' ? '代码（app_config.dart）' : '配置文件 / 命令行注入';

  /// 技术提示：只在调试日志里打，方便用 Logcat 排查
  static String describe() {
    return 'llm=${llmReady ? "ready" : "not-ready"} '
        'base=$llmBaseUrl($baseUrlSource) '
        'model=$llmModel($modelSource) '
        'key=$apiKeyMasked/$apiKeySource '
        'agent=${agentReady ? agentBaseUrl : (agentConfigured ? "地址有问题" : "未配置")}';
  }

  /// 命令行自检用（`dart run tool/config_check.dart`），App 内不展示
  static List<String> diagnosis() {
    final List<String> lines = <String>[];
    lines.add('大模型：${llmReady ? "已配置" : "未配置"}');
    lines.add('· 接口地址：$llmBaseUrl（$baseUrlSource）');
    lines.add('· 模型名称：$llmModel（$modelSource）');
    lines.add('· API Key：$apiKeyMasked（$apiKeySource）');

    if (agentConfigured) {
      lines.add('智能体：${agentReady ? agentBaseUrl : "地址有问题"}');
      final String? warning = agentWarning;
      if (warning != null) {
        lines.add('· $warning');
      }
      lines.add('· 地址来源：${_envAgentBaseUrl == '' ? "代码（app_config.dart）" : "配置文件 / 命令行注入"}');
      final String? hint = agentHint;
      if (hint != null) {
        lines.add('· $hint');
      }
    } else {
      lines.add('智能体：未配置（不需要可以留空）');
    }

    if (!llmReady) {
      lines.add('');
      lines.add('排查：如果刚在 config/app_config.json 里填了 Key，'
          '需要在 Run 配置的 Additional run args 里加上 '
          '--dart-define-from-file=config/app_config.json，然后**重新 Run**；'
          '热重载不会重新读取配置。');
    }
    return lines;
  }

  static String _normalize(String url) {
    String value = url.trim().toLowerCase();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
