import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  late OnDeviceTranslator _translator;
  bool _isModelDownloaded = false;

  TranslationService() {
    _translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.indonesian,
    );
  }

  Future<void> ensureModelDownloaded() async {
    if (_isModelDownloaded) return;
    
    final modelManager = OnDeviceTranslatorModelManager();
    // Check if models exist, if not download
    final bool isSourceDownloaded = await modelManager.isModelDownloaded(TranslateLanguage.english.bcpCode);
    final bool isTargetDownloaded = await modelManager.isModelDownloaded(TranslateLanguage.indonesian.bcpCode);

    if (!isSourceDownloaded) {
      await modelManager.downloadModel(TranslateLanguage.english.bcpCode);
    }
    if (!isTargetDownloaded) {
      await modelManager.downloadModel(TranslateLanguage.indonesian.bcpCode);
    }
    
    _isModelDownloaded = true;
  }

  Future<String?> translate(String text) async {
    if (text.isEmpty) return null;
    try {
      await ensureModelDownloaded();
      final String translation = await _translator.translateText(text);
      return translation;
    } catch (e) {
      debugPrint('Translation Error: $e');
      return null;
    }
  }

  void dispose() {
    _translator.close();
  }
}
