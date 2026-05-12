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
      
      final List<String> segments = text.split('\n');
      final List<String> translatedSegments = [];

      for (final segment in segments) {
        if (segment.trim().isEmpty) {
          translatedSegments.add('');
        } else {
          String translated = await _translator.translateText(segment);
          // Post-process: Preserve Proper Nouns and Brand Names casing
          translated = _preserveOriginalCasing(segment, translated);
          translatedSegments.add(translated);
        }
      }

      return translatedSegments.join('\n');
    } catch (e) {
      debugPrint('Translation Error: $e');
      return null;
    }
  }

  /// Restores original casing for words that were not actually translated 
  /// (e.g. Names, Brand Names like 'Ocrato', Technical terms)
  String _preserveOriginalCasing(String source, String target) {
    final sourceWords = source.split(RegExp(r'\s+'));
    String refinedTarget = target;

    for (final sWord in sourceWords) {
      if (sWord.length < 3) continue; // Skip very short words
      
      // Use regex to find the word in target case-insensitively
      // We look for the source word but allow different casing in the target
      final escapedWord = RegExp.escape(sWord);
      final regex = RegExp(escapedWord, caseSensitive: false);
      
      refinedTarget = refinedTarget.replaceAllMapped(regex, (match) {
        // If the translation kept the word but changed the case, 
        // we revert it to the original source case.
        return sWord;
      });
    }
    
    return refinedTarget;
  }

  void dispose() {
    _translator.close();
  }
}
