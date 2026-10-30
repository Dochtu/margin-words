import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'recognition_failure.dart';

/// 本地离线 OCR（Google ML Kit，拉丁字母识别，完全在本机运行）。
///
/// 只用于把图片变成文字，不上传任何图片。
class OcrService {
  const OcrService();

  /// 返回图片中被识别出的全部文字（按行拼接）。
  Future<String> recognize(String imagePath) async {
    final TextRecognizer recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final InputImage input = InputImage.fromFilePath(imagePath);
      final RecognizedText result = await recognizer.processImage(input);
      final String text = result.text;
      if (text.trim().isEmpty) {
        throw const RecognitionFailure(
          FailureKind.noText,
          '这张图片里没有识别到文字',
        );
      }
      return text;
    } on RecognitionFailure {
      rethrow;
    } catch (e) {
      throw RecognitionFailure(
        FailureKind.ocr,
        '本地文字识别失败',
        detail: e.toString(),
      );
    } finally {
      await recognizer.close();
    }
  }
}
