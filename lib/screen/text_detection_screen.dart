import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

class TextDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const TextDetectionScreen({super.key, required this.cameras});

  @override
  State<TextDetectionScreen> createState() => _TextDetectionScreenState();
}

class _TextDetectionScreenState extends State<TextDetectionScreen> with WidgetsBindingObserver {
  late CameraController _cameraController;
  bool isCameraReady = false;
  String _displayedText = "Initialisation...";
  String _lastStableText = "";
  String detectedLanguage = "Inconnu";
  final TextRecognizer _textRecognizer = TextRecognizer();
  final LanguageIdentifier _languageIdentifier = LanguageIdentifier(confidenceThreshold: 0.5);
  bool _isDisposed = false;
  bool _useLiveFeed = true;
  bool _isTtsEnabled = false;
  bool _freezeText = false;
  final FlutterTts _tts = FlutterTts();
  final _isProcessing = ValueNotifier<bool>(false);
  DateTime _lastProcessed = DateTime.now();
  DateTime? _lastValidTextTime;
  Duration _processingInterval = const Duration(milliseconds: 1500);
  bool _isHighContrast = false;
  double _textScaleFactor = 1.0;
  bool _isDarkMode = true;

  // Palette de couleurs
  Color get primaryColor => _isDarkMode
      ? const Color(0xFF1976D2)
      : const Color(0xFF2196F3);
  Color get darkColor => _isDarkMode
      ? const Color(0xFF0D47A1)
      : const Color(0xFF1565C0);
  Color get lightColor => _isDarkMode
      ? const Color(0xFFBBDEFB)
      : const Color(0xFFE3F2FD);
  Color get accentColor => _isDarkMode
      ? const Color(0xFF448AFF)
      : const Color(0xFF2979FF);
  Color get backgroundColor => _isDarkMode
      ? const Color(0xFF121212)
      : const Color(0xFFE3F2FD);
  Color get cardColor => _isDarkMode
      ? Colors.grey[900]!
      : Colors.white;
  Color get textColor => _isDarkMode
      ? Colors.white
      : Colors.black87;

