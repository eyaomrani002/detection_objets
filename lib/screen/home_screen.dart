import 'package:camera/camera.dart';
import 'package:detection_objects/screen/object_detection_screen.dart';
import 'package:detection_objects/screen/text_detection_screen.dart';
import 'package:detection_objects/screen/text_translation_screen.dart';
import 'package:detection_objects/screen/speech_to_text_screen.dart'; // Import ajouté
import 'package:detection_objects/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _onNavTap(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const NeverScrollableScrollPhysics(), // Désactive le swipe manuel
        children: [
          ObjectDetectionScreen(cameras: widget.cameras),
          TextDetectionScreen(cameras: widget.cameras),
          TextTranslationScreen(cameras: widget.cameras),
          SpeechToTextScreen(cameras: widget.cameras), // Nouvel écran ajouté
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }
}