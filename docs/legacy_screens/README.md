# 归档：被"对话式提取"取代的旧界面

这 3 个文件已不参与编译（后缀改成 `.txt` 存档），仅作参考。

| 文件 | 原用途 | 现状 |
| --- | --- | --- |
| `recognize_page.dart.txt` | 拍照识别页：拍照/相册 → 处理进度 → 失败/权限态 | 由 `lib/ui/pages/chat_page.dart` 取代 |
| `recognize_controller.dart.txt` | 拍照识别状态机（OCR → 智能体/大模型/本地规则 → 音标） | 由 `lib/state/chat_controller.dart` 取代 |
| `confirm_words_page.dart.txt` | 识别结果确认页（逐条编辑、合并重复、校验音标） | 现在由智能体直接写库，逐条编辑改在「全部」页做 |

要恢复旧流程：把文件改回 `.dart` 放回原目录，并在 `home_page.dart` / `today_page.dart` 里
把 `ChatPage` 换回 `RecognizePage`。注意旧页面依赖的 `AgentService.extract`、`PhoneticLookup`
仍然保留，可直接复用。
