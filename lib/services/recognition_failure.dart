/// 识别流程中可能出现的失败类型，用来决定“提示文案 / 是否可重试 / 是否降级”。
enum FailureKind {
  /// 没有配置大模型 Key（自动降级为本地规则解析）
  noKey,

  /// OCR 没有识别到任何文字
  noText,

  /// 图片里没有可用的英文单词
  noWords,

  /// 网络不可达 / DNS / 连接被拒
  network,

  /// 请求超时
  timeout,

  /// 401 / 403：Key 无效或无权限
  unauthorized,

  /// 402 / 429 + 额度相关：余额或额度不足
  quota,

  /// 429：触发限流
  rateLimit,

  /// 5xx：服务端错误
  server,

  /// 返回内容不是可解析的 JSON
  badResponse,

  /// 本地 OCR 失败
  ocr,

  /// 其他
  unknown,
}

class RecognitionFailure implements Exception {
  const RecognitionFailure(this.kind, this.message, {this.detail});

  final FailureKind kind;
  final String message;
  final String? detail;

  /// 是否可以用“本地规则解析”兜底
  bool get canUseLocal => const <FailureKind>{
        FailureKind.noKey,
        FailureKind.network,
        FailureKind.timeout,
        FailureKind.unauthorized,
        FailureKind.quota,
        FailureKind.rateLimit,
        FailureKind.server,
        FailureKind.badResponse,
        FailureKind.noWords,
      }.contains(kind);

  /// 是否需要重新拍照（而不是只重试网络）
  bool get needRepick => kind == FailureKind.ocr || kind == FailureKind.noText;

  String get title {
    switch (kind) {
      case FailureKind.noKey:
        return '未配置大模型';
      case FailureKind.noText:
        return '没有识别到文字';
      case FailureKind.noWords:
        return '没有找到英文单词';
      case FailureKind.network:
        return '网络不可用';
      case FailureKind.timeout:
        return '请求超时';
      case FailureKind.unauthorized:
        return 'API Key 无效';
      case FailureKind.quota:
        return '额度不足';
      case FailureKind.rateLimit:
        return '请求过于频繁';
      case FailureKind.server:
        return '服务端异常';
      case FailureKind.badResponse:
        return '返回格式无法解析';
      case FailureKind.ocr:
        return '本地识别失败';
      case FailureKind.unknown:
        return '识别失败';
    }
  }

  String get suggestion {
    switch (kind) {
      case FailureKind.noKey:
        return '在 config/app_config.json 里填好 LLM_API_KEY，并用 --dart-define-from-file=config/app_config.json 重新运行；或直接使用本地规则识别。';
      case FailureKind.noText:
        return '请让单词/音标在画面中占更大比例，避免反光与倾斜，或改用相册里更清晰的照片。';
      case FailureKind.noWords:
        return '这张图片里可能只有中文或题目说明。可以换一张包含英文单词的照片，或手动添加。';
      case FailureKind.network:
        return '检查手机网络与代理设置；只有大模型提取这一步需要联网。';
      case FailureKind.timeout:
        return '网络较慢，可稍后重试；本地规则识别不依赖网络。';
      case FailureKind.unauthorized:
        return '确认 Key 是否复制完整、是否与 Base URL 属于同一家服务商。';
      case FailureKind.quota:
        return '账户余额或调用额度已用尽，请充值或更换 Key；也可以先用本地规则识别。';
      case FailureKind.rateLimit:
        return '稍等几十秒再试，或降低一次上传的单词数量。';
      case FailureKind.server:
        return '服务商临时故障，稍后重试即可。';
      case FailureKind.badResponse:
        return '模型输出不是标准 JSON，重试一次通常可恢复。';
      case FailureKind.ocr:
        return '确认照片未损坏；也可以直接从相册重新选择一张。';
      case FailureKind.unknown:
        return '重试一次；若持续失败，请改用本地规则识别。';
    }
  }

  @override
  String toString() => 'RecognitionFailure(${kind.name}): $message';
}