  static const Map<String, String> _languageToTtsCode = {
    "en": "en-US",
    "fr": "fr-FR",
    "es": "es-ES",
    "de": "de-DE",
    "it": "it-IT",
    "pt": "pt-PT",
    "ru": "ru-RU",
    "zh": "zh-CN",
    "ja": "ja-JP",
    "ko": "ko-KR",
  };
  static const Map<String, String> _languageToName = {
    "en": "Anglais",
    "fr": "Français",
    "es": "Espagnol",
    "de": "Allemand",
    "it": "Italien",
    "pt": "Portugais",
    "ru": "Russe",
    "zh": "Chinois",
    "ja": "Japonais",
    "ko": "Coréen",
    "und": "Inconnu",
  };
  static const String _defaultTtsLanguage = "fr-FR";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _initializeTts();
    _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tts.speak("Écran de détection de texte. Prêt à détecter.");
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_isDisposed && mounted) {
      setState(() {
        _isHighContrast = prefs.getBool('highContrast') ?? false;
        _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.0;
        _isDarkMode = prefs.getBool('darkMode') ?? true;
      });
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('highContrast', _isHighContrast);
    await prefs.setDouble('textScaleFactor', _textScaleFactor);
    await prefs.setBool('darkMode', _isDarkMode);
  }

  Future<void> _initializeCamera() async {
    if (_isDisposed) return;
    if (!await _checkPermissions()) {
      _updateDisplayText("Permission caméra ou stockage refusée");
      _tts.speak("Permission caméra ou stockage refusée.");
      return;
    }
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final camera = widget.cameras.isNotEmpty
            ? widget.cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => widget.cameras.first,
        )
            : throw Exception("Aucune caméra disponible");
        _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController.initialize();
        if (!mounted || _isDisposed) return;
        setState(() {
          isCameraReady = true;
        });
        _updateDisplayText("Détection en cours...");
        if (_useLiveFeed) {
          _startImageStream();
        }
        return;
      } catch (e) {
        if (attempt == 3) {
          _updateDisplayText("Erreur caméra: $e");
          _tts.speak("Erreur caméra.");
          Vibration.vibrate(pattern: [0, 200, 100, 200]);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  void _updateDisplayText(String newText) {
    if (_freezeText || newText.isEmpty) return;

    // Ne pas mettre à jour si le texte est identique ou trop similaire
    if (newText == _displayedText ||
        _calculateSimilarity(newText, _displayedText) > 0.8) {
      return;
    }

    // Pour "Aucun texte détecté", attendre 5 secondes avant de l'afficher
    if (newText == "Aucun texte détecté") {
      if (_lastValidTextTime == null ||
          DateTime.now().difference(_lastValidTextTime!).inSeconds > 5) {
        setState(() => _displayedText = newText);
        _checkNoTextDetected();
      }
    } else {
      _lastValidTextTime = DateTime.now();
      _lastStableText = newText;
      setState(() => _displayedText = newText);
    }
  }

  double _calculateSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0;
    final words1 = text1.split(' ');
    final words2 = text2.split(' ');
    final intersection = words1.where((w) => words2.contains(w)).length;
    return intersection / max(words1.length, words2.length);
  }

  void _checkNoTextDetected() {
    if (_displayedText == "Détection en cours..." || _displayedText == "Aucun texte détecté") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Aucun texte détecté. Essayez d'améliorer l'éclairage ou de rapprocher la caméra."),
        ),
      );
      _tts.speak("Aucun texte détecté. Essayez d'améliorer l'éclairage ou de rapprocher la caméra.");
    }
  }

  Future<bool> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final storageStatus = await Permission.storage.status;
    if (!cameraStatus.isGranted) {
      final cameraResult = await Permission.camera.request();
      if (cameraResult.isPermanentlyDenied && mounted) {
        _showPermissionDialog("Caméra");
        return false;
      }
    }
    if (!storageStatus.isGranted && !_useLiveFeed) {
      final storageResult = await Permission.storage.request();
      if (storageResult.isPermanentlyDenied && mounted) {
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
        content: Text('L\'accès à $permission est requis pour la détection de texte.'),
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

  Future<void> _initializeTts() async {
    try {
      await _tts.setLanguage(_defaultTtsLanguage);
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur d'initialisation TTS")),
        );
      }
    }
  }

  Future<String> _detectLanguage(String text) async {
    if (text.isEmpty || text == "Aucun texte détecté") return _defaultTtsLanguage;
    try {
      final String langCode = await _languageIdentifier.identifyLanguage(text);
      if (langCode == "und") {
        return _defaultTtsLanguage;
      }
      final ttsCode = _languageToTtsCode[langCode] ?? _defaultTtsLanguage;
      bool isAvailable = await _tts.isLanguageAvailable(ttsCode);
      return isAvailable ? ttsCode : _defaultTtsLanguage;
    } catch (e) {
      return _defaultTtsLanguage;
    }
  }

  void _startImageStream() {
    if (_isDisposed || !isCameraReady || !_cameraController.value.isInitialized) return;

    _cameraController.startImageStream((CameraImage image) async {
      if (_isProcessing.value || !_useLiveFeed || _freezeText) return;

      final now = DateTime.now();
      if (now.difference(_lastProcessed) < _processingInterval) return;

      _isProcessing.value = true;
      _lastProcessed = now;

      try {
        final inputImage = await _convertToInputImage(image);
        final recognizedText = await _textRecognizer.processImage(inputImage);

        if (!mounted || _isDisposed) return;

        final text = recognizedText.text.trim().isNotEmpty
            ? recognizedText.text.trim()
            : "Aucun texte détecté";

        if (_calculateSimilarity(text, _lastStableText) < 0.6) {
          _updateDisplayText(text);
          final language = await _detectLanguage(text);
          setState(() {
            detectedLanguage = _languageToName[_languageToTtsCode.entries
                .firstWhere((e) => e.value == language,
                orElse: () => MapEntry("und", _defaultTtsLanguage))
                .key] ?? "Inconnu";
          });
          if (_isTtsEnabled && text != "Aucun texte détecté") {
            await _speakText(text, language);
          }
        }
      } catch (e) {
        debugPrint("Erreur traitement image: $e");
        if (mounted && !_freezeText) {
          setState(() => _displayedText = "Erreur de détection");
        }
      } finally {
        if (!_isDisposed) {
          _isProcessing.value = false;
        }
      }
    });
  }

  Future<void> _capturePhoto() async {
    if (_isDisposed || !isCameraReady || _isProcessing.value) return;
    try {
      _isProcessing.value = true;
      if (_cameraController.value.isStreamingImages) {
        await _cameraController.stopImageStream();
      }
      final XFile photo = await _cameraController.takePicture();
      await _processCapturedPhoto(photo);
      Vibration.vibrate(duration: 100);
      _tts.speak("Photo capturée.");
      if (_useLiveFeed && isCameraReady) {
        _startImageStream();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur de capture photo")),
        );
        _tts.speak("Erreur de capture.");
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
      _updateDisplayText(text);
      final language = await _detectLanguage(text);
      setState(() {
        detectedLanguage = _languageToName[_languageToTtsCode.entries
            .firstWhere((e) => e.value == language,
            orElse: () => MapEntry("und", _defaultTtsLanguage))
            .key] ??
            "Inconnu";
      });
      if (_isTtsEnabled && text != "Aucun texte détecté") {
        await _speakText(text, language);
      }
    } catch (e) {
      if (mounted) {
        _updateDisplayText("Erreur de détection");
        _tts.speak("Erreur de détection.");
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
      _updateDisplayText(text);
      final language = await _detectLanguage(text);
      setState(() {
        detectedLanguage = _languageToName[_languageToTtsCode.entries
            .firstWhere((e) => e.value == language,
            orElse: () => MapEntry("und", _defaultTtsLanguage))
            .key] ??
            "Inconnu";
      });
      Vibration.vibrate(duration: 100);
      _tts.speak("Image sélectionnée.");
      if (_isTtsEnabled && text != "Aucun texte détecté") {
        await _speakText(text, language);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur de détection")),
        );
        _tts.speak("Erreur de détection.");
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    }
  }

  Future<InputImage> _convertToInputImage(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    const format = InputImageFormat.nv21;
    final expectedSize = image.width * image.height * 1.5;
    if (bytes.length < expectedSize) {
      throw Exception("Données image invalides");
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
  }

  InputImageRotation _getInputImageRotation() {
    if (_isDisposed) return InputImageRotation.rotation0deg;
    final sensorOrientation = _cameraController.description.sensorOrientation;
    final deviceOrientation = MediaQuery.of(context).orientation;
    int rotationCompensation = sensorOrientation;
    if (Platform.isAndroid) {
      if (deviceOrientation == Orientation.portrait) {
        rotationCompensation = (sensorOrientation + 90) % 360;
      } else {
        rotationCompensation = sensorOrientation;
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

  Future<void> _speakText(String text, String language) async {
    if (text == "Aucun texte détecté" || !_isTtsEnabled) return;
    try {
      bool isAvailable = await _tts.isLanguageAvailable(language);
      if (!isAvailable) {
        await _tts.setLanguage(_defaultTtsLanguage);
      } else {
        await _tts.setLanguage(language);
      }
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur TTS")),
        );
      }
    }
  }

  void _toggleInputMode() {
    if (_isDisposed) return;
    setState(() {
      _useLiveFeed = !_useLiveFeed;
      _updateDisplayText(_useLiveFeed ? "Détection en cours..." : "Sélectionnez une image");
      detectedLanguage = "Inconnu";
      _lastValidTextTime = null;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_useLiveFeed ? "Mode flux en direct activé." : "Mode galerie activé.");
    if (_useLiveFeed && isCameraReady) {
      _startImageStream();
    } else {
      _cameraController.stopImageStream().catchError((e) {});
    }
  }

  void _toggleTts() {
    if (_isDisposed) return;
    setState(() {
      _isTtsEnabled = !_isTtsEnabled;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_isTtsEnabled ? "Synthèse vocale activée." : "Synthèse vocale désactivée.");
    if (!_isTtsEnabled) {
      _tts.stop();
    }
  }

  void _toggleHighContrast() {
    if (_isDisposed) return;
    setState(() {
      _isHighContrast = !_isHighContrast;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_isHighContrast ? "Mode contraste élevé activé." : "Mode contraste élevé désactivé.");
    _savePreferences();
  }

  void _toggleDarkMode() {
    if (_isDisposed) return;
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_isDarkMode ? "Mode sombre activé." : "Mode clair activé.");
    _savePreferences();
  }

  void _toggleFreezeText() {
    setState(() => _freezeText = !_freezeText);
    Vibration.vibrate(duration: 50);
    _tts.speak(_freezeText ? "Texte figé" : "Texte non figé");
  }

  Future<void> _copyToClipboard(String text) async {
    if (text.isEmpty || text == "Aucun texte détecté") return;
    await Clipboard.setData(ClipboardData(text: text));
    Vibration.vibrate(duration: 50);
    _tts.speak("Texte copié");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Texte copié !"),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearText() {
    if (_freezeText) {
      setState(() => _displayedText = "");
      Vibration.vibrate(duration: 50);
      _tts.speak("Texte effacé");
    }
  }

  void _updateTextScale(double value) {
    if (_isDisposed) return;
    setState(() {
      _textScaleFactor = value;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak("Taille du texte: ${value.toStringAsFixed(1)}");
    _savePreferences();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !isCameraReady || !_cameraController.value.isInitialized) return;
    if (state == AppLifecycleState.paused) {
      _cameraController.stopImageStream().catchError((e) {});
    } else if (state == AppLifecycleState.resumed && _useLiveFeed && !_cameraController.value.isStreamingImages) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isDisposed && mounted) {
          _startImageStream();
        }
      });
    }
  }

  Future<void> _cleanupResources() async {
    try {
      if (_cameraController.value.isStreamingImages) {
        await _cameraController.stopImageStream();
      }
      await _cameraController.dispose();
      await _textRecognizer.close();
      await _languageIdentifier.close();
      await _tts.stop();
      _isProcessing.dispose();
    } catch (e) {
      debugPrint("Erreur nettoyage: $e");
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
    if (_isDisposed) return const SizedBox.shrink();
    return WillPopScope(
      onWillPop: () async {
        await _cleanupResources();
        return true;
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
              "Détection de Texte",
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
            IconButton(
              icon: Icon(
                Icons.brightness_6,
                color: Colors.white,
                size: 26,
              ),
              onPressed: _toggleDarkMode,
              tooltip: 'Changer le thème',
            ),
            IconButton(
              icon: Icon(
                Icons.contrast,
                color: _isHighContrast ? accentColor : Colors.white,
                size: 26,
              ),
              onPressed: _toggleHighContrast,
              tooltip: 'Basculer le contraste',
            ),
            IconButton(
              icon: Icon(
                _isTtsEnabled ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
                size: 26,
              ),
              onPressed: _toggleTts,
              tooltip: 'Basculer la synthèse vocale',
            ),
            const SizedBox(width: 10),
          ],
        ),
        backgroundColor: _isHighContrast ? Colors.black : backgroundColor,
        body: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: _isHighContrast
                      ? null
                      : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      darkColor.withOpacity(0.7),
                      backgroundColor,
                    ],
                  ),
                  color: _isHighContrast ? Colors.black : null,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Column(
                    children: [
                      if (_useLiveFeed && isCameraReady)
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _isHighContrast ? Colors.white : primaryColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: CameraPreview(_cameraController),
                          ),
                        )
                      else
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: _isHighContrast ? Colors.grey[900] : cardColor,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _isHighContrast ? Colors.white : primaryColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              "Sélectionnez une image depuis la galerie",
                              style: TextStyle(
                                color: _isHighContrast ? Colors.white : textColor,
                                fontSize: 16 * _textScaleFactor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<bool>(
                        valueListenable: _isProcessing,
                        builder: (context, isProcessing, _) {
                          return isProcessing
                              ? CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(accentColor),
                          )
                              : _buildTextCard(
                            title: "Texte Détecté",
                            content: _displayedText,
                            icon: Icons.text_fields,
                            color: accentColor,
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildTextCard(
                        title: "Langue Détectée",
                        content: detectedLanguage,
                        icon: Icons.language,
                        color: lightColor,
                      ),
                      const SizedBox(height: 30),
                      FadeInUp(
                        delay: const Duration(milliseconds: 300),
                        child: GestureDetector(
                          onTap: _useLiveFeed ? _capturePhoto : _processGalleryImage,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: _isHighContrast
                                  ? Colors.white
                                  : _isProcessing.value ? Colors.red : primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_isProcessing.value)
                                  Pulse(
                                    infinite: true,
                                    child: Container(
                                      width: 90,
                                      height: 90,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: primaryColor.withOpacity(0.3),
                                      ),
                                    ),
                                  ),
                                Icon(
                                  _useLiveFeed ? Icons.camera_alt : Icons.image,
                                  size: 36,
                                  color: _isHighContrast ? Colors.black : Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _isHighContrast ? Colors.black : cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(
                  color: _isHighContrast ? Colors.white : Colors.grey.withOpacity(0.3),
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
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.camera,
                          color: _isHighContrast ? Colors.white : primaryColor,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Mode d'entrée",
                            style: TextStyle(
                              color: _isHighContrast ? Colors.white : textColor,
                              fontSize: 16 * _textScaleFactor,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isHighContrast ? Colors.white : primaryColor,
                            foregroundColor: _isHighContrast ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          onPressed: _toggleInputMode,
                          child: Text(
                            _useLiveFeed ? "Passer à la Galerie" : "Passer au Flux en Direct",
                            style: TextStyle(
                              color: _isHighContrast ? Colors.black : Colors.white,
                              fontSize: 14 * _textScaleFactor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Icon(
                          Icons.text_fields,
                          color: _isHighContrast ? Colors.white : primaryColor,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Taille du texte",
                            style: TextStyle(
                              color: _isHighContrast ? Colors.white : textColor,
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
                            inactiveColor: _isHighContrast ? Colors.grey : Colors.grey,
                            label: "Taille du texte: ${_textScaleFactor.toStringAsFixed(1)}",
                          ),
                        ),
                      ],
                    ),
                  ],
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
      color: _isHighContrast
          ? Colors.grey[900]
          : _isDarkMode
          ? color.withOpacity(0.15)
          : Colors.white,
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
                if (title == "Texte Détecté")
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _freezeText ? Icons.lock : Icons.lock_open,
                          color: _isHighContrast ? Colors.white : accentColor,
                          size: 20,
                        ),
                        onPressed: _toggleFreezeText,
                        tooltip: _freezeText ? 'Déverrouiller le texte' : 'Verrouiller le texte',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.copy,
                          color: _isHighContrast ? Colors.white : accentColor,
                          size: 20,
                        ),
                        onPressed: () => _copyToClipboard(content),
                        tooltip: 'Copier le texte',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: _isHighContrast ? Colors.white : accentColor,
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
            Container(
              constraints: BoxConstraints(
                minHeight: 80,
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: SingleChildScrollView(
                child: Text(
                  content,
                  style: TextStyle(
                    color: _isHighContrast ? Colors.white : textColor,
                    fontSize: 16 * _textScaleFactor,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}