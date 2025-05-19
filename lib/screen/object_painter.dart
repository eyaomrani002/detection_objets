import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final bool highContrast;

  ObjectPainter(this.objects, this.imageSize, this.highContrast);

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    final Paint boxPaint = Paint()
      ..color = highContrast ? Colors.white : Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final TextStyle textStyle = TextStyle(
      color: highContrast ? Colors.white : Colors.yellowAccent,
      fontSize: 14.0,
      fontWeight: FontWeight.bold,
      backgroundColor: highContrast ? Colors.black : Colors.black45,
    );

    for (final DetectedObject obj in objects) {
      final Rect scaledBox = Rect.fromLTRB(
        obj.boundingBox.left * scaleX,
        obj.boundingBox.top * scaleY,
        obj.boundingBox.right * scaleX,
        obj.boundingBox.bottom * scaleY,
      );

      canvas.drawRect(scaledBox, boxPaint);

      if (obj.labels.isNotEmpty) {
        final label = obj.labels.first;
        final textSpan = TextSpan(
          text: '${label.text} (${(label.confidence * 100).toStringAsFixed(1)}%)',
          style: textStyle,
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width);

        textPainter.paint(
          canvas,
          Offset(scaledBox.left + 4, scaledBox.top + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}