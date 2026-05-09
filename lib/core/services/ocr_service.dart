import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<RecognizedText?> processImage(InputImage inputImage) async {
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText;
    } catch (e) {
      debugPrint('OCR Error: $e');
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
