import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:animate_do/animate_do.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:translator/translator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:vibration/vibration.dart';

class TextTranslationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const TextTranslationScreen({super.key, required this.cameras});

  @override
  State<TextTranslationScreen> createState() => _TextTranslationScreenState();
}

class _TextTranslationScreenState extends State<TextTranslationScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool isCameraReady = false;
  String originalText = "Détection...";
  String translatedText = "";
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _isDisposed = false;
  bool _useLiveFeed = true;
  bool _isHighContrast = false;
  bool _isDarkMode = true;
  bool _isTtsEnabled = true;
  double _textScaleFactor = 1.0;
  final ValueNotifier<bool> _isProcessing = ValueNotifier<bool>(false);
  DateTime _lastProcessed = DateTime.now();
  final Duration _processingInterval = const Duration(seconds: 3);
  String _selectedLanguage = 'en';
  final GoogleTranslator _translator = GoogleTranslator();
  bool _isVisible = true;
  final FlutterTts _tts = FlutterTts();
  bool _isLiveFeedPaused = false;
  String? _cameraError;
  Timer? _debounceTimer;
  String _processingText = "Détection...";

  static const Map<String, String> _languageMap = {
    'en': 'Anglais',
    'fr': 'Français',
    'es': 'Espagnol',
    'de': 'Allemand',
    'it': 'Italien',
    'pt': 'Portugais',
    'ru': 'Russe',
    'zh': 'Chinois',
    'ja': 'Japonais',
    'ko': 'Coréen',
  };

  Color get primaryColor => _isHighContrast
      ? Colors.white
      : _isDarkMode
      ? const Color(0xFF1976D2)
      : const Color(0xFF2196F3);
  Color get darkColor => _isHighContrast
      ? Colors.black
      : _isDarkMode
      ? const Color(0xFF0D47A1)
      : const Color(0xFF1565C0);
  Color get lightColor => _isHighContrast
      ? Colors.grey[300]!
      : _isDarkMode
      ? const Color(0xFFBBDEFB)
      : const Color(0xFFE3F2FD);
  Color get accentColor => _isHighContrast
      ? Colors.white
      : _isDarkMode
      ? const Color(0xFF448AFF)
      : const Color(0xFF2979FF);
  Color get backgroundColor => _isHighContrast
      ? Colors.black
      : _isDarkMode
      ? const Color(0xFF121212)
      : const Color(0xFFE3F2FD);
  Color get cardColor => _isHighContrast
      ? Colors.grey[900]!
      : _isDarkMode
      ? Colors.white.withOpacity(0.08)
      : Colors.white;
  Color get textColor => _isHighContrast
      ? Colors.white
      : _isDarkMode
      ? Colors.white
      : Colors.black87;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _loadPreferences();
    _initTTS();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isTtsEnabled) {
        _tts.speak("Écran de traduction de texte. Prêt à détecter.");
      }
    });
  }

  Future<void> _initTTS() async {
    try {
      await _tts.setLanguage(_getLanguageCodeForTTS(_selectedLanguage));
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(_isTtsEnabled ? 1.0 : 0.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur TTS: $e")),
        );
      }
    }
  }

  String _getLanguageCodeForTTS(String languageCode) {
    switch (languageCode) {
      case 'fr':
        return 'fr-FR';
      case 'es':
        return 'es-ES';
      case 'de':
        return 'de-DE';
      case 'it':
        return 'it-IT';
      case 'pt':
        return 'pt-PT';
      case 'ru':
        return 'ru-RU';
      case 'zh':
        return 'zh-CN';
      case 'ja':
        return 'ja-JP';
      case 'ko':
        return 'ko-KR';
      default:
        return 'en-US';
    }
  }

  Future<void> _speak(String text) async {
    if (!_isTtsEnabled || text.isEmpty || text == "Aucun texte détecté") return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur TTS: $e")),
        );
      }
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_isDisposed && mounted) {
      setState(() {
        _isHighContrast = prefs.getBool('highContrast') ?? false;
        _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.0;
        _isDarkMode = prefs.getBool('darkMode') ?? true;
        _isTtsEnabled = prefs.getBool('ttsEnabled') ?? true;
      });
      await _tts.setVolume(_isTtsEnabled ? 1.0 : 0.0);
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('highContrast', _isHighContrast);
    await prefs.setDouble('textScaleFactor', _textScaleFactor);
    await prefs.setBool('darkMode', _isDarkMode);
    await prefs.setBool('ttsEnabled', _isTtsEnabled);
  }

  Future<void> _initializeCamera() async {
    if (_isDisposed) return;
    if (!await _checkPermissions()) {
      setState(() {
        _cameraError = "Permission caméra ou stockage refusée";
        originalText = _cameraError!;
      });
      if (_isTtsEnabled) {
        _tts.speak("Permission caméra ou stockage refusée.");
      }
      Vibration.vibrate(pattern: [0, 200, 100, 200]);
      return;
    }
    try {
      if (widget.cameras.isEmpty) {
        setState(() {
          _cameraError = "Aucune caméra disponible";
          originalText = _cameraError!;
        });
        if (_isTtsEnabled) {
          _tts.speak("Aucune caméra disponible.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
        return;
      }
      final camera = widget.cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      );
      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted || _isDisposed) return;
      setState(() {
        isCameraReady = true;
        _cameraError = null;
        originalText = "Détection...";
      });
      if (_useLiveFeed && _isVisible) {
        _startImageStream();
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() {
          _cameraError = "Erreur caméra: $e";
          originalText = _cameraError!;
        });
        if (_isTtsEnabled) {
          _tts.speak("Erreur caméra.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
        print("Camera initialization error: $e");
      }
    }
  }

  Future<bool> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final storageStatus = await Permission.storage.status;
    if (!cameraStatus.isGranted) {
      final result = await Permission.camera.request();
      if (result.isPermanentlyDenied && mounted) {
        _showPermissionDialog("Caméra");
        return false;
      }
    }
    if (!storageStatus.isGranted && !_useLiveFeed) {
      final result = await Permission.storage.request();
      if (result.isPermanentlyDenied && mounted) {
        _showPermissionDialog("Stockage");
        return false;
      }
    }
    return cameraStatus.isGranted && (_useLiveFeed || storageStatus.isGranted);
  }

  void _showPermissionDialog(String permission) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permission Requise'),
        content: Text('L\'accès à $permission est requis pour la traduction de texte.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => openAppSettings(),
            child: const Text('Ouvrir Paramètres'),
          ),
        ],
      ),
    );
  }

  bool _isTextSignificantlyDifferent(String newText, String oldText) {
    if (newText == oldText) return false;
    if (newText == "Aucun texte détecté" || oldText == "Aucun texte détecté") return true;
    int maxLength = newText.length > oldText.length ? newText.length : oldText.length;
    int differences = 0;
    for (int i = 0; i < maxLength; i++) {
      if (i >= newText.length || i >= oldText.length || newText[i] != oldText[i]) {
        differences++;
      }
    }
    return differences > maxLength * 0.2;
  }

  void _updateDisplayText(String newText, String newTranslatedText) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _processingText = newText;
      originalText = newText;
      translatedText = newTranslatedText;
    });
  }

  void _startImageStream() {
    if (_isDisposed || !isCameraReady || !_isVisible || _isLiveFeedPaused || _cameraController == null) return;
    _cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessing.value || !_useLiveFeed) return;
      if (DateTime.now().difference(_lastProcessed) < _processingInterval) return;
      _isProcessing.value = true;
      _lastProcessed = DateTime.now();
      try {
        await _processLiveImage(image);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur détection texte: $e")),
          );
          if (_isTtsEnabled) {
            _tts.speak("Erreur de détection.");
          }
          Vibration.vibrate(pattern: [0, 200, 100, 200]);
          print("Error in stream processing: $e");
        }
      } finally {
        if (!_isDisposed) {
          _isProcessing.value = false;
        }
      }
    });
  }

  Future<void> _processLiveImage(CameraImage cameraImage) async {
    if (_isDisposed) return;
    try {
      final inputImage = await _convertToInputImage(cameraImage);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (!mounted || _isDisposed) return;
      final text = recognizedText.text.isNotEmpty ? recognizedText.text : "Aucun texte détecté";
      if (_isTextSignificantlyDifferent(text, _processingText)) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
          if (!mounted || _isDisposed) return;
          String translated = "";
          if (text != "Aucun texte détecté") {
            translated = await _translateText(text);
            _speak(text);
          } else {
            _checkNoTextDetected();
          }
          _updateDisplayText(text, translated);
          print("Detected text: $text, Translated: $translated");
        });
      }
    } catch (e) {
      if (mounted) {
        _updateDisplayText("Erreur: $e", "");
        if (_isTtsEnabled) {
          _tts.speak("Erreur de détection.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
        print("Error in live image processing: $e");
      }
    }
  }

  void _checkNoTextDetected() {
    if (_processingText == "Détection..." && DateTime.now().difference(_lastProcessed).inSeconds > 5) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Aucun texte détecté. Essayez d'améliorer l'éclairage ou de rapprocher la caméra.")),
        );
        if (_isTtsEnabled) {
          _tts.speak("Aucun texte détecté. Essayez d'améliorer l'éclairage ou de rapprocher la caméra.");
        }
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_isDisposed || !isCameraReady || _isProcessing.value || _cameraController == null) return;
    try {
      _isProcessing.value = true;
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      final XFile photo = await _cameraController!.takePicture();
      await _processCapturedPhoto(photo);
      Vibration.vibrate(duration: 100);
      if (_isTtsEnabled) {
        _tts.speak("Photo capturée.");
      }
      if (_useLiveFeed && isCameraReady && _isVisible && !_isLiveFeedPaused) {
        _startImageStream();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur capture photo: $e")),
        );
        if (_isTtsEnabled) {
          _tts.speak("Erreur de capture.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    } finally {
      if (!_isDisposed) {
        _isProcessing.value = false;
      }
    }
  }

  Future<void> _processCapturedPhoto(XFile photo) async {
    if (_isDisposed) return;
    try {
      final inputImage = InputImage.fromFilePath(photo.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (!mounted || _isDisposed) return;
      final text = recognizedText.text.isNotEmpty ? recognizedText.text : "Aucun texte détecté";
      final translated = text == "Aucun texte détecté" ? "" : await _translateText(text);
      _updateDisplayText(text, translated);
      if (text != "Aucun texte détecté") {
        _speak(text);
      }
    } catch (e) {
      if (mounted) {
        _updateDisplayText("Erreur: $e", "");
        if (_isTtsEnabled) {
          _tts.speak("Erreur de détection.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    }
  }

  Future<void> _processGalleryImage() async {
    if (_isDisposed) return;
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (!mounted || _isDisposed) return;
      final text = recognizedText.text.isNotEmpty ? recognizedText.text : "Aucun texte détecté";
      final translated = text == "Aucun texte détecté" ? "" : await _translateText(text);
      _updateDisplayText(text, translated);
      Vibration.vibrate(duration: 100);
      if (_isTtsEnabled) {
        _tts.speak("Image sélectionnée.");
      }
      if (text != "Aucun texte détecté") {
        _speak(text);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur détection texte: $e")),
        );
        if (_isTtsEnabled) {
          _tts.speak("Erreur de détection.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    }
  }

  Future<String> _translateText(String text) async {
    if (text.isEmpty || text == "Aucun texte détecté") return "";
    try {
      final translation = await _translator.translate(
        text,
        to: _selectedLanguage,
      );
      if (translation.text.isNotEmpty && _isTtsEnabled) {
        await _tts.setLanguage(_getLanguageCodeForTTS(_selectedLanguage));
        _speak(translation.text);
      }
      return translation.text;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur de traduction: $e")),
        );
        if (_isTtsEnabled) {
          _tts.speak("Erreur de traduction.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
      return "Erreur de traduction";
    }
  }

  Future<InputImage> _convertToInputImage(CameraImage image) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      const format = InputImageFormat.nv21;
      final expectedSize = image.width * image.height * 1.5;
      if (bytes.length < expectedSize) {
        throw Exception("Données image invalides: taille ${bytes.length} ≠ $expectedSize");
      }
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _getInputImageRotation(),
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur conversion image: $e")),
        );
        if (_isTtsEnabled) {
          _tts.speak("Erreur de conversion d'image.");
        }
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
      rethrow;
    }
  }

  InputImageRotation _getInputImageRotation() {
    if (_isDisposed || _cameraController == null) return InputImageRotation.rotation0deg;
    final sensorOrientation = _cameraController!.description.sensorOrientation;
    final deviceOrientation = MediaQuery.of(context).orientation;
    int rotationCompensation = sensorOrientation;
    if (Platform.isAndroid) {
      if (deviceOrientation == Orientation.portrait) {
        rotationCompensation = (sensorOrientation + 90) % 360;
      }
    } else if (Platform.isIOS) {
      if (deviceOrientation == Orientation.portrait) {
        rotationCompensation = (sensorOrientation - 90 + 360) % 360;
      }
    }
    switch (rotationCompensation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void _toggleInputMode() {
    if (_isDisposed) return;
    setState(() {
      _useLiveFeed = !_useLiveFeed;
      _isLiveFeedPaused = false;
      _processingText = _useLiveFeed ? "Détection..." : "Sélectionner une image";
      originalText = _processingText;
      translatedText = "";
    });
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak(_useLiveFeed ? "Mode flux en direct activé." : "Mode galerie activé.");
    }
    if (_useLiveFeed && isCameraReady && _isVisible) {
      _startImageStream();
    } else {
      _cameraController?.stopImageStream().catchError((e) {});
    }
  }

  void _toggleHighContrast() {
    if (_isDisposed) return;
    setState(() {
      _isHighContrast = !_isHighContrast;
    });
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak(_isHighContrast ? "Mode contraste élevé activé." : "Mode contraste élevé désactivé.");
    }
    _savePreferences();
  }

  void _toggleDarkMode() {
    if (_isDisposed) return;
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak(_isDarkMode ? "Mode sombre activé." : "Mode clair activé.");
    }
    _savePreferences();
  }

  void _toggleTts() {
    if (_isDisposed) return;
    setState(() {
      _isTtsEnabled = !_isTtsEnabled;
    });
    _tts.setVolume(_isTtsEnabled ? 1.0 : 0.0);
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak("Synthèse vocale activée.");
    }
    _savePreferences();
  }

  void _updateTextScale(double value) {
    if (_isDisposed) return;
    setState(() {
      _textScaleFactor = value;
    });
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak("Taille du texte: ${value.toStringAsFixed(1)}");
    }
    _savePreferences();
  }

  void _toggleLiveFeedPause() {
    if (_isDisposed) return;
    setState(() {
      _isLiveFeedPaused = !_isLiveFeedPaused;
    });
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak(_isLiveFeedPaused ? "Flux en direct en pause." : "Flux en direct repris.");
    }
    if (!_isLiveFeedPaused && _useLiveFeed && _isVisible && isCameraReady) {
      _startImageStream();
    } else {
      _cameraController?.stopImageStream().catchError((e) {});
    }
  }

  void _clearText() {
    if (_isDisposed) return;
    setState(() {
      _processingText = _useLiveFeed ? "Détection..." : "Sélectionner une image";
      originalText = _processingText;
      translatedText = "";
    });
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak("Texte effacé.");
    }
  }

  void _copyText(String text) async {
    if (_isDisposed || text.isEmpty || text == "Aucun texte détecté" || text == "Détection...") return;
    await Clipboard.setData(ClipboardData(text: text));
    Vibration.vibrate(duration: 50);
    if (_isTtsEnabled) {
      _tts.speak("Texte copié dans le presse-papiers.");
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Texte copié !",
            style: TextStyle(color: _isHighContrast ? Colors.black : textColor),
          ),
          backgroundColor: _isHighContrast ? Colors.white : accentColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !isCameraReady || _cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.paused) {
      _cameraController!.stopImageStream().catchError((e) {});
      _tts.stop();
    } else if (state == AppLifecycleState.resumed &&
        _useLiveFeed &&
        _isVisible &&
        !_isLiveFeedPaused &&
        !_cameraController!.value.isStreamingImages) {
      _startImageStream();
    }
  }

  Future<void> _cleanupResources() async {
    try {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      if (_cameraController != null) {
        await _cameraController!.dispose();
      }
      await _textRecognizer.close();
      _isProcessing.dispose();
      _debounceTimer?.cancel();
      await _tts.stop();
    } catch (e) {
      print("Error cleaning up resources: $e");
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanupResources();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqData = MediaQuery.of(context);
    return VisibilityDetector(
      key: const Key('text_translation'),
      onVisibilityChanged: (info) {
        if (_isDisposed || !isCameraReady) return;
        setState(() {
          _isVisible = info.visibleFraction > 0;
        });
        if (_isVisible && _useLiveFeed && !_isLiveFeedPaused && _cameraController != null && !_cameraController!.value.isStreamingImages) {
          _startImageStream();
        } else if (!_isVisible && _cameraController != null && _cameraController!.value.isStreamingImages) {
          _cameraController!.stopImageStream().catchError((e) {});
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isHighContrast
                    ? [Colors.black, Colors.black]
                    : [darkColor, primaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: FadeInDown(
            child: Text(
              "Traduction de Texte",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22 * _textScaleFactor,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            ZoomIn(
              child: IconButton(
                icon: Icon(
                  Icons.brightness_6,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: _toggleDarkMode,
                tooltip: 'Changer le thème',
              ),
            ),
            ZoomIn(
              child: IconButton(
                icon: Icon(
                  Icons.contrast,
                  color: _isHighContrast ? accentColor : Colors.white,
                  size: 26,
                ),
                onPressed: _toggleHighContrast,
                tooltip: 'Basculer le contraste',
              ),
            ),
            ZoomIn(
              child: IconButton(
                icon: Icon(
                  _isTtsEnabled ? Icons.volume_up : Icons.volume_off,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: _toggleTts,
                tooltip: 'Basculer la synthèse vocale',
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: _useLiveFeed && isCameraReady && _cameraController != null && _cameraController!.value.isInitialized
                        ? AspectRatio(
                      aspectRatio: _cameraController!.value.aspectRatio,
                      child: CameraPreview(_cameraController!),
                    )
                        : Container(
                      color: cardColor,
                      child: Center(
                        child: _cameraError != null
                            ? Text(
                          _cameraError!,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16 * _textScaleFactor,
                          ),
                          textAlign: TextAlign.center,
                        )
                            : CircularProgressIndicator(
                          color: accentColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(
                      color: _isHighContrast ? Colors.white : Colors.blueGrey.withOpacity(0.3),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: _isProcessing,
                          builder: (context, isProcessing, _) {
                            return _buildTextCard(
                              title: "Texte Original",
                              content: originalText,
                              icon: Icons.text_snippet,
                              color: accentColor,
                              showActions: true,
                              isProcessing: isProcessing,
                            );
                          },
                        ),
                        const SizedBox(height: 15),
                        _buildTextCard(
                          title: "Traduction",
                          content: translatedText.isEmpty ? "La traduction apparaîtra ici" : translatedText,
                          icon: Icons.translate,
                          color: lightColor,
                          showActions: false,
                          isProcessing: false,
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            _buildActionButton(
                              icon: _useLiveFeed ? Icons.photo_library : Icons.camera_alt,
                              label: _useLiveFeed ? "Galerie" : "Caméra",
                              onPressed: _toggleInputMode,
                              color: primaryColor,
                            ),
                            if (!_useLiveFeed)
                              _buildActionButton(
                                icon: Icons.image_search,
                                label: "Choisir Image",
                                onPressed: _processGalleryImage,
                                color: primaryColor,
                              ),
                            if (_useLiveFeed && isCameraReady)
                              _buildActionButton(
                                icon: _isLiveFeedPaused ? Icons.play_arrow : Icons.pause,
                                label: _isLiveFeedPaused ? "Reprendre" : "Pause",
                                onPressed: _toggleLiveFeedPause,
                                color: _isLiveFeedPaused ? Colors.green : Colors.red,
                              ),
                            if (_useLiveFeed && isCameraReady)
                              _buildActionButton(
                                icon: Icons.camera,
                                label: "Capturer",
                                onPressed: _capturePhoto,
                                color: primaryColor,
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Icon(
                              Icons.language,
                              color: _isHighContrast ? Colors.white : lightColor,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Langue Cible",
                                style: TextStyle(
                                  color: _isHighContrast ? Colors.white : lightColor,
                                  fontSize: 16 * _textScaleFactor,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: mqData.size.width * 0.5,
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedLanguage,
                                dropdownColor: _isHighContrast ? Colors.grey[900] : darkColor,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14 * _textScaleFactor,
                                ),
                                items: _languageMap.entries.map((entry) {
                                  return DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(
                                      entry.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _selectedLanguage = value);
                                    _tts.setLanguage(_getLanguageCodeForTTS(value));
                                    if (originalText.isNotEmpty &&
                                        originalText != "Aucun texte détecté" &&
                                        originalText != "Détection...") {
                                      _translateText(originalText).then((translated) {
                                        setState(() => translatedText = translated);
                                      });
                                    }
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Icon(
                              Icons.text_fields,
                              color: _isHighContrast ? Colors.white : lightColor,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Taille du Texte",
                                style: TextStyle(
                                  color: _isHighContrast ? Colors.white : lightColor,
                                  fontSize: 16 * _textScaleFactor,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Slider(
                                value: _textScaleFactor,
                                min: 1.0,
                                max: 2.0,
                                divisions: 10,
                                onChanged: _updateTextScale,
                                activeColor: _isHighContrast ? Colors.white : accentColor,
                                inactiveColor: _isHighContrast ? Colors.grey : Colors.blueGrey,
                                label: "Taille du texte: ${_textScaleFactor.toStringAsFixed(1)}",
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextCard({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
    required bool showActions,
    required bool isProcessing,
  }) {
    return Card(
      elevation: _isHighContrast ? 0 : 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: _isHighContrast ? Colors.white : color.withOpacity(0.3),
          width: 1,
        ),
      ),
      color: _isHighContrast ? Colors.grey[900] : color.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      color: _isHighContrast ? Colors.white : color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: _isHighContrast ? Colors.white : color,
                        fontSize: 18 * _textScaleFactor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (showActions)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.volume_up,
                          color: _isHighContrast ? Colors.white : color,
                          size: 20,
                        ),
                        onPressed: () => _speak(content),
                        tooltip: 'Lire le texte',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.copy,
                          color: _isHighContrast ? Colors.white : color,
                          size: 20,
                        ),
                        onPressed: () => _copyText(content),
                        tooltip: 'Copier le texte',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: _isHighContrast ? Colors.white : color,
                          size: 20,
                        ),
                        onPressed: _clearText,
                        tooltip: 'Effacer le texte',
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Stack(
              children: [
                Container(
                  constraints: const BoxConstraints(minHeight: 80),
                  child: SingleChildScrollView(
                    child: Text(
                      content,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16 * _textScaleFactor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                if (isProcessing && _processingText != content)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(accentColor),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      icon: Icon(
        icon,
        size: 20,
        color: _isHighContrast ? Colors.black : Colors.white,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14 * _textScaleFactor,
          color: _isHighContrast ? Colors.black : Colors.white,
        ),
      ),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isHighContrast ? Colors.white : color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}