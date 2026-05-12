import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ocrato/core/services/ocr_service.dart';
import 'package:ocrato/core/services/translation_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final OCRService _ocrService = OCRService();
  final TranslationService _translationService = TranslationService();
  
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  bool _isLive = true;
  Size? _imageSize;
  bool _isFlashEnabled = false;
  
  bool _isProcessing = false;
  String? _recognizedText;
  String? _translatedText;
  bool _isCameraReady = false;

  // Dynamic Scanner Box State
  Rect _scannerRect = const Rect.fromLTWH(50, 200, 300, 200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    
    // Initialize scanner rect based on screen size once available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      setState(() {
        _scannerRect = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 3),
          width: size.width * 0.8,
          height: size.height * 0.25,
        );
      });
    });
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
      // await _cameraController!.startImageStream(_processCameraImage); // Removed continuous stream
      if (mounted) {
        setState(() {
          _isCameraReady = true;
        });
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }

  Future<void> _scanNow() async {
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) return;
    
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      if (_isFlashEnabled) {
        await _cameraController!.setFlashMode(FlashMode.always);
      } else {
        await _cameraController!.setFlashMode(FlashMode.off);
      }
      
      final XFile photo = await _cameraController!.takePicture();
      
      // Turn off flash after capture if it was on
      if (_isFlashEnabled) {
        await _cameraController!.setFlashMode(FlashMode.off);
      }
      
      await _processStaticImage(photo.path);
    } catch (e) {
      debugPrint('Capture Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickImage() async {
    setState(() => _isProcessing = true);
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _pickedImage = image;
          _isLive = false;
          _recognizedText = null;
          _translatedText = null;
        });
        await _processStaticImage(image.path);
      }
    } catch (e) {
      debugPrint('Pick Image Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processStaticImage(String path) async {
    if (path.isEmpty) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final inputImage = InputImage.fromFilePath(path);
      
      // Get image dimensions
      final imageFile = File(path);
      final bytes = await imageFile.readAsBytes();
      final decodedImage = await decodeImageFromList(bytes);
      
      if (mounted) {
        setState(() {
          _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
        });
      }

      final recognizedText = await _ocrService.processImage(inputImage);
      if (recognizedText == null || recognizedText.blocks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada teks terdeteksi di gambar ini')),
          );
        }
        return;
      }

      final String? filteredText = _filterTextInStaticArea(recognizedText);
      
      if (filteredText != null) {
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
      debugPrint('Static Process Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleFlash() async {
    setState(() {
      _isFlashEnabled = !_isFlashEnabled;
    });
    HapticFeedback.lightImpact();
  }

  String? _filterTextInStaticArea(RecognizedText recognizedText) {
    if (_imageSize == null) return null;

    final screenSize = MediaQuery.of(context).size;
    final double screenWidth = screenSize.width;
    final double screenHeight = screenSize.height;
    final double imageWidth = _imageSize!.width;
    final double imageHeight = _imageSize!.height;

    // Scale calculation for BoxFit.contain
    final double scaleX = screenWidth / imageWidth;
    final double scaleY = screenHeight / imageHeight;
    final double fitScale = scaleX < scaleY ? scaleX : scaleY;

    final double displayedWidth = imageWidth * fitScale;
    final double displayedHeight = imageHeight * fitScale;
    
    final double offsetX = (screenWidth - displayedWidth) / 2;
    final double offsetY = (screenHeight - displayedHeight) / 2;

    final Rect scanRect = _scannerRect;
    
    // Collect all lines inside the box first for "Contexting" (Sorting)
    List<TextLine> linesInBox = [];

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final rect = line.boundingBox;
        
        final double left = rect.left * fitScale + offsetX;
        final double top = rect.top * fitScale + offsetY;
        final double right = rect.right * fitScale + offsetX;
        final double bottom = rect.bottom * fitScale + offsetY;
        
        final screenRect = Rect.fromLTRB(left, top, right, bottom);

        if (scanRect.overlaps(screenRect)) {
          if (scanRect.contains(screenRect.center) || 
              scanRect.intersect(screenRect).width * scanRect.intersect(screenRect).height > (screenRect.width * screenRect.height * 0.3)) {
            linesInBox.add(line);
          }
        }
      }
    }

    // Apply "Contexting": Sort lines by reading order (Top to Bottom, then Left to Right)
    // We use a small threshold (10 units) for "top" to group lines on the same level
    linesInBox.sort((a, b) {
      if ((a.boundingBox.top - b.boundingBox.top).abs() < 10) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return a.boundingBox.top.compareTo(b.boundingBox.top);
    });

    StringBuffer buffer = StringBuffer();
    for (var i = 0; i < linesInBox.length; i++) {
      final currentLine = linesInBox[i];
      String text = currentLine.text.trim();
      
      if (i > 0) {
        final prevLine = linesInBox[i - 1];
        // If current line is significantly below the previous line, add a newline
        // We check if the vertical distance between tops is greater than a threshold
        // Or if the horizontal position resets significantly to the left
        final verticalGap = (currentLine.boundingBox.top - prevLine.boundingBox.top).abs();
        final horizontalReset = currentLine.boundingBox.left < prevLine.boundingBox.left - 20;

        if (verticalGap > 15 || horizontalReset) {
          buffer.write('\n');
        } else {
          buffer.write(' ');
        }
      }
      
      // Smart joining for hyphens
      if (text.endsWith('-') && i + 1 < linesInBox.length) {
        buffer.write(text.substring(0, text.length - 1));
      } else {
        buffer.write(text);
      }
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : _refineCasing(result);
  }

  String _refineCasing(String text) {
    if (text.isEmpty) return text;

    // Split into sentences for better context processing
    final sentenceRegex = RegExp(r'(?<=[.!?])\s+');
    final sentences = text.split(sentenceRegex);
    
    final refinedSentences = sentences.map((sentence) {
      String trimmed = sentence.trim();
      if (trimmed.isEmpty) return "";

      // 1. Sentence Capitalization: Ensure first letter is uppercase
      String refined = trimmed[0].toUpperCase() + trimmed.substring(1);

      // 2. Acronym Preservation: If a word was mostly uppercase, make it fully uppercase
      // (Fixes OCR misidentifying one letter in an acronym)
      refined = refined.split(' ').map((word) {
        if (word.length > 2) {
          int upperCount = 0;
          for (var i = 0; i < word.length; i++) {
            if (word[i] == word[i].toUpperCase() && RegExp(r'[A-Z]').hasMatch(word[i])) {
              upperCount++;
            }
          }
          // If > 70% is uppercase, treat as Acronym
          if (upperCount / word.length > 0.7) return word.toUpperCase();
        }
        
        // Fix standalone "i" to "I"
        if (word.toLowerCase() == 'i') return 'I';
        
        return word;
      }).join(' ');

      return refined;
    }).toList();

    return refinedSentences.join(' ');
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
          // Camera Preview or Picked Image
          if (_isLive)
            _isCameraReady && _cameraController != null
                ? Center(child: CameraPreview(_cameraController!))
                : const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          else if (_pickedImage != null)
            Center(
              child: Image.file(
                File(_pickedImage!.path),
                fit: BoxFit.contain,
              ),
            ),

          // Interactive Overlay
          ScannerOverlay(
            rect: _scannerRect,
            onChanged: (newRect) {
              setState(() {
                _scannerRect = newRect;
              });
            },
          ),

          // Control Buttons
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: _pickImage,
                ),
                const SizedBox(width: 20),
                _MainScanButton(
                  isProcessing: _isProcessing,
                  onTap: _isLive 
                      ? _scanNow 
                      : (_pickedImage != null ? () => _processStaticImage(_pickedImage!.path) : _pickImage),
                ),
                const SizedBox(width: 20),
                // Camera/Live button - only shows when in static mode to go back
                _ControlButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: _isLive ? null : () {
                    setState(() {
                      _isLive = true;
                      _pickedImage = null;
                      _recognizedText = null;
                      _translatedText = null;
                    });
                  },
                  opacity: _isLive ? 0.3 : 1.0,
                ),
              ],
            ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.5, end: 0),
          ),

          // Results Card (Now above buttons)
          if (_translatedText != null)
            Positioned(
              bottom: 140,
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
                onClose: () {
                  setState(() {
                    _recognizedText = null;
                    _translatedText = null;
                  });
                },
              ).animate().fade().slideY(begin: 0.2, end: 0),
            ),
            
          // Top Bar Actions
          Positioned(
            top: 60,
            right: 20,
            child: Row(
              children: [
                if (_isLive)
                  _TopActionButton(
                    icon: _isFlashEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    onTap: _toggleFlash,
                    isActive: _isFlashEnabled,
                  ),
              ],
            ),
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
                  'Interactive Precision Scan',
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

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double opacity;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.1),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onTap,
              icon: Icon(icon, color: Colors.white, size: 24),
              padding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MainScanButton extends StatelessWidget {
  final bool isProcessing;
  final VoidCallback onTap;

  const _MainScanButton({
    required this.isProcessing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isProcessing ? null : onTap,
      child: Container(
        height: 70,
        width: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: isProcessing
              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
              : const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

class ScannerOverlay extends StatefulWidget {
  final Rect rect;
  final Function(Rect) onChanged;

  const ScannerOverlay({
    super.key,
    required this.rect,
    required this.onChanged,
  });

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay> {
  Offset? _startGlobalPosition;
  Rect? _startRect;
  bool _hasMoved = false;
  double _accumulatedDist = 0;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final rect = widget.rect;

    return Stack(
      children: [
        // Darkened background with a hole
        ClipPath(
          clipper: InvertedRectClipper(rect),
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),

        // Main Draggable Area
        Positioned.fromRect(
          rect: rect.inflate(30),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _startGlobalPosition = details.globalPosition;
              _startRect = rect;
              _hasMoved = false;
            },
            onPanUpdate: (details) {
              if (_startGlobalPosition == null || _startRect == null) return;

              final deltaX = details.globalPosition.dx - _startGlobalPosition!.dx;
              final deltaY = details.globalPosition.dy - _startGlobalPosition!.dy;

              // Add a small threshold to avoid "slippery" jitter
              if (!_hasMoved && (deltaX.abs() < 2 && deltaY.abs() < 2)) return;
              _hasMoved = true;

              final double newLeft = _startRect!.left + deltaX;
              final double newTop = _startRect!.top + deltaY;
              
              var newRect = Rect.fromLTWH(newLeft, newTop, rect.width, rect.height);
              
              // Stable Clamping
              newRect = Rect.fromLTWH(
                newRect.left.clamp(5.0, screenSize.width - rect.width - 5),
                newRect.top.clamp(80.0, screenSize.height - rect.height - 140),
                rect.width,
                rect.height,
              );

              widget.onChanged(newRect);
            },
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.all(30),
              child: CustomPaint(
                painter: BoxPainter(),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Resize Handle (Bottom Right)
        Positioned(
          left: rect.right - 30,
          top: rect.bottom - 30,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              final newWidth = (rect.width + details.delta.dx).clamp(80.0, screenSize.width - rect.left - 10);
              final newHeight = (rect.height + details.delta.dy).clamp(40.0, screenSize.height - rect.top - 140);
              
              widget.onChanged(Rect.fromLTWH(rect.left, rect.top, newWidth, newHeight));
              
              // Throttled tactile feedback: only vibrate every 20 pixels of movement
              _accumulatedDist += details.delta.distance;
              if (_accumulatedDist > 20.0) {
                HapticFeedback.selectionClick();
                _accumulatedDist = 0;
              }
            },
            child: Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(15),
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class InvertedRectClipper extends CustomClipper<Path> {
  final Rect rect;
  InvertedRectClipper(this.rect);

  @override
  Path getClip(Size size) {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(InvertedRectClipper oldClipper) => oldClipper.rect != rect;
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
  final VoidCallback onClose;

  const ResultCard({
    super.key,
    required this.originalText,
    required this.translatedText,
    required this.onCopy,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'RESULT',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_all_rounded, size: 22, color: Color(0xFF6C63FF)),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 22, color: Colors.white54),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              translatedText,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ORIGINAL TEXT',
                    style: GoogleFonts.outfit(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF6C63FF),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    originalText,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _TopActionButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? const Color(0xFF6C63FF) : Colors.black38,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
        padding: const EdgeInsets.all(12),
      ),
    ).animate(target: isActive ? 1 : 0).shimmer();
  }
}
