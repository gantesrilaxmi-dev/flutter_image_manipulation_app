import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';

void main() {
  runApp(const FaceAuthenticationApp());
}

class FaceAuthenticationApp extends StatelessWidget {
  const FaceAuthenticationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Facial Authentication',
      theme: ThemeData.dark(),
      home: FaceEnrollScreen(),
    );
  }
}

enum ViewType { frontal, rightProfile, leftProfile, up, down }

class FaceEnrollScreen extends StatefulWidget {
  @override
  _FaceEnrollScreenState createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isProcessing = false;
  String _warningMessage = "";
  bool _showAccessoryWarning = false;

  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Map<ViewType, bool> viewStatus = {
    ViewType.frontal: false,
    ViewType.rightProfile: false,
    ViewType.leftProfile: false,
    ViewType.up: false,
    ViewType.down: false,
  };

  Map<ViewType, int> stableCounter = {
    ViewType.frontal: 0,
    ViewType.rightProfile: 0,
    ViewType.leftProfile: 0,
    ViewType.up: 0,
    ViewType.down: 0,
  };

  final int requiredStableFrames = 5;
  ViewType? _currentTargetView;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _currentTargetView = ViewType.frontal;
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();

    final camera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21, // ✅ Use NV21 for Android
    );

    await _cameraController!.initialize();
    await _cameraController!.startImageStream(_processCameraImage);
    setState(() {});
  }

  InputImageRotation _rotationIntToImageRotation(int rotation) {
    switch (rotation) {
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

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final camera = _cameraController!.description;
      final sensorOrientation = camera.sensorOrientation;
      final imageRotation = _rotationIntToImageRotation(sensorOrientation);

      InputImageFormat? inputImageFormat;

      // Handle different image formats
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        inputImageFormat = InputImageFormat.bgra8888;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        if (image.format.group == ImageFormatGroup.nv21) {
          inputImageFormat = InputImageFormat.nv21;
        } else if (image.format.group == ImageFormatGroup.yuv420) {
          inputImageFormat = InputImageFormat.yuv420;
        }
      }

      if (inputImageFormat == null) {
        debugPrint('❌ Unsupported image format: ${image.format.group}');
        _isProcessing = false;
        return;
      }

      final plane = image.planes.first;
      final inputImageData = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: plane.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: inputImageData,
      );

      // Detect faces
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _warningMessage = "No face detected. Please position your face in the frame.";
          _showAccessoryWarning = false;
        });
        _resetStableCounters();
        _isProcessing = false;
        return;
      }

      final face = faces.first;

      // Check for accessories
      final accessoryWarnings = _detectAccessories(face);

      if (accessoryWarnings.isNotEmpty) {
        setState(() {
          _warningMessage = accessoryWarnings.join('\n');
          _showAccessoryWarning = true;
        });
        _resetStableCounters();
        _isProcessing = false;
        return;
      }

      setState(() {
        _warningMessage = "";
        _showAccessoryWarning = false;
      });

      final headEulerY = face.headEulerAngleY ?? 0.0; // yaw
      final headEulerX = face.headEulerAngleX ?? 0.0; // pitch

      debugPrint('Yaw: $headEulerY | Pitch: $headEulerX');

      // Check current target view
      if (_currentTargetView != null) {
        _checkView(
          _currentTargetView!,
          headEulerY,
          headEulerX,
          false,
              () {
            _moveToNextView();
          },
        );
      }
    } catch (e) {
      debugPrint("❌ Error processing image: $e");
    } finally {
      _isProcessing = false;
    }
  }

  List<String> _detectAccessories(Face face) {
    List<String> warnings = [];

    // Check for glasses/spectacles
    // Low eye open probability might indicate glasses obstruction
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;

    // If both eyes have consistently low visibility, might be glasses
    // Note: This is a heuristic and may need tuning
    if (leftEyeOpen < 0.3 && rightEyeOpen < 0.3) {
      warnings.add("⚠️ Please remove spectacles/glasses");
    }

    // Check if face is partially covered (mask detection)
    // If mouth landmarks are not detected or face contours are incomplete
    final landmarks = face.landmarks;
    final mouthBottom = landmarks[FaceLandmarkType.mouthBottom];
    final mouthLeft = landmarks[FaceLandmarkType.mouthLeft];
    final mouthRight = landmarks[FaceLandmarkType.mouthRight];

    if (mouthBottom == null || mouthLeft == null || mouthRight == null) {
      warnings.add("⚠️ Please remove any face mask");
    }

    // Check for headwear by analyzing forehead visibility
    // If top contours are missing or forehead area is obscured
    final contours = face.contours;
    final faceContour = contours[FaceContourType.face];

    if (faceContour == null || faceContour.points.length < 30) {
      warnings.add("⚠️ Please remove cap/hat");
    }

    // Note: Earbuds detection is difficult with front camera
    // You might need to add manual instructions or use additional ML models
    if (warnings.isEmpty) {
      // Add a general check message
      final leftEar = landmarks[FaceLandmarkType.leftEar];
      final rightEar = landmarks[FaceLandmarkType.rightEar];

      if (leftEar == null || rightEar == null) {
        warnings.add("⚠️ Please ensure ears are visible (remove earbuds/headphones)");
      }
    }

    return warnings;
  }

  void _resetStableCounters() {
    stableCounter.updateAll((key, value) => 0);
  }

  void _checkView(
      ViewType view,
      double yaw,
      double pitch,
      bool accessoryDetected,
      VoidCallback onSuccess,
      ) {
    if (viewStatus[view] == true) return;

    if (accessoryDetected) {
      stableCounter[view] = 0;
      setState(() {});
      return;
    }

    bool inRange = false;
    switch (view) {
      case ViewType.frontal:
        inRange = (yaw.abs() <= 15 && pitch.abs() <= 15);
        break;
      case ViewType.rightProfile:
        inRange = (yaw > 30 && yaw <= 70 && pitch.abs() <= 20);
        break;
      case ViewType.leftProfile:
        inRange = (yaw < -30 && yaw >= -70 && pitch.abs() <= 20);
        break;
      case ViewType.up:
        inRange = (pitch < -20 && pitch >= -45 && yaw.abs() <= 20);
        break;
      case ViewType.down:
        inRange = (pitch > 20 && pitch <= 45 && yaw.abs() <= 20);
        break;
    }

    if (inRange) {
      stableCounter[view] = (stableCounter[view] ?? 0) + 1;
      if (stableCounter[view]! >= requiredStableFrames) {
        viewStatus[view] = true;
        debugPrint('✅ View ${view.toString()} detected successfully.');
        onSuccess();
      }
    } else {
      stableCounter[view] = 0;
    }

    setState(() {});
  }

  void _moveToNextView() {
    final views = ViewType.values;
    final currentIndex = views.indexOf(_currentTargetView!);

    if (currentIndex < views.length - 1) {
      setState(() {
        _currentTargetView = views[currentIndex + 1];
      });
    } else {
      // All views completed
      setState(() {
        _currentTargetView = null;
      });
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('✅ Enrollment Complete'),
        content: const Text('All facial views have been captured successfully!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Reset for new enrollment
              setState(() {
                viewStatus.updateAll((key, value) => false);
                _currentTargetView = ViewType.frontal;
              });
            },
            child: const Text('Start New Enrollment'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _getViewInstruction(ViewType view) {
    switch (view) {
      case ViewType.frontal:
        return "Look straight at the camera";
      case ViewType.rightProfile:
        return "Turn your head to the RIGHT";
      case ViewType.leftProfile:
        return "Turn your head to the LEFT";
      case ViewType.up:
        return "Tilt your head UP";
      case ViewType.down:
        return "Tilt your head DOWN";
    }
  }

  @override
  void dispose() {
    faceDetector.close();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final allCompleted = viewStatus.values.every((status) => status);
    final incompleteViews = viewStatus.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key.toString().split('.').last)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Center(
            child: AspectRatio(
              aspectRatio: _cameraController!.value.aspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),

          // Top Instructions
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black54,
              child: Column(
                children: [
                  Text(
                    _currentTargetView != null
                        ? _getViewInstruction(_currentTargetView!)
                        : "All views captured!",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_showAccessoryWarning) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _warningMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ] else if (_warningMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _warningMessage,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // View Status Checklist
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Capture Progress',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...ViewType.values.map((v) {
                    final isCompleted = viewStatus[v]!;
                    final isCurrent = v == _currentTargetView;
                    final progress = stableCounter[v]! / requiredStableFrames;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isCompleted ? Colors.green : (isCurrent ? Colors.blue : Colors.grey),
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.toString().split('.').last.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    color: isCompleted ? Colors.green : (isCurrent ? Colors.blue : Colors.white),
                                  ),
                                ),
                                if (isCurrent && !isCompleted)
                                  LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.grey[800],
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  if (!allCompleted && incompleteViews.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Please complete: ${incompleteViews.join(", ")}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Initial Warning Overlay
          Positioned(
            top: 120,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '📋 Before starting:\n'
                    '• Remove spectacles/glasses\n'
                    '• Remove face masks\n'
                    '• Remove caps/hats\n'
                    '• Remove earbuds/headphones\n'
                    '• Ensure good lighting',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  height: 1.5,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ],
      ),
    );
  }
}