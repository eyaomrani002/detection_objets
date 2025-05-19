import 'dart:async';
import 'dart:convert';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vibration/vibration.dart';
import 'package:camera/camera.dart';

class SpeechToTextScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const SpeechToTextScreen({super.key, required this.cameras});

  @override
  State<SpeechToTextScreen> createState() => _SpeechToTextScreenState();
}

class _SpeechToTextScreenState extends State<SpeechToTextScreen>
    with WidgetsBindingObserver {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _recognizedText = "Appuyez sur le bouton pour parler...";
  String _translatedText = "";
  bool _isHighContrast = false;
  double _textScaleFactor = 1.0;
  String _selectedLanguage = 'fr';
  final FlutterTts _tts = FlutterTts();
  bool _isDisposed = false;
  final _translationCache = <String, String>{};
  bool _isDarkMode = true;

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
    'ar': 'Arabe',
    'hi': 'Hindi',
  };

  // Palette de couleurs bleue
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSpeech();
    _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tts.speak("Écran de traduction vocale. Appuyez sur le bouton pour parler.");
    });
  }

  Future<void> _initializeSpeech() async {
    if (_isDisposed) return;
    if (!await _checkPermissions()) {
      setState(() => _recognizedText = "Permission microphone refusée");
      _tts.speak("Permission microphone refusée. Veuillez l'activer dans les paramètres.");
      return;
    }

    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' && _isListening) {
            _stopListening();
          }
        },
        onError: (error) {
          if (!_isDisposed && mounted) {
            setState(() => _recognizedText = "Erreur: ${error.errorMsg}");
            Vibration.vibrate(pattern: [0, 200, 100, 200]);
            _tts.speak("Erreur de reconnaissance vocale.");
          }
        },
      );

      if (!available && mounted) {
        setState(() => _recognizedText = "Reconnaissance vocale non disponible");
        _tts.speak("Reconnaissance vocale non disponible.");
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() => _recognizedText = "Erreur d'initialisation: $e");
        _tts.speak("Erreur d'initialisation.");
      }
    }
  }

  Future<bool> _checkPermissions() async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final result = await Permission.microphone.request();
      return result.isGranted;
    }
    return micStatus.isGranted;
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

  void _startListening() async {
    if (_isListening || _isDisposed) return;

    try {
      setState(() {
        _isListening = true;
        _recognizedText = "Écoute en cours...";
        _translatedText = "";
      });

      Vibration.vibrate(duration: 50);
      await _tts.speak("Écoute démarrée.");

      await _speech.listen(
        onResult: (result) {
          if (!_isDisposed && mounted) {
            setState(() {
              _recognizedText = result.recognizedWords.isEmpty
                  ? "Aucune parole détectée"
                  : result.recognizedWords;
            });
            if (result.finalResult && _recognizedText != "Aucune parole détectée") {
              Vibration.vibrate(duration: 100);
              _translateAndSpeak(_recognizedText);
            }
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        localeId: 'fr-FR', // Forcer la reconnaissance vocale en français
      );
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() => _recognizedText = "Erreur: $e");
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
        _tts.speak("Erreur de démarrage de l'écoute.");
      }
    }
  }

  void _stopListening() {
    if (!_isListening || _isDisposed) return;
    _speech.stop();
    setState(() => _isListening = false);
    Vibration.vibrate(duration: 50);
    _tts.speak("Écoute arrêtée.");
  }

  Future<void> _translateAndSpeak(String text) async {
    if (text.isEmpty || text == "Aucune parole détectée" || _isDisposed) return;

    try {
      final translation = await _translateWithMyMemory(text, _selectedLanguage);
      if (!_isDisposed && mounted) {
        setState(() {
          _translatedText = translation.isEmpty ? "Échec de la traduction" : translation;
        });

        if (translation.startsWith("Erreur") || translation == "Échec de la traduction") {
          Vibration.vibrate(pattern: [0, 200, 100, 200]);
          _tts.speak("Erreur de traduction.");
        } else {
          Vibration.vibrate(duration: 150);
          await _tts.setLanguage(_selectedLanguage == 'zh' ? 'zh-CN' : _selectedLanguage);
          await _tts.speak(translation);
        }
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() => _translatedText = "Erreur: $e");
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
        _tts.speak("Erreur de traduction.");
      }
    }
  }

  Future<String> _translateWithMyMemory(String text, String targetLang) async {
    final cacheKey = '$text-$targetLang';
    if (_translationCache.containsKey(cacheKey)) {
      return _translationCache[cacheKey]!;
    }

    try {
      // Assumer que la langue source est le français par défaut
      String detectedLang = 'fr';
      final apiDetectedLang = await _detectLanguage(text);
      if (apiDetectedLang.isNotEmpty) {
        detectedLang = apiDetectedLang;
      }

      // Vérifier si la langue source et cible sont identiques
      if (detectedLang == targetLang || (detectedLang == 'zh' && targetLang == 'zh')) {
        return text; // Retourner le texte original si les langues sont identiques
      }

      final langPair = '${detectedLang == 'zh' ? 'zh-CN' : detectedLang}|${targetLang == 'zh' ? 'zh-CN' : targetLang}';
      print('langPair: $langPair'); // Log pour débogage
      final encodedText = Uri.encodeComponent(text);
      final url = 'https://api.mymemory.translated.net/get?q=$encodedText&langpair=$langPair';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['responseData'] != null && data['responseData']['translatedText'] != null) {
          final translation = data['responseData']['translatedText'].toString();
          _translationCache[cacheKey] = translation;
          return translation;
        } else {
          return "Erreur: Aucun résultat de traduction";
        }
      } else {
        return "Erreur API: ${response.statusCode}";
      }
    } catch (e) {
      return "Erreur: ${e.toString()}";
    }
  }

  Future<String> _detectLanguage(String text) async {
    try {
      final encodedText = Uri.encodeComponent(text);
      final url = 'https://api.mymemory.translated.net/detect?q=$encodedText';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['responseData'] != null && data['responseData']['language'] != null) {
          final detectedLang = data['responseData']['language'].toString();
          print('Detected language: $detectedLang'); // Log pour débogage
          return detectedLang;
        }
      }
    } catch (e) {
      print('Erreur détection langue: $e');
    }

    // Fallback pour les langues courantes
    if (RegExp(r'[а-яА-Я]').hasMatch(text)) return 'ru';
    if (RegExp(r'[一-龯]').hasMatch(text)) return 'zh';
    if (RegExp(r'[あ-んア-ン]').hasMatch(text)) return 'ja';
    if (RegExp(r'[가-힣]').hasMatch(text)) return 'ko';
    if (RegExp(r'[ء-ي]').hasMatch(text)) return 'ar';

    // Par défaut, retourner français au lieu d'anglais
    return 'fr';
  }

  void _toggleHighContrast() {
    if (_isDisposed) return;
    setState(() {
      _isHighContrast = !_isHighContrast;
    });
    _savePreferences();
    _tts.speak(_isHighContrast ? "Mode contraste élevé activé" : "Mode contraste élevé désactivé");
  }

  void _toggleDarkMode() {
    if (_isDisposed) return;
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    _savePreferences();
    _tts.speak(_isDarkMode ? "Mode sombre activé" : "Mode clair activé");
  }

  void _updateTextScale(double value) {
    if (_isDisposed) return;
    setState(() {
      _textScaleFactor = value;
    });
    _savePreferences();
    _tts.speak("Taille du texte: ${value.toStringAsFixed(1)}");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    if (state == AppLifecycleState.paused) {
      _stopListening();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _speech.stop();
    _tts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            "Traduction Vocale",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22 * _textScaleFactor,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
            semanticsLabel: "Écran de Traduction Vocale",
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
          const SizedBox(width: 10),
        ],
      ),
      backgroundColor: _isHighContrast
          ? Colors.black
          : backgroundColor,
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
                    _buildTextCard(
                      title: "Votre Message",
                      content: _recognizedText,
                      icon: Icons.mic,
                      color: accentColor,
                      height: 200, // Grande zone de texte
                    ),
                    const SizedBox(height: 20),
                    _buildTextCard(
                      title: "Traduction",
                      content: _translatedText.isEmpty
                          ? "La traduction apparaîtra ici"
                          : _translatedText,
                      icon: Icons.translate,
                      color: lightColor,
                      height: 200, // Grande zone de texte
                    ),
                    const SizedBox(height: 30),
                    FadeInUp(
                      delay: const Duration(milliseconds: 300),
                      child: GestureDetector(
                        onTap: _isListening ? _stopListening : _startListening,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: _isHighContrast
                                ? Colors.white
                                : _isListening ? Colors.red : primaryColor,
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
                              if (_isListening)
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
                                _isListening ? Icons.stop : Icons.mic,
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
              color: _isHighContrast
                  ? Colors.black
                  : cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(
                color: _isHighContrast
                    ? Colors.white
                    : Colors.grey.withOpacity(0.3),
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
              top: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.language,
                        color: _isHighContrast ? Colors.white : primaryColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Langue Cible",
                          style: TextStyle(
                            color: _isHighContrast ? Colors.white : textColor,
                            fontSize: 16 * _textScaleFactor,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.5,
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedLanguage,
                          dropdownColor: _isHighContrast
                              ? Colors.grey[900]
                              : _isDarkMode ? darkColor : lightColor,
                          style: TextStyle(
                            color: _isHighContrast ? Colors.white : textColor,
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
                            if (value != null && !_isDisposed) {
                              setState(() => _selectedLanguage = value);
                              _tts.speak(
                                  "Langue définie sur ${_languageMap[value]}");
                              if (_recognizedText.isNotEmpty &&
                                  _recognizedText != "Aucune parole détectée") {
                                _translateAndSpeak(_recognizedText);
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
                        color: _isHighContrast ? Colors.white : primaryColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Taille du Texte",
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
                          activeColor: _isHighContrast
                              ? Colors.white
                              : accentColor,
                          inactiveColor: _isHighContrast
                              ? Colors.grey
                              : Colors.grey,
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
    required double height,
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
              height: height,
              width: double.infinity,
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