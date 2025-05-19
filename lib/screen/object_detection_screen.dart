import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import 'package:animate_do/animate_do.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../auth/auth_service.dart';
import '../pages/login_page.dart';

class ObjectDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ObjectDetectionScreen({super.key, required this.cameras});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> with WidgetsBindingObserver {
  late CameraController _cameraController;
  bool isCameraReady = false;
  String result = "Détection en cours...";
  late ImageLabeler _imageLabeler;
  bool isDetecting = false;
  bool _isDisposed = false;
  bool _isTorchOn = false;
  bool _isObstacleAlertEnabled = false;
  bool _isHighContrast = false;
  bool _isDarkMode = true;
  bool _isTtsEnabled = false;
  double _textScaleFactor = 1.0;
  final FlutterTts _tts = FlutterTts();
  DateTime _lastAlert = DateTime.now();
  final Duration _alertInterval = Duration(seconds: 2);
  static const double _confidenceThreshold = 0.5;

  Color get primaryColor => _isDarkMode ? const Color(0xFF1976D2) : const Color(0xFF2196F3);
  Color get darkColor => _isDarkMode ? const Color(0xFF0D47A1) : const Color(0xFF1565C0);
  Color get lightColor => _isDarkMode ? const Color(0xFFBBDEFB) : const Color(0xFFE3F2FD);
  Color get accentColor => _isDarkMode ? const Color(0xFF448AFF) : const Color(0xFF2979FF);
  Color get backgroundColor => _isDarkMode ? const Color(0xFF121212) : const Color(0xFFE3F2FD);
  Color get cardColor => _isDarkMode ? Colors.grey[900]! : Colors.white;
  Color get textColor => _isDarkMode ? Colors.white : Colors.black87;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _initializeMLKit();
    _initializeTts();
    _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tts.speak("Écran de détection d'objets. Prêt à détecter.");
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_isDisposed && mounted) {
      setState(() {
        _isObstacleAlertEnabled = prefs.getBool('obstacleAlert') ?? false;
        _isHighContrast = prefs.getBool('highContrast') ?? false;
        _isDarkMode = prefs.getBool('darkMode') ?? true;
        _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.0;
        _isTtsEnabled = prefs.getBool('ttsEnabled') ?? false;
      });
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('obstacleAlert', _isObstacleAlertEnabled);
    await prefs.setBool('highContrast', _isHighContrast);
    await prefs.setBool('darkMode', _isDarkMode);
    await prefs.setDouble('textScaleFactor', _textScaleFactor);
    await prefs.setBool('ttsEnabled', _isTtsEnabled);
  }

  Future<void> _initializeCamera() async {
    if (_isDisposed) return;
    try {
      final camera = widget.cameras.isNotEmpty
          ? widget.cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      )
          : throw Exception("Aucune caméra disponible");
      _cameraController = CameraController(
        camera,
        ResolutionPreset.ultraHigh,
        enableAudio: false,
      );
      await _cameraController.initialize();
      if (!mounted || _isDisposed) return;
      setState(() {
        isCameraReady = true;
      });
      _startImageStream();
    } catch (e) {
      if (mounted) {
        setState(() => result = "Erreur caméra: $e");
        _tts.speak("Erreur caméra.");
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    }
  }

  void _initializeMLKit() {
    _imageLabeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: _confidenceThreshold),
    );
  }

  Future<void> _initializeTts() async {
    try {
      await _tts.setLanguage("fr-FR");
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur TTS: $e")),
        );
      }
    }
  }

  void _startImageStream() {
    if (_isDisposed || !isCameraReady) return;
    _cameraController.startImageStream((CameraImage image) async {
      if (isDetecting || _isDisposed) return;
      isDetecting = true;
      try {
        await _processImage(image);
      } catch (e) {
        if (mounted) {
          setState(() => result = "Erreur traitement image: $e");
          _tts.speak("Erreur de détection.");
          Vibration.vibrate(pattern: [0, 200, 100, 200]);
        }
      } finally {
        isDetecting = false;
      }
    });
  }

  Future<void> _processImage(CameraImage cameraImage) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File imageFile = File(filePath);

      final XFile picture = await _cameraController.takePicture();
      await picture.saveTo(imageFile.path);

      final inputImage = InputImage.fromFile(imageFile);
      final List<ImageLabel> labels = await _imageLabeler.processImage(inputImage);

      String detectedObjects = labels.isNotEmpty
          ? labels
          .map((label) {
        final confidence = (label.confidence * 100).toStringAsFixed(2);
        final distance = _estimateDistance(label.confidence);
        return "${label.label} - $confidence% - $distance";
      })
          .join("\n")
          : "Aucun objet détecté";

      // Annonce vocale des objets détectés
      if (_isTtsEnabled && labels.isNotEmpty && DateTime.now().difference(_lastAlert) >= _alertInterval) {
        String ttsMessage = labels
            .where((label) => label.confidence >= _confidenceThreshold)
            .map((label) {
          final distance = _estimateDistance(label.confidence);
          return "${label.label} $distance";
        })
            .join(", ");

        if (ttsMessage.isNotEmpty) {
          _lastAlert = DateTime.now();
          await _speakText("Objets détectés: $ttsMessage");
        }
      }

      // Gestion des alertes d'obstacles
      if (_isObstacleAlertEnabled &&
          labels.isNotEmpty &&
          DateTime.now().difference(_lastAlert) >= _alertInterval) {
        String alertMessage = "";
        bool shouldVibrate = false;
        for (var label in labels) {
          if (label.confidence < _confidenceThreshold) continue;
          final distance = _estimateDistance(label.confidence);
          alertMessage += "${label.label} $distance. ";
          if (distance == "très proche" || distance == "proche") {
            shouldVibrate = true;
          }
        }
        if (alertMessage.isNotEmpty) {
          _lastAlert = DateTime.now();
          if (_isTtsEnabled) {
            await _speakText("Attention! $alertMessage");
          }
          if (shouldVibrate && await Vibration.hasVibrator() == true) {
            Vibration.vibrate(pattern: [0, 200, 100, 200]);
          }
        }
      }

      if (mounted) {
        setState(() {
          result = detectedObjects;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => result = "Erreur: $e");
        _tts.speak("Erreur de détection.");
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    }
  }

  String _estimateDistance(double confidence) {
    if (confidence > 0.8) {
      return "très proche";
    } else if (confidence > 0.6) {
      return "proche";
    } else {
      return "loin";
    }
  }

  Future<void> _speakText(String text) async {
    if (text.isEmpty || !_isTtsEnabled || _isDisposed) return;
    try {
      await _tts.stop();
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur TTS: $e")),
        );
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _cameraController.setFlashMode(
        _isTorchOn ? FlashMode.off : FlashMode.torch,
      );
      setState(() {
        _isTorchOn = !_isTorchOn;
      });
      Vibration.vibrate(duration: 50);
      _tts.speak(_isTorchOn ? "Lampe torche activée." : "Lampe torche désactivée.");
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lampe torche: $e")),
        );
      }
    }
  }

  void _toggleObstacleAlert() {
    setState(() {
      _isObstacleAlertEnabled = !_isObstacleAlertEnabled;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_isObstacleAlertEnabled ? "Alertes d'obstacles activées." : "Alertes d'obstacles désactivées.");
    _savePreferences();
    if (!_isObstacleAlertEnabled) {
      _tts.stop();
    }
  }

  void _toggleHighContrast() {
    setState(() {
      _isHighContrast = !_isHighContrast;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_isHighContrast ? "Mode contraste élevé activé." : "Mode contraste élevé désactivé.");
    _savePreferences();
  }

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_isDarkMode ? "Mode sombre activé." : "Mode clair activé.");
    _savePreferences();
  }

  void _toggleTts() {
    setState(() {
      _isTtsEnabled = !_isTtsEnabled;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak(_isTtsEnabled ? "Synthèse vocale activée." : "Synthèse vocale désactivée.");
    _savePreferences();
    if (!_isTtsEnabled) {
      _tts.stop();
    }
  }

  void _updateTextScale(double value) {
    setState(() {
      _textScaleFactor = value;
    });
    Vibration.vibrate(duration: 50);
    _tts.speak("Taille du texte: ${value.toStringAsFixed(1)}");
    _savePreferences();
  }

  Future<void> _logout() async {
    try {
      final authService = AuthService();
      await authService.signOut();
      if (mounted) {
        _tts.speak("Déconnexion réussie.");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginPage(cameras: widget.cameras)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur de déconnexion: $e")),
        );
        _tts.speak("Erreur de déconnexion.");
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !isCameraReady) return;
    if (state == AppLifecycleState.paused) {
      _cameraController.stopImageStream();
    } else if (state == AppLifecycleState.resumed && !_cameraController.value.isStreamingImages) {
      _startImageStream();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cameraController.stopImageStream();
    _cameraController.dispose();
    _imageLabeler.close();
    _tts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) return const SizedBox.shrink();
    return Scaffold(
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
            "Détection d'Objets",
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
          IconButton(
            icon: Icon(
              _isObstacleAlertEnabled ? Icons.warning : Icons.warning_outlined,
              color: _isHighContrast ? Colors.white : Colors.white,
              size: 26,
            ),
            onPressed: _toggleObstacleAlert,
            tooltip: 'Basculer les alertes d\'obstacles',
          ),
          IconButton(
            icon: Icon(
              Icons.logout,
              color: Colors.white,
              size: 26,
            ),
            onPressed: _logout,
            tooltip: 'Se déconnecter',
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
                    if (isCameraReady)
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
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.blue),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    isDetecting
                        ? CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(accentColor),
                    )
                        : _buildTextCard(
                      title: "Objets Détectés",
                      content: result,
                      icon: Icons.visibility,
                      color: accentColor,
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
                        _isTorchOn ? Icons.flash_on : Icons.flash_off,
                        color: _isHighContrast ? Colors.white : primaryColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Lampe torche",
                          style: TextStyle(
                            color: _isHighContrast ? Colors.white : textColor,
                            fontSize: 16 * _textScaleFactor,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleTorch,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _isTorchOn
                                ? (_isHighContrast ? Colors.white : accentColor)
                                : (_isHighContrast ? Colors.grey[800] : Colors.grey[600]),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: _isTorchOn
                              ? Pulse(
                            infinite: true,
                            child: Icon(
                              Icons.flash_on,
                              color: _isHighContrast ? Colors.black : Colors.white,
                              size: 28,
                            ),
                          )
                              : Icon(
                            Icons.flash_off,
                            color: _isHighContrast ? Colors.white : Colors.black,
                            size: 28,
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
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 80),
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