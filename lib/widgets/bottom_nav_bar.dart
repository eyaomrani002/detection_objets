import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade900,
                Colors.cyan.shade600,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: onTap,
            backgroundColor: Colors.transparent,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white.withOpacity(0.6),
            selectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
            showUnselectedLabels: true,
            elevation: 0,
            type: BottomNavigationBarType.fixed, // Important pour 4 éléments
            items: [
              _buildNavItem(
                icon: Icons.camera_alt,
                label: 'Detection',
                isSelected: currentIndex == 0,
              ),
              _buildNavItem(
                icon: Icons.text_fields,
                label: 'Text',
                isSelected: currentIndex == 1,
              ),
              _buildNavItem(
                icon: Icons.translate,
                label: 'Translation',
                isSelected: currentIndex == 2,
              ),
              _buildNavItem(
                icon: Icons.mic,
                label: 'Speech',
                isSelected: currentIndex == 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return BottomNavigationBarItem(
      icon: ElasticIn(
        duration: const Duration(milliseconds: 200),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
            ),
            if (isSelected)
              Positioned(
                bottom: -8,
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.cyan.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
      label: label,
    );
  }
}