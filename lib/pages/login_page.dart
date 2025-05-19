import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../auth/auth_service.dart';
import '../screen/home_screen.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LoginPage({super.key, required this.cameras});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _useFaceAuth = false;
  bool _hasFacialData = false;
  bool _faceDetected = false;
  bool _cameraInitializationStarted = false;

  @override
  void initState() {
    super.initState();
    _checkFacialData();
  }

  Future<void> _checkFacialData() async {
    final userId = authService.currentUserId;
    if (userId != null) {
      final hasData = await authService.hasFacialData(userId);
      if (mounted) {
        setState(() {
          _hasFacialData = hasData;
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_cameraInitializationStarted) return;
    setState(() {
      _cameraInitializationStarted = true;
      _isLoading = true;
    });

    try {
      if (await Permission.camera.request().isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Permission caméra requise")),
          );
        }
        return;
      }

      final frontCamera = widget.cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        if (_useFaceAuth) {
          _startFaceDetectionFeedback();
        }
      }
    } catch (e) {
      print("Erreur initialisation caméra : $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Échec initialisation caméra: $e")),
        );
        setState(() {
          _hasFacialData = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startFaceDetectionFeedback() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    bool isProcessing = false;
    await _cameraController!.startImageStream((image) async {
      if (isProcessing || !mounted) return;
      isProcessing = true;
      try {
        final inputImage = InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
        final faces = await authService.detectFaces(inputImage);
        if (mounted) {
          setState(() {
            _faceDetected = faces.isNotEmpty;
          });
        }
      } finally {
        isProcessing = false;
      }
      await Future.delayed(const Duration(milliseconds: 1000));
    });
  }

  void login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegExp.hasMatch(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Format d'email invalide")),
        );
      }
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veuillez entrer email et mot de passe")),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await authService.signInWithEmailPassword(email, password);
      print("Connexion réussie : ${response.session?.user.id}");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen(cameras: widget.cameras)),
        );
      }
    } catch (e) {
      print("Erreur de connexion : $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur de connexion: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void loginWithFace() async {
    if (!_isCameraInitialized || _cameraController == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Caméra non initialisée")),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final isAuthenticated = await authService.authenticateWithFace(inputImage);
      if (isAuthenticated) {
        if (authService.hasActiveSession) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Authentification faciale réussie")),
            );
            Navigator.of(context, rootNavigator: true).pushReplacement(
              MaterialPageRoute(builder: (context) => HomeScreen(cameras: widget.cameras)),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text("Veuillez d'abord vous connecter avec email/mot de passe")),
            );
            setState(() {
              _useFaceAuth = false;
            });
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Échec de l'authentification faciale")),
          );
        }
      }
    } catch (e) {
      print("Erreur authentification faciale : $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleFaceAuth() {
    setState(() {
      _useFaceAuth = !_useFaceAuth;
      if (_useFaceAuth && !_isCameraInitialized) {
        _initializeCamera();
      } else if (!_useFaceAuth && _cameraController != null) {
        _cameraController!.stopImageStream();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient modernisé
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2196F3),
                  Color(0xFF1976D2),
                  Color(0xFF0D47A1),
                ],
                stops: [0.1, 0.5, 0.9],
              ),
            ),
          ),

          // Content
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 80),

                  // Logo and title - Design modernisé
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          _useFaceAuth ? Icons.face : Icons.lock,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _useFaceAuth ? "Face Authentication" : "Welcome Back",
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _useFaceAuth ? "Look at the camera" : "Sign in to continue",
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Login form or Face Auth
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 30,
                          spreadRadius: 2,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (!_useFaceAuth) ...[
                          // Email field
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: "Email",
                              labelStyle: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.email_outlined,
                                color: Colors.grey[600],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[100],
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 20),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Password field
                          TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: "Password",
                              labelStyle: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: Colors.grey[600],
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureText ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureText = !_obscureText;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[100],
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 20),
                            ),
                            obscureText: _obscureText,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Forgot password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () async {
                                final email = _emailController.text.trim();
                                if (email.isNotEmpty) {
                                  try {
                                    await authService.resetPasswordForEmail(email);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text("Email de réinitialisation envoyé")),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Erreur: $e")),
                                      );
                                    }
                                  }
                                }
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                "Forgot Password?",
                                style: TextStyle(
                                  color: Color(0xFF1976D2),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ] else if (_isCameraInitialized) ...[
                          // Face Auth Preview
                          Container(
                            height: 200,
                            width: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _faceDetected ? Colors.green : Colors.grey[300]!,
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CameraPreview(_cameraController!),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _faceDetected ? "Face detected" : "Position your face in the frame",
                            style: TextStyle(
                              color: _faceDetected ? Colors.green : Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text("Initializing camera..."),
                        ],

                        const SizedBox(height: 24),

                        // Login/Face Auth button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 5,
                              shadowColor: const Color(0xFF1976D2).withOpacity(0.4),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _isLoading ? null :
                            (_useFaceAuth ? loginWithFace : login),
                            child: _isLoading
                                ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                                : Text(
                              _useFaceAuth ? "AUTHENTICATE" : "LOGIN",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Toggle between auth methods
                        if (_hasFacialData)
                          TextButton(
                            onPressed: _toggleFaceAuth,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _useFaceAuth
                                  ? "Use Email/Password"
                                  : "Use Face Authentication",
                              style: const TextStyle(
                                color: Color(0xFF1976D2),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RegisterPage(cameras: widget.cameras),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                          ),
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
}