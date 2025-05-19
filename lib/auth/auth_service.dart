import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:encrypt/encrypt.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  final _encryptionKey = Key.fromUtf8('32-character-long-key-here!!!'); // À sécuriser

  String? get currentUserId => _supabase.auth.currentUser?.id;

  bool get hasActiveSession => _supabase.auth.currentSession != null;

  Future<AuthResponse> signInWithEmailPassword(
      String email, String password) async {
    try {
      return await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      String message = e is AuthException ? e.message : "Une erreur inattendue s'est produite";
      throw Exception("Échec de la connexion: $message");
    }
  }

  Future<AuthResponse> signUpWithEmailPassword(
      String email, String password) async {
    try {
      return await _supabase.auth.signUp(
        email: email,
        password: password,
      );
    } catch (e) {
      String message = e is AuthException ? e.message : "Une erreur inattendue s'est produite";
      throw Exception("Échec de l'inscription: $message");
    }
  }

  Future<void> signOut() async {
    try {
      final userId = currentUserId;
      if (userId != null) {
        final directory = await getApplicationDocumentsDirectory();
        final localImagePath = '${directory.path}/images/$userId/facial_image.jpg';
        final localImageFile = File(localImagePath);
        if (await localImageFile.exists()) {
          await localImageFile.delete();
        }
        await _supabase.storage.from('images').remove(['$userId/facial_image.jpg']);
        await _supabase.from('facial_data').delete().eq('user_id', userId);
      }
      await _supabase.auth.signOut();
    } catch (e) {
      String message = e is AuthException ? e.message : "Une erreur inattendue s'est produite";
      throw Exception("Échec de la déconnexion: $message");
    }
  }

  Future<void> resetPasswordForEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw Exception("Échec de la réinitialisation du mot de passe: $e");
    }
  }

  String? getCurrentUserEmail() {
    final session = _supabase.auth.currentSession;
    final user = session?.user;
    return user?.email;
  }

  Future<File> _compressImage(File file) async {
    final image = img.decodeImage(await file.readAsBytes());
    final compressed = img.encodeJpg(image!, quality: 85);
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/compressed.jpg');
    await tempFile.writeAsBytes(compressed);
    return tempFile;
  }

  Future<void> storeFacialData(String userId, InputImage inputImage) async {
    try {
      if (await Permission.storage.request().isDenied) {
        throw Exception("Permission de stockage refusée");
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) throw Exception("Aucun visage détecté dans l'image");
      if (faces.length > 1) throw Exception("Plusieurs visages détectés dans l'image");

      final face = faces.first;
      final boundingBox = face.boundingBox;
      final width = boundingBox.width;
      final height = boundingBox.height;

      final facialData = {
        'left_eye': {
          'x': ((face.landmarks[FaceLandmarkType.leftEye]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.leftEye]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'right_eye': {
          'x': ((face.landmarks[FaceLandmarkType.rightEye]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.rightEye]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'nose_base': {
          'x': ((face.landmarks[FaceLandmarkType.noseBase]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.noseBase]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'mouth_left': {
          'x': ((face.landmarks[FaceLandmarkType.leftMouth]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.leftMouth]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'mouth_right': {
          'x': ((face.landmarks[FaceLandmarkType.rightMouth]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.rightMouth]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
      };

      final iv = IV.fromLength(16);
      final encrypter = Encrypter(AES(_encryptionKey));
      final encryptedData = encrypter.encrypt(jsonEncode(facialData), iv: iv).base64;

      final imageFile = await _compressImage(File(inputImage.filePath!));
      final directory = await getApplicationDocumentsDirectory();
      final localImagePath = '${directory.path}/images/$userId/facial_image.jpg';
      final localImageFile = File(localImagePath);
      await localImageFile.parent.create(recursive: true);
      await imageFile.copy(localImagePath);

      final supabaseImagePath = '$userId/facial_image.jpg';
      await _supabase.storage
          .from('images')
          .upload(
        supabaseImagePath,
        imageFile,
        fileOptions: FileOptions(metadata: {'user_id': userId}),
      );

      await _supabase.from('facial_data').insert({
        'user_id': userId,
        'data': encryptedData,
        'iv': iv.base64,
        'image_path': supabaseImagePath,
        'local_image_path': localImagePath,
      });
    } catch (e) {
      throw Exception("Échec du stockage des données faciales: $e");
    }
  }

  Future<bool> authenticateWithFace(InputImage inputImage) async {
    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) throw Exception("Aucun visage détecté");
      if (faces.length > 1) throw Exception("Plusieurs visages détectés");

      final face = faces.first;
      final boundingBox = face.boundingBox;
      final width = boundingBox.width;
      final height = boundingBox.height;

      final currentFacialData = {
        'left_eye': {
          'x': ((face.landmarks[FaceLandmarkType.leftEye]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.leftEye]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'right_eye': {
          'x': ((face.landmarks[FaceLandmarkType.rightEye]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.rightEye]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'nose_base': {
          'x': ((face.landmarks[FaceLandmarkType.noseBase]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.noseBase]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'mouth_left': {
          'x': ((face.landmarks[FaceLandmarkType.leftMouth]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.leftMouth]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
        'mouth_right': {
          'x': ((face.landmarks[FaceLandmarkType.rightMouth]?.position.x ?? 0.0) - boundingBox.left) / width,
          'y': ((face.landmarks[FaceLandmarkType.rightMouth]?.position.y ?? 0.0) - boundingBox.top) / height,
        },
      };

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception("Aucun utilisateur connecté");

      final response = await _supabase
          .from('facial_data')
          .select('data, iv')
          .eq('user_id', userId)
          .single();

      if (response.isEmpty) throw Exception("Aucune donnée faciale trouvée");

      final encrypter = Encrypter(AES(_encryptionKey));
      final iv = IV.fromBase64(response['iv'] as String);
      final decryptedData = encrypter.decrypt64(response['data'] as String, iv: iv);
      final storedFacialData = jsonDecode(decryptedData);

      double totalDistance = 0.0;
      for (var key in currentFacialData.keys) {
        final currentPoint = currentFacialData[key] as Map<String, dynamic>;
        final storedPoint = storedFacialData[key] as Map<String, dynamic>;
        final dx = (currentPoint['x'] as double) - (storedPoint['x'] as double);
        final dy = (currentPoint['y'] as double) - (storedPoint['y'] as double);
        totalDistance += dx * dx + dy * dy;
      }
      totalDistance = sqrt(totalDistance);

      const threshold = 0.1;
      return totalDistance < threshold;
    } catch (e) {
      throw Exception("Échec de l'authentification faciale: $e");
    }
  }

  Future<List<Face>> detectFaces(InputImage inputImage) async {
    try {
      return await _faceDetector.processImage(inputImage);
    } catch (e) {
      throw Exception("Échec de la détection de visage: $e");
    }
  }

  Future<String?> getFacialImageUrl(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('image_url_$userId');
      final cachedExpiry = prefs.getInt('image_url_expiry_$userId') ?? 0;

      if (cachedUrl != null && cachedExpiry > DateTime.now().millisecondsSinceEpoch) {
        return cachedUrl;
      }

      final response = await _supabase
          .from('facial_data')
          .select('image_path')
          .eq('user_id', userId)
          .single();

      if (response.isEmpty) return null;
      final imagePath = response['image_path'] as String;
      final signedUrl = await _supabase.storage
          .from('images')
          .createSignedUrl(imagePath, 3600);

      await prefs.setString('image_url_$userId', signedUrl);
      await prefs.setInt(
          'image_url_expiry_$userId',
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);

      return signedUrl;
    } catch (e) {
      throw Exception("Échec de la récupération de l'URL de l'image: $e");
    }
  }

  Future<String?> getLocalImagePath(String userId) async {
    try {
      final response = await _supabase
          .from('facial_data')
          .select('local_image_path')
          .eq('user_id', userId)
          .single();
      if (response.isEmpty) return null;
      return response['local_image_path'] as String?;
    } catch (e) {
      throw Exception("Échec de la récupération du chemin de l'image locale: $e");
    }
  }

  Future<bool> hasFacialData(String userId) async {
    try {
      final response = await _supabase
          .from('facial_data')
          .select('user_id')
          .eq('user_id', userId);
      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> disposeResources() async {
    await _faceDetector.close();
  }

  void dispose() {
    disposeResources();
  }
}