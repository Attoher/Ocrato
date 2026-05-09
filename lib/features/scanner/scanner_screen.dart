import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ocrato/core/services/ocr_service.dart';
import 'package:ocrato/core/services/translation_service.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final OCRService _ocrService = OCRService();
  final TranslationService _translationService = TranslationService();
  
  bool _isProcessing = false;
  String? _recognizedText;
  String? _translatedText;
  bool _isCameraReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status.isDenied) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21, // Better for Android OCR
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);
      if (mounted) {
        setState(() {
          _isCameraReady = true;
        });
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      final recognizedText = await _ocrService.processImage(inputImage);
      if (recognizedText == null || recognizedText.blocks.isEmpty) return;

      // Filter text inside the precision box
      final String? filteredText = _filterTextInArea(recognizedText, image);
      
      if (filteredText != null && filteredText != _recognizedText) {
        final translation = await _translationService.translate(filteredText);
        
        if (mounted) {
          setState(() {
            _recognizedText = filteredText;
            _translatedText = translation;
          });
          HapticFeedback.lightImpact();
        }
      }
    } catch (e) {
      debugPrint('Processing Error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 1000));
      _isProcessing = false;
    }
  }

  String? _filterTextInArea(RecognizedText recognizedText, CameraImage image) {
    final screenSize = MediaQuery.of(context).size;
    
    // Scanner box dimensions (from ScannerOverlay)
    final double boxWidth = screenSize.width * 0.8;
    final double boxHeight = screenSize.height * 0.3;
    final double left = (screenSize.width - boxWidth) / 2;
    final double top = (screenSize.height - boxHeight) / 2;
    final Rect scanRect = Rect.fromLTWH(left, top, boxWidth, boxHeight);

    // Map image coordinates to screen coordinates
    // Assuming portrait orientation and specific scaling
    final double scaleX = screenSize.width / image.height; // Height because of rotation
    final double scaleY = screenSize.height / image.width;

    StringBuffer buffer = StringBuffer();
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final rect = line.boundingBox;
        
        // Convert rect to screen coordinates
        // This is a simplified mapping that works for most portrait Android/iOS devices
        final screenRect = Rect.fromLTRB(
          rect.left * scaleX,
          rect.top * scaleY,
          rect.right * scaleX,
          rect.bottom * scaleY,
        );

        if (scanRect.overlaps(screenRect)) {
          buffer.write('${line.text} ');
        }
      }
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageRotation = InputImageRotationValue.fromRawValue(
            _cameraController!.description.sensorOrientation) ??
        InputImageRotation.rotation0deg;

      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (e) {
      debugPrint('Conversion Error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _ocrService.dispose();
    _translationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraReady && _cameraController != null)
            Center(
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),

          // Overlay Box
          const ScannerOverlay(),

          // Results Card (Floating CTA)
          if (_translatedText != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: ResultCard(
                originalText: _recognizedText ?? '',
                translatedText: _translatedText ?? '',
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _translatedText!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Teks disalin!')),
                  );
                },
              ).animate().fade().slideY(begin: 0.2, end: 0),
            ),
            
          // Top Status Bar
          Positioned(
            top: 60,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OCRATO',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.white,
                  ),
                ).animate().fadeIn(duration: 1.seconds),
                Text(
                  'Offline Precision Scan',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth * 0.8;
        final double height = constraints.maxHeight * 0.3;
        
        return Stack(
          children: [
            // Darken outside
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.5),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Border & Corners
            Align(
              alignment: Alignment.center,
              child: CustomPaint(
                size: Size(width, height),
                painter: BoxPainter(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class BoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6C63FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final path = Path();
    double cornerSize = 30.0;

    // Top Left
    path.moveTo(0, cornerSize);
    path.lineTo(0, 0);
    path.lineTo(cornerSize, 0);

    // Top Right
    path.moveTo(size.width - cornerSize, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, cornerSize);

    // Bottom Right
    path.moveTo(size.width, size.height - cornerSize);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width - cornerSize, size.height);

    // Bottom Left
    path.moveTo(cornerSize, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, size.height - cornerSize);

    canvas.drawPath(path, paint);
    
    // Subtle inner pulse line
    final scanPaint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    canvas.drawRect(Rect.fromLTWH(5, 5, size.width - 10, size.height - 10), scanPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ResultCard extends StatelessWidget {
  final String originalText;
  final String translatedText;
  final VoidCallback onCopy;

  const ResultCard({
    super.key,
    required this.originalText,
    required this.translatedText,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ID',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF6C63FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Terjemahan',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 20, color: Colors.white70),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            translatedText,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            originalText,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.4),
              fontStyle: FontStyle.italic,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
