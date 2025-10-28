import 'dart:typed_data';
import 'dart:math';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:http_parser/http_parser.dart';



List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

// Helper function to decode image dimensions
Future<ui.Image> decodeImageFromList(Uint8List list) async {
  final codec = await ui.instantiateImageCodec(list);
  final frame = await codec.getNextFrame();
  return frame.image;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Image Editor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: HomePage(),
    );
  }
}

class ImageFilterService {
  final String cloudUploadUrl = "https://new-camme-backend.onrender.com/api/v1/upload-file";
  final String createFilterUrl = "https://new-camme-backend.onrender.com/api/v1/image/process";

  Future<Uint8List?> previewFilterOnImage(File image, Map<String, dynamic> adjustments) async {
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("http://192.168.1.2:5000/edit"),
      );

      // Add image file
      request.files.add(await http.MultipartFile.fromPath("image", image.path));

      // Add adjustment fields
      adjustments.forEach((key, value) {
        request.fields[key] = value.toString();
      });

      // ✅ Print request details before sending
      print("----- HTTP REQUEST DETAILS -----");
      print("URL: ${request.url}");
      print("Method: ${request.method}");
      print("Headers: ${request.headers}");
      print("Fields:");
      request.fields.forEach((k, v) => print("  $k: $v"));
      print("Files:");
      for (var file in request.files) {
        print("  Field: ${file.field}");
        print("  Filename: ${file.filename}");
        print("  Length: ${file.length}");
        print("  ContentType: ${file.contentType}");
      }
      print("--------------------------------");

      // Send the request
      final streamedResponse = await request.send();
      final responseBytes = await streamedResponse.stream.toBytes();

      if (streamedResponse.statusCode == 200) {
        print("✅ Preview updated successfully");
        return responseBytes;
      } else {
        print("❌ Preview failed: ${streamedResponse.statusCode}");
        return null;
      }
    } catch (e) {
      print("❌ Preview error: $e");
      return null;
    }
  }


  Future<String?> uploadImage(Uint8List imageBytes) async {
    try {
      var request = http.MultipartRequest("POST", Uri.parse(cloudUploadUrl));
      request.files.add(
        http.MultipartFile.fromBytes("file", imageBytes, filename: 'image.jpg'),
      );

      var streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      print("📤 Upload response: $responseBody");

      if (streamedResponse.statusCode == 200) {
        final data = jsonDecode(responseBody);
        print("🧩 Parsed keys: ${data.keys.toList()}");

        // Extract nested URL properly
        final url = data['data']?['fileUrl'];

        if (url == null || url.isEmpty) {
          print("⚠️ No valid file URL found in response!");
          return null;
        }

        print("✅ Image uploaded: $url");
        return url;
      } else {
        print("❌ Upload failed: ${streamedResponse.statusCode} - $responseBody");
        return null;
      }
    } catch (e) {
      print("❌ Upload error: $e");
      return null;
    }
  }


  Future<void> createFilterFromUrl(String imageUrl, String filterName, Map<String, dynamic> params) async {
    try {
      final payload = {
        "image_url": imageUrl,
        "filter_data": {
          "filter_name": filterName,
          "params": params,
        }
      };
      print("📦 payload: $payload");


      final response = await http.post(
        Uri.parse(createFilterUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        print("✅ Filter stored successfully!");
        print("📦 Response: $decoded");
      } else {
        print("❌ Failed to store filter: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("❌ Error in createFilterFromUrl: $e");
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _adjectives = [
    'Ethereal', 'Lush', 'Mystic', 'Bold', 'Glimmering', 'Radiant', 'Vivid',
    'Dreamy', 'Sleek', 'Eclipsed', 'Luminous', 'Serene', 'Pale', 'Tropical',
    'Gleaming', 'Fiery', 'Frosted', 'Misty', 'Turbid', 'Gloomy'
  ];

  final List<String> _nouns = [
    'Blossom', 'Ember', 'Wave', 'Veil', 'Horizon', 'Spark', 'Glint', 'Shade',
    'Whisper', 'Chime', 'Aura', 'Flare', 'Zenith', 'Radiance', 'Reverie',
    'Pulse', 'Haze', 'Vibe', 'Flurry'
  ];

  final ImageFilterService _imageFilterService = ImageFilterService();

  File? _image;
  Uint8List? _processedImage;
  Timer? debounce;
  Uint8List? processedImageBytes;
  Uint8List? _beforeEnhanceImage;
  Uint8List? _afterEnhanceImage;
  final picker = ImagePicker();
  Timer? _debounce;
  bool _isProcessing = false;
  int _selectedTab = 0;
  String? _currentFilterName;
  String? _currentBlurName;
  Map<String, dynamic>? currentFilterParams;
  String? currentFilterId;
  bool isLoading = false;
  final GlobalKey _imageKey = GlobalKey();
  bool useBase64 = true;
  Size? _imageSize;
  String? _uploadedImageUrl;

  final Map<String, dynamic> adjustments = {
    "brightness": 0.0,
    "contrast": 0.0,
    "saturation": 0.0,
    "exposure": 0.0,
    "highlights": 0.0,
    "shadows": 0.0,
    "vibrance": 0.0,
    "temperature": 0.0,
    "hue": 0.0,
    "fading": 0.0,
    "enhance": 0.0,
    "smoothness": 0.0,
    "ambiance": 0.0,
    "noise": 0.0,
    "color_noise": 0.0,
    "inner_spotlight": 0.0,
    "outer_spotlight": 0.0,
    "tint": 0.0,
    "texture": 0.0,
    "clarity": 0.0,
    "dehaze": 0.0,
    "grain_amount": 0.0,
    "grain_size": 1.0,
    "grain_roughness": 1.0,
    "sharpen_amount": 0.0,
    "sharpen_radius": 1.0,
    "sharpen_detail": 1.0,
    "sharpen_masking": 0.0,
    "vignette_amount": 0.0,
    "vignette_midpoint": 50.0,
    "vignette_feather": 50.0,
    "vignette_roundness": 0.0,
    "vignette_highlights": 0.0,
  };

  String _blurType = 'linear';
  double _blurStrength = 50; // Changed from 51 to 50 for cleaner values
  double _stripPosition = 0.5;
  double _stripWidth = 0.3;
  double _radiusRatio = 0.3;
  double _widthRatio = 0.45;
  double _heightRatio = 0.25;
  double _feather = 50; // Changed from 51 to 50
  String _focusRegion = 'center';
  Offset? _gestureStart;
  Offset? _gestureEnd;
  Offset? _handCenter;
  double _handRadius = 50;


  final String apiUrl = "http://192.168.1.2:5000/edit";
  final String blurUrl = "http://192.168.1.2:5000/blur";
  final String enhanceUrl = "http://192.168.1.2:5000/enhance";
  final String healthUrl = "http://192.168.1.2:5000/";

  @override
  void initState() {
    super.initState();
    _adjectives.shuffle();
    _nouns.shuffle();
  }

  String generateFilterName(Map<String, dynamic> adjustments) {
    List<String> parts = [];
    adjustments.forEach((key, value) {
      if (value is num && value != 0) {
        String readableKey = key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
        String roundedValue = value.toStringAsFixed(2);
        parts.add("$readableKey $roundedValue");
      }
    });

    String humanReadable = parts.isEmpty ? "Default" : parts.join(", ");
    String jsonString = jsonEncode(adjustments);
    String hash = md5.convert(utf8.encode(jsonString + DateTime.now().toIso8601String()))
        .toString()
        .substring(0, 6);

    return "${_adjectives.first} ${_nouns.first} ($humanReadable) [$hash]";
  }

  String generateUniqueFilterName(Map<String, dynamic> adjustments) {
    List<String> parts = [];
    adjustments.forEach((key, value) {
      if (value is num && value != 0) {
        String readableKey = key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
        String roundedValue = value.toStringAsFixed(2);
        parts.add("$readableKey $roundedValue");
      }
    });

    String humanReadable = parts.isEmpty ? "Default" : parts.join(", ");
    String hash = md5
        .convert(utf8.encode(jsonEncode(adjustments) + DateTime.now().toIso8601String()))
        .toString()
        .substring(0, 6);

    return "${_adjectives.first} ${_nouns.first} ($humanReadable) [$hash]";
  }

  void showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.photos.request();
      await Permission.storage.request();
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }
  }

  Future<void> _checkApi() async {
    try {
      final res = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        showSnack("✓ Server connected successfully!", Colors.green);
      } else {
        showSnack("Server returned: ${res.statusCode}", Colors.orange);
      }
    } catch (e) {
      showSnack("✗ Cannot connect to server. Check your IP address.", Colors.red);
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _processedImage = null;
        _uploadedImageUrl = null;
      });
    }
  }

  Future<File> _bytesToFile(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/temp_blur_image.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  // FIXED: Apply Blur Function
  Future<void> _applyBlur() async {
    if ((_image == null && _processedImage == null) || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      File imageFile;
      if (_image != null) {
        imageFile = _image!;
      } else {
        imageFile = await _bytesToFile(_processedImage!);
      }

      var request = http.MultipartRequest("POST", Uri.parse(blurUrl));
      request.files.add(await http.MultipartFile.fromPath("image", imageFile.path));

      // Common blur fields - strength 0-100
      request.fields['blur_type'] = _blurType;
      request.fields['blur_strength'] = _blurStrength.toString();
      request.fields['feather'] = _feather.toString();

      // Type-specific parameters
      request.fields['strip_position'] = _stripPosition.toString();
      request.fields['strip_width'] = _stripWidth.toString();
      request.fields['radius_ratio'] = _radiusRatio.toString();
      request.fields['width_ratio'] = _widthRatio.toString();
      request.fields['height_ratio'] = _heightRatio.toString();
      request.fields['focus_region'] = _focusRegion;

      // Hand blur specific fields - send pixel coordinates
      if (_blurType == 'hand' && _handCenter != null) {
        // Get actual image dimensions
        Uint8List imageBytes;
        if (_processedImage != null) {
          imageBytes = _processedImage!;
        } else {
          imageBytes = await _image!.readAsBytes();
        }

        final ui.Image imageWidget = await decodeImageFromList(imageBytes);
        final actualImageWidth = imageWidget.width.toDouble();
        final actualImageHeight = imageWidget.height.toDouble();

        // Get display size from _imageSize (which is set in LayoutBuilder)
        if (_imageSize != null) {
          final displayWidth = _imageSize!.width;
          final displayHeight = _imageSize!.height;

          // Calculate scale factors
          final scaleX = actualImageWidth / displayWidth;
          final scaleY = actualImageHeight / displayHeight;

          // Scale the gesture coordinates to actual image coordinates
          final scaledX = (_handCenter!.dx * scaleX).toInt();
          final scaledY = (_handCenter!.dy * scaleY).toInt();
          final scaledRadius = (_handRadius * ((scaleX + scaleY) / 2)).toInt();

          request.fields['hand_x'] = scaledX.toString();
          request.fields['hand_y'] = scaledY.toString();
          request.fields['hand_radius'] = scaledRadius.toString();
          request.fields['hand_feather'] = _feather.toString();

          debugPrint("🎯 Hand blur: displaySize=$displayWidth×$displayHeight, imageSize=$actualImageWidth×$actualImageHeight");
          debugPrint("🎯 Gesture: center=(${_handCenter!.dx}, ${_handCenter!.dy}), radius=$_handRadius");
          debugPrint("🎯 Scaled: x=$scaledX, y=$scaledY, radius=$scaledRadius");
        }
      }

      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      if (streamedResponse.statusCode == 200) {
        final bytes = await streamedResponse.stream.toBytes();
        if (mounted) {
          setState(() {
            _processedImage = bytes;
            _isProcessing = false;
            _currentBlurName = "${_blurType.toUpperCase()} Blur (Strength: ${_blurStrength.toInt()})";
          });
        }
      } else {
        setState(() => _isProcessing = false);
        showSnack("Blur error: ${streamedResponse.statusCode}", Colors.red);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      showSnack("Failed to apply blur: ${e.toString()}", Colors.red);
    }
  }

// FIXED: Gesture Handler with proper coordinate mapping
  void _handleGesture(Offset start, Offset end, Size displaySize) {
    double dx = (end.dx - start.dx).abs();
    double dy = (end.dy - start.dy).abs();
    double centerX = (start.dx + end.dx) / 2;
    double centerY = (start.dy + end.dy) / 2;

    switch (_blurType) {
      case 'linear':
        if (dx > dy) {
          // Horizontal strip
          _stripPosition = (centerX / displaySize.width).clamp(0.0, 1.0);
          _stripWidth = (dx / displaySize.width).clamp(0.1, 0.8);
        } else {
          // Vertical strip
          _stripPosition = (centerY / displaySize.height).clamp(0.0, 1.0);
          _stripWidth = (dy / displaySize.height).clamp(0.1, 0.8);
        }
        break;

      case 'hand':
      // Store display coordinates - will be scaled in _applyBlur
        _handCenter = Offset(centerX, centerY);
        _handRadius = ((end - start).distance / 2).clamp(20.0, 200.0);
        debugPrint("👆 Gesture: center=($centerX, $centerY), radius=$_handRadius");
        break;

      case 'circular':
      case 'radial':
        _radiusRatio = ((dx + dy) / 2 / (displaySize.width / 2)).clamp(0.1, 0.8);
        break;

      case 'oval':
        _widthRatio = (dx / displaySize.width).clamp(0.1, 0.9);
        _heightRatio = (dy / displaySize.height).clamp(0.1, 0.9);
        break;

      case 'focus':
        double relX = centerX / displaySize.width;
        double relY = centerY / displaySize.height;
        if (relX < 0.33) {
          _focusRegion = 'left';
        } else if (relX > 0.67) {
          _focusRegion = 'right';
        } else if (relY < 0.33) {
          _focusRegion = 'top';
        } else if (relY > 0.67) {
          _focusRegion = 'bottom';
        } else {
          _focusRegion = 'center';
        }
        break;
    }

    setState(() {});
    _applyBlur();
  }
  Future<void> _enhanceImage() async {
    if (_image == null) {
      showSnack("No image selected", Colors.orange);
      return;
    }

    final fileSizeBytes = await _image!.length();
    final fileSizeMB = fileSizeBytes / (1024 * 1024);

    if (fileSizeMB >= 4.0) {
      showSnack("Image is already ${fileSizeMB.toStringAsFixed(2)} MB (≥4 MB)", Colors.orange);
      return;
    }

    try {
      var request = http.MultipartRequest("POST", Uri.parse(enhanceUrl));
      request.files.add(await http.MultipartFile.fromPath("image", _image!.path));
      request.fields["enhance"] = adjustments["enhance"]!.toString();
      request.fields["clarity"] = adjustments["clarity"]!.toString();
      request.fields["texture"] = adjustments["texture"]!.toString();

      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      if (streamedResponse.statusCode == 200) {
        final beforeBytes = await _image!.readAsBytes();
        final afterBytes = await streamedResponse.stream.toBytes();

        setState(() {
          _beforeEnhanceImage = beforeBytes;
          _afterEnhanceImage = afterBytes;
        });

        final beforeSizeMB = beforeBytes.length / (1024 * 1024);
        final afterSizeMB = afterBytes.length / (1024 * 1024);

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) {
              return AlertDialog(
                title: const Text("Image Enhancement Result"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Before Enhancement:", style: TextStyle(fontWeight: FontWeight.bold)),
                      if (_beforeEnhanceImage != null) Image.memory(_beforeEnhanceImage!, height: 150),
                      Text("Size: ${beforeSizeMB.toStringAsFixed(2)} MB"),
                      const SizedBox(height: 16),
                      const Text("After Enhancement:", style: TextStyle(fontWeight: FontWeight.bold)),
                      if (_afterEnhanceImage != null) Image.memory(_afterEnhanceImage!, height: 150),
                      Text("Size: ${afterSizeMB.toStringAsFixed(2)} MB"),
                      const SizedBox(height: 8),
                      Text("Size Increase: ${(afterSizeMB - beforeSizeMB).toStringAsFixed(2)} MB"),
                      const SizedBox(height: 8),
                      const Text("Changes Applied:", style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text("• Enhanced clarity and sharpness"),
                      const Text("• Improved texture details"),
                      const Text("• Optimized for 4MB+ file size"),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Close"),
                  ),
                ],
              );
            },
          );
        }
      } else {
        showSnack("Enhance error: ${streamedResponse.statusCode}", Colors.red);
      }
    } catch (e) {
      showSnack("Enhance failed: ${e.toString()}", Colors.red);
    }
  }

  Future<void> _saveImage() async {
    if (_processedImage == null && _image == null) {
      showSnack("No image to save!", Colors.orange);
      return;
    }

    try {
      await Permission.storage.request();
      Uint8List imageBytes = _processedImage ?? await _image!.readAsBytes();

      final result = await ImageGallerySaverPlus.saveImage(
        imageBytes,
        quality: 100,
        name: "edited_image_${DateTime.now().millisecondsSinceEpoch}",
      );

      bool success = false;
      if (result != null) {
        if (result is Map && result.containsKey('isSuccess')) {
          success = result['isSuccess'] == true;
        } else if (result is String && result.isNotEmpty) {
          success = true;
        }
      }

      showSnack(
        success ? "✅ Image saved to gallery!" : "❌ Failed to save image",
        success ? Colors.green : Colors.red,
      );
    } catch (e) {
      showSnack("Save failed: $e", Colors.red);
    }
  }

  Widget buildSlider(String label, String key, {double min = 0, double max = 100}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label)),
          Expanded(
            child: Slider(
              value: adjustments[key] ?? 0.0,
              min: min,
              max: max,
              divisions: ((max - min) * 100).toInt(), // Precision: 0.01 steps
              onChanged: (val) {
                setState(() {
                  adjustments[key] = val;
                  _currentFilterName = generateUniqueFilterName(adjustments);
                });

                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () async {
                  if (_image != null) {
                    final bytes = await _imageFilterService.previewFilterOnImage(_image!, adjustments);
                    if (bytes != null && mounted) {
                      setState(() => _processedImage = bytes);
                    }
                  }
                });
              },
            ),
          ),
          SizedBox(
            width: 50, // Increased width to accommodate 2 decimals
            child: Text(
              (adjustments[key] ?? 0.0).toStringAsFixed(2), // ⭐ CHANGED: 2 decimals
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManipulationTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("Basic Adjustments", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          buildSlider("Brightness", "brightness", min: -100, max: 100),
          buildSlider("Contrast", "contrast", min: -100, max: 100),
          buildSlider("Saturation", "saturation", min: -100, max: 100),
          buildSlider("Exposure", "exposure", min: -100, max: 100),
          buildSlider("Highlights", "highlights", min: -100, max: 100),
          buildSlider("Shadows", "shadows", min: -100, max: 100),
          buildSlider("Vibrance", "vibrance", min: -100, max: 100),
          buildSlider("Temperature", "temperature", min: -100, max: 100),
          buildSlider("Hue", "hue", min: -100, max: 100),
          buildSlider("Tint", "tint", min: -100, max: 100),
          buildSlider("Fading", "fading", min: 0, max: 100),
          buildSlider("Enhance", "enhance", min: -100, max: 100),
          buildSlider("Smoothness", "smoothness", min: -100, max: 100),
          buildSlider("Ambiance", "ambiance", min: -100, max: 100),
          buildSlider("Inner Spotlight", "inner_spotlight", min: -100, max: 100),
          buildSlider("Outer Spotlight", "outer_spotlight", min: -100, max: 100),
          buildSlider("Noise", "noise", min: 0, max: 100),
          buildSlider("Color Noise", "color_noise", min: 0, max: 100),
          const Divider(thickness: 2),
          ExpansionTile(
            title: const Text("Effects", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Texture", "texture"),
              buildSlider("Clarity", "clarity"),
              buildSlider("Dehaze", "dehaze"),
            ],
          ),
          ExpansionTile(
            title: const Text("Sharpening", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Amount", "sharpen_amount"),
              buildSlider("Radius", "sharpen_radius", min: 1, max: 10),
              buildSlider("Detail", "sharpen_detail", min: 1, max: 10),
              buildSlider("Masking", "sharpen_masking"),
            ],
          ),
          ExpansionTile(
            title: const Text("Grain", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Amount", "grain_amount", min: 0, max: 100),
              buildSlider("Size", "grain_size", min: 1, max: 10),
              buildSlider("Roughness", "grain_roughness", min: 1, max: 10),
            ],
          ),
          ExpansionTile(
            title: const Text("Vignette", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Amount", "vignette_amount"),
              buildSlider("Midpoint", "vignette_midpoint", min: 0, max: 100),
              buildSlider("Feather", "vignette_feather", min: 0, max: 100),
              buildSlider("Roundness", "vignette_roundness"),
              buildSlider("Highlights", "vignette_highlights"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancementTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_fix_high, size: 80, color: Colors.blue),
          const SizedBox(height: 20),
          const Text(
            "Image Enhancement",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Enhance images smaller than 4MB to reach or exceed 4MB with improved quality.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _image == null ? null : _enhanceImage,
            icon: const Icon(Icons.upgrade),
            label: const Text("Enhance Image"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 20),
          if (_beforeEnhanceImage != null && _afterEnhanceImage != null)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text("Before", style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Image.memory(_beforeEnhanceImage!)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Text("After", style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Image.memory(_afterEnhanceImage!)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // FIXED: Blur Tab UI with cleaner sliders
  Widget _buildBlurTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("Blur Effects",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),

          // Blur type chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text("Linear"),
                selected: _blurType == 'linear',
                onSelected: (selected) {
                  setState(() => _blurType = 'linear');
                  _applyBlur();
                },
              ),
              ChoiceChip(
                label: const Text("Radial"),
                selected: _blurType == 'radial',
                onSelected: (selected) {
                  setState(() => _blurType = 'radial');
                  _applyBlur();
                },
              ),
              ChoiceChip(
                label: const Text("Circular"),
                selected: _blurType == 'circular',
                onSelected: (selected) {
                  setState(() => _blurType = 'circular');
                  _applyBlur();
                },
              ),
              ChoiceChip(
                label: const Text("Oval"),
                selected: _blurType == 'oval',
                onSelected: (selected) {
                  setState(() => _blurType = 'oval');
                  _applyBlur();
                },
              ),
              ChoiceChip(
                label: const Text("Focus"),
                selected: _blurType == 'focus',
                onSelected: (selected) {
                  setState(() => _blurType = 'focus');
                  _applyBlur();
                },
              ),
              ChoiceChip(
                label: const Text("Hand"),
                selected: _blurType == 'hand',
                onSelected: (selected) {
                  setState(() => _blurType = 'hand');
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Blur Strength Slider (0-100)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Blur Strength", style: TextStyle(fontSize: 16)),
                    Text("${_blurStrength.toInt()}",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _blurStrength,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: _blurStrength.toInt().toString(),
                  onChanged: (val) {
                    setState(() => _blurStrength = val);
                  },
                  onChangeEnd: (val) {
                    _applyBlur();
                  },
                ),
              ],
            ),
          ),

          // Feather Slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Edge Softness", style: TextStyle(fontSize: 16)),
                    Text("${_feather.toInt()}",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _feather,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: _feather.toInt().toString(),
                  onChanged: (val) {
                    setState(() => _feather = val);
                  },
                  onChangeEnd: (val) {
                    _applyBlur();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(),

          // Instructions
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Text("How to use:",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text("• Adjust 'Blur Strength' slider to control blur intensity"),
                  const Text("• Adjust 'Edge Softness' for smoother transitions"),
                  const Text("• Draw on image to define blur area:"),
                  const SizedBox(height: 4),
                  Text("  - ${_blurType == 'linear' ? 'Drag to set strip position & width' : ''}"),
                  Text("  - ${_blurType == 'hand' ? 'Drag to set center & radius' : ''}"),
                  Text("  - ${_blurType == 'circular' || _blurType == 'radial' ? 'Drag to set radius' : ''}"),
                  Text("  - ${_blurType == 'oval' ? 'Drag to set oval size' : ''}"),
                  Text("  - ${_blurType == 'focus' ? 'Tap region to focus' : ''}"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Image Editor"),
        actions: [
          IconButton(
            onPressed: _checkApi,
            icon: const Icon(Icons.cloud),
            tooltip: "Check API",
          ),
          IconButton(
            onPressed: _pickImage,
            icon: const Icon(Icons.image),
            tooltip: "Pick Image",
          ),
          IconButton(
            onPressed: _saveImage,
            icon: const Icon(Icons.save),
            tooltip: "Save Image",
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PhotoHubScreen()),
              );
            },
            icon: const Icon(Icons.photo_library),
            tooltip: "Open Photo Hub",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 0),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTab == 0 ? Colors.blue : Colors.grey[300],
                      foregroundColor: _selectedTab == 0 ? Colors.white : Colors.black,
                    ),
                    child: const Text("Manipulation"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTab == 1 ? Colors.blue : Colors.grey[300],
                      foregroundColor: _selectedTab == 1 ? Colors.white : Colors.black,
                    ),
                    child: const Text("Enhancement"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 2),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTab == 2 ? Colors.blue : Colors.grey[300],
                      foregroundColor: _selectedTab == 2 ? Colors.white : Colors.black,
                    ),
                    child: const Text("Blurring"),
                  ),
                ),
              ],
            ),
          ),
          if (_image != null)
            Expanded(
              flex: 2,
              child: Stack(
                children: [
                  GestureDetector(
                    onPanStart: _selectedTab == 2
                        ? (details) => setState(() => _gestureStart = details.localPosition)
                        : null,
                    onPanUpdate: _selectedTab == 2
                        ? (details) => setState(() => _gestureEnd = details.localPosition)
                        : null,
                    onPanEnd: _selectedTab == 2
                        ? (details) {
                      if (_gestureStart != null && _gestureEnd != null && _imageSize != null) {
                        _handleGesture(_gestureStart!, _gestureEnd!, _imageSize!);
                      }
                      setState(() {
                        _gestureStart = null;
                        _gestureEnd = null;
                      });
                    }
                        : null,
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        // Store size after frame is built
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            final newSize = Size(constraints.maxWidth, constraints.maxHeight);
                            if (_imageSize != newSize) {
                              setState(() {
                                _imageSize = newSize;
                              });
                            }
                          }
                        });

                        if (_image == null) {
                          return const Center(child: Text("No image selected"));
                        }

                        return _processedImage != null
                            ? Image.memory(_processedImage!, fit: BoxFit.contain)
                            : Image.file(_image!, key: _imageKey, fit: BoxFit.contain);
                      },
                    ),
                  ),
                  if ((_selectedTab == 0 && _currentFilterName != null) ||
                      (_selectedTab == 2 && _currentBlurName != null))
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _selectedTab == 2 ? (_currentBlurName ?? '') : (_currentFilterName ?? ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_image != null) ...[
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isProcessing || _processedImage == null)
                          ? null
                          : () async {
                        setState(() => _isProcessing = true);
                        final url = await _imageFilterService.uploadImage(_processedImage!);
                        setState(() {
                          _uploadedImageUrl = url;
                          _isProcessing = false;
                        });
                        if (url != null) {
                          showSnack("✅ Image uploaded to cloud!", Colors.green);
                        } else {
                          showSnack("❌ Upload failed", Colors.red);
                        }
                      },
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text("Upload Image"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isProcessing || _uploadedImageUrl == null)
                          ? null
                          : () async {
                        setState(() => _isProcessing = true);
                        _currentFilterName ??= generateUniqueFilterName(adjustments);
                        await _imageFilterService.createFilterFromUrl(
                          _uploadedImageUrl!,
                          _currentFilterName!,
                          adjustments,
                        );
                        setState(() => _isProcessing = false);
                        showSnack("✅ Filter created in database!", Colors.green);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text("Create Filter"),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isLoading) const LinearProgressIndicator(),
          Expanded(
            child: _selectedTab == 0
                ? _buildManipulationTab()
                : _selectedTab == 1
                ? _buildEnhancementTab()
                : _buildBlurTab(),
          ),
        ],
      ),
    );
  }
}


// END OF HOME PAGE

// PHOTOHUBSCREEN

class PhotoHubScreen extends StatefulWidget {
  const PhotoHubScreen({super.key});

  @override
  State<PhotoHubScreen> createState() => _PhotoHubScreenState();
}

class _PhotoHubScreenState extends State<PhotoHubScreen> {
  File? selectedImage;
  final ImagePicker _picker = ImagePicker();

  // Pick image from gallery
  Future<void> pickImageFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        selectedImage = File(image.path);
      });
    }
  }

  // Pick image from camera
  Future<void> pickImageFromCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        selectedImage = File(image.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Photo Hub")),
      body: Column(
        children: [
          const SizedBox(height: 20),
          selectedImage != null
              ? Image.file(selectedImage!, height: 250)
              : Container(
            height: 250,
            color: Colors.grey[300],
            child: const Center(child: Text("No image selected")),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: pickImageFromGallery,
                child: const Text("Upload"),
              ),
              ElevatedButton(
                onPressed: pickImageFromCamera,
                child: const Text("Camera"),
              ),
              ElevatedButton(
                onPressed: selectedImage != null
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          EditImagePage(image: selectedImage),
                    ),
                  );
                }
                    : null,
                child: const Text("Edit"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FilterGalleryScreen(image: selectedImage),
                    ),
                  );
                },
                child: const Text("Filters"),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PhotographyFormScreen(),
              ),
            );
          },
          icon: const Icon(Icons.add_a_photo),
          label: const Text("Go to Photography Form"),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ),
    );
  }
}

// ------------------ Edit Image Page ------------------
class EditImagePage extends StatefulWidget {
  final File? image;
  const EditImagePage({super.key, this.image});

  @override
  State<EditImagePage> createState() => _EditImagePageState();
}

class _EditImagePageState extends State<EditImagePage> {
  Uint8List? displayedImage;
  bool _loading = false;
  Timer? _debounce;
  final GlobalKey _previewKey = GlobalKey();

  final Map<String, double> adjustments = {
    "brightness": 0,
    "contrast": 1,
    "saturation": 1,
    "exposure": 0,
    "highlights": 0,
    "shadows": 0,
    "vibrance": 1,
    "temperature": 0,
    "hue": 0,
    "fading": 0,
    "enhance": 0,
    "smoothness": 0,
    "ambiance": 0,
    "noise": 0,
    "color_noise": 0,
    "inner_spotlight": 0,
    "outer_spotlight": 0,
    "tint": 0,
    "texture": 0,
    "clarity": 0,
    "dehaze": 0,
    "grain_amount": 0,
    "grain_size": 1,
    "grain_roughness": 1,
    "sharpen_amount": 0,
    "sharpen_radius": 1,
    "sharpen_detail": 1,
    "sharpen_masking": 0,
    "vignette_amount": 0,
    "vignette_midpoint": 50,
    "vignette_feather": 50,
    "vignette_roundness": 0,
    "vignette_highlights": 0,
  };

  @override
  void initState() {
    super.initState();
    if (widget.image != null) {
      displayedImage = widget.image!.readAsBytesSync();
    }
  }

  Future<Uint8List?> sendToEditApi({
    required File imageFile,
    required Map<String, double> adjustments,
  }) async {
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("http://192.168.1.2:5000/edit"),
      );

      request.files.add(await http.MultipartFile.fromPath("image", imageFile.path));

      adjustments.forEach((key, value) {
        if (value != 0 && value != 1) {
          request.fields[key] = value.toString();
        }
      });

      var response = await request.send();

      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        return Uint8List.fromList(bytes);
      } else {
        print("Edit API failed: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Error sending image to API: $e");
      return null;
    }
  }

  void onSliderChange(String key, double value) {
    setState(() => adjustments[key] = value);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      applyAdjustments();
    });
  }

  Future<void> applyAdjustments() async {
    if (widget.image == null) return;

    setState(() => _loading = true);
    try {
      final editedBytes = await sendToEditApi(
        imageFile: widget.image!,
        adjustments: adjustments,
      );

      if (editedBytes != null) {
        setState(() {
          displayedImage = editedBytes;
        });
      } else {
        print("⚠️ Failed to update image");
      }
    } catch (e) {
      print("API Error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> saveFilteredImage() async {
    try {
      RenderRepaintBoundary boundary =
      _previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final result = await ImageGallerySaverPlus.saveImage(
        pngBytes,
        quality: 100,
        name: "filtered_${DateTime.now().millisecondsSinceEpoch}",
      );

      showSnack("✅ Saved to gallery!", Colors.green);
      debugPrint("💾 Saved: $result");
    } catch (e) {
      showSnack("❌ Failed to save: $e", Colors.red);
    }
  }

  Widget buildSlider(String label, String key, {double min = -100, double max = 100}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ${adjustments[key]!.toStringAsFixed(2)}"),
        Slider(
          value: adjustments[key]!,
          min: min,
          max: max,
          onChanged: (val) => onSliderChange(key, val),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildManipulationTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              "Basic Adjustments",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          buildSlider("Brightness", "brightness", min: -100, max: 100),
          buildSlider("Contrast", "contrast", min: -100, max: 100),
          buildSlider("Saturation", "saturation", min: -100, max: 100),
          buildSlider("Exposure", "exposure", min: -100, max: 100),
          buildSlider("Highlights", "highlights", min: -100, max: 100),
          buildSlider("Shadows", "shadows", min: -100, max: 100),
          buildSlider("Vibrance", "vibrance", min: -100, max: 100),
          buildSlider("Temperature", "temperature", min: -100, max: 100),
          buildSlider("Hue", "hue", min: -100, max: 100),
          buildSlider("Tint", "tint", min: -100, max: 100),
          buildSlider("Fading", "fading", min: 0, max: 100),
          buildSlider("Enhance", "enhance", min: -100, max: 100),
          buildSlider("Smoothness", "smoothness", min: -100, max: 100),
          buildSlider("Ambiance", "ambiance", min: -100, max: 100),
          buildSlider("Inner Spotlight", "inner_spotlight", min: -100, max: 100),
          buildSlider("Outer Spotlight", "outer_spotlight", min: -100, max: 100),
          buildSlider("Noise", "noise", min: 0, max: 100),
          buildSlider("Color Noise", "color_noise", min: 0, max: 100),
          const Divider(thickness: 2),
          ExpansionTile(
            title: const Text("Effects", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Texture", "texture"),
              buildSlider("Clarity", "clarity"),
              buildSlider("Dehaze", "dehaze"),
            ],
          ),
          ExpansionTile(
            title: const Text("Sharpening", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Amount", "sharpen_amount"),
              buildSlider("Radius", "sharpen_radius", min: 1, max: 10),
              buildSlider("Detail", "sharpen_detail", min: 1, max: 10),
              buildSlider("Masking", "sharpen_masking"),
            ],
          ),
          ExpansionTile(
            title: const Text("Grain", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Amount", "grain_amount", min: 0, max: 100),
              buildSlider("Size", "grain_size", min: 1, max: 10),
              buildSlider("Roughness", "grain_roughness", min: 1, max: 10),
            ],
          ),
          ExpansionTile(
            title: const Text("Vignette", style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              buildSlider("Amount", "vignette_amount"),
              buildSlider("Midpoint", "vignette_midpoint", min: 0, max: 100),
              buildSlider("Feather", "vignette_feather", min: 0, max: 100),
              buildSlider("Roundness", "vignette_roundness"),
              buildSlider("Highlights", "vignette_highlights"),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Image"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: saveFilteredImage,
            tooltip: "Save to Gallery",
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          RepaintBoundary(
            key: _previewKey,
            child: displayedImage != null
                ? Image.memory(displayedImage!, height: 250)
                : const SizedBox(height: 250),
          ),
          Expanded(child: _buildManipulationTab()),
        ],
      ),
    );
  }
}

// ------------------ Filter Gallery Screen ------------------
// Replace the FilterGalleryScreen class with this enhanced version

class FilterGalleryScreen extends StatefulWidget {
  final File? image;

  const FilterGalleryScreen({super.key, this.image});

  @override
  State<FilterGalleryScreen> createState() => _FilterGalleryScreenState();
}

class _FilterGalleryScreenState extends State<FilterGalleryScreen> {
  List<Map<String, dynamic>> filters = [];
  bool _loading = true;
  bool getAll = true;
  final TextEditingController idController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // State variables
  File? _selectedImage;
  Map<String, dynamic>? _selectedFilter;
  Map<String, dynamic> _adjustedParams = {}; // Store adjusted values
  GlobalKey _previewKey = GlobalKey();
  bool _showSliders = false;

  @override
  void initState() {
    super.initState();
    fetchAllFilters();
  }

  // Fetch All Filters
  Future<void> fetchAllFilters() async {
    setState(() => _loading = true);
    try {
      final response = await http
          .get(Uri.parse("https://new-camme-backend.onrender.com/api/v1/image/get-all"))
          .timeout(const Duration(seconds: 180));

      debugPrint("📡 Response status: ${response.statusCode}");
      debugPrint("📡 Raw response data: ${response.body}");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic>? dataList = decoded["data"];

        if (dataList != null && dataList.isNotEmpty) {
          filters = dataList.map<Map<String, dynamic>>((item) {
            final filterData = item["filters"] ?? {};
            return {
              "_id": item["_id"],
              "filter_name": filterData["filter_name"] ?? "Unnamed",
              "params": Map<String, dynamic>.from(filterData["params"] ?? {}),
              "image_url": item["image_data"]?.toString() ?? "",
            };
          }).toList();

          debugPrint("📂 Total filters received: ${filters.length}");
        } else {
          filters = [];
          showSnack("No filters found", Colors.orange);
        }
      } else {
        showSnack("Failed to fetch filters: ${response.statusCode}", Colors.red);
        filters = [];
      }
    } catch (e) {
      showSnack("Error fetching filters: $e", Colors.red);
      filters = [];
    } finally {
      setState(() => _loading = false);
    }
  }

  // Fetch Filter by ID
  Future<void> fetchById(String imageId) async {
    if (imageId.isEmpty) return;
    setState(() => _loading = true);

    try {
      final uri = Uri.parse(
          "https://new-camme-backend.onrender.com/api/v1/image/get-by-id?imageId=${Uri.encodeComponent(imageId)}");
      final response = await http.get(uri).timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded["data"];

        if (data != null) {
          final filterData = data["filters"] ?? {};
          setState(() {
            filters = [
              {
                "_id": data["_id"],
                "filter_name": filterData["filter_name"] ?? "Unnamed",
                "params": Map<String, dynamic>.from(filterData["params"] ?? {}),
                "image_url": data["image_data"]?.toString() ?? "",
              }
            ];
          });
        } else {
          showSnack("No filter found for this ID", Colors.orange);
          filters = [];
        }
      } else {
        showSnack("Filter not found: ${response.statusCode}", Colors.red);
        filters = [];
      }
    } catch (e) {
      showSnack("Error fetching filter: $e", Colors.red);
      filters = [];
    } finally {
      setState(() => _loading = false);
    }
  }

  // Save Updated Filter to Database
  Future<void> _saveUpdatedFilter() async {
    if (_selectedFilter == null || _selectedImage == null) return;

    setState(() => _loading = true);
    try {
      // First upload the filtered image
      final bytes = await _captureFilteredImage();
      if (bytes == null) {
        showSnack("Failed to capture filtered image", Colors.red);
        return;
      }

      // Upload image to get URL
      final imageUrl = await _uploadImageToCloud(bytes);
      if (imageUrl == null) {
        showSnack("Failed to upload image", Colors.red);
        return;
      }

      // Generate new filter name
      final newFilterName = _generateFilterName(_adjustedParams);

      // Send to backend
      final payload = {
        "image_url": imageUrl,
        "filter_data": {
          "filter_name": newFilterName,
          "params": _adjustedParams,
        }
      };

      final response = await http.post(
        Uri.parse("https://new-camme-backend.onrender.com/api/v1/image/process"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        showSnack("✅ Filter saved successfully!", Colors.green);
        fetchAllFilters(); // Refresh the list
      } else {
        showSnack("Failed to save filter: ${response.statusCode}", Colors.red);
      }
    } catch (e) {
      showSnack("Error saving filter: $e", Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  // Generate filter name
  String _generateFilterName(Map<String, dynamic> params) {
    List<String> parts = [];
    params.forEach((key, value) {
      if (value is num && value != 0) {
        String readableKey = key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
        parts.add("$readableKey ${value.toStringAsFixed(2)}");
      }
    });

    String hash = md5
        .convert(utf8.encode(jsonEncode(params) + DateTime.now().toIso8601String()))
        .toString()
        .substring(0, 6);

    return "Custom Filter (${parts.isEmpty ? 'Default' : parts.take(2).join(', ')}) [$hash]";
  }

  // Capture filtered image as bytes
  Future<Uint8List?> _captureFilteredImage() async {
    try {
      RenderRepaintBoundary boundary =
      _previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("Error capturing image: $e");
      return null;
    }
  }

  // Upload image to cloud
  Future<String?> _uploadImageToCloud(Uint8List imageBytes) async {
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("https://new-camme-backend.onrender.com/api/v1/upload-file"),
      );
      request.files.add(
        http.MultipartFile.fromBytes("file", imageBytes, filename: 'image.jpg'),
      );

      var streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final url = data['data']?['fileUrl'];
        return url;
      }
      return null;
    } catch (e) {
      debugPrint("Upload error: $e");
      return null;
    }
  }

  void showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  Widget buildNetworkImage(String url) {
    if (url.isEmpty) {
      return const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey));
    }
    return Image.network(
      Uri.encodeFull(url),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  void _showImageSourcePicker(Map<String, dynamic> filter) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("Gallery"),
                onTap: () => _pickImage(ImageSource.gallery, filter),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Camera"),
                onTap: () => _pickImage(ImageSource.camera, filter),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source, Map<String, dynamic> filter) async {
    Navigator.pop(context);
    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() {
      _selectedImage = File(picked.path);
      _selectedFilter = filter;
      _adjustedParams = Map<String, dynamic>.from(filter["params"] ?? {});
      _showSliders = false;
    });

    showSnack("Filter '${filter["filter_name"]}' applied!", Colors.blue);
  }

  ColorFilter _buildColorFilter(Map<String, dynamic> params) {
    if (params.isEmpty) {
      return const ColorFilter.matrix([
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    }

    double brightness = (params['brightness'] ?? 0).toDouble();
    double contrast = (params['contrast'] ?? 0).toDouble();
    double saturation = (params['saturation'] ?? 0).toDouble();
    double exposure = (params['exposure'] ?? 0).toDouble();
    double temperature = (params['temperature'] ?? 50).toDouble();
    double tint = (params['tint'] ?? 50).toDouble();

    double b = brightness / 100.0;
    double c = 1 + (contrast / 200.0);
    double s = 1 + (saturation / 100.0);
    double e = exposure / 200.0;

    double rMult = 1 + ((temperature - 50) / 200.0);
    double gMult = 1 + ((tint - 50) / 200.0);
    double bMult = 1 - ((temperature - 50) / 200.0);

    rMult = rMult.clamp(0.5, 1.5);
    gMult = gMult.clamp(0.5, 1.5);
    bMult = bMult.clamp(0.5, 1.5);

    double offset = (b + e) * 128.0;

    List<double> matrix = [
      c * s * rMult, 0, 0, 0, offset,
      0, c * s * gMult, 0, 0, offset,
      0, 0, c * s * bMult, 0, offset,
      0, 0, 0, 1, 0,
    ];

    return ColorFilter.matrix(matrix);
  }

  Future<void> _saveFilteredImage() async {
    try {
      RenderRepaintBoundary boundary =
      _previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final result = await ImageGallerySaverPlus.saveImage(
        pngBytes,
        quality: 100,
        name: "filtered_${DateTime.now().millisecondsSinceEpoch}",
      );

      showSnack("✅ Saved to gallery!", Colors.green);
    } catch (e) {
      showSnack("❌ Failed to save: $e", Colors.red);
    }
  }

  // Build adjustable slider
  Widget _buildAdjustableSlider(String label, String key, {double min = -100, double max = 100}) {
    // Get value and clamp it to the valid range
    double rawValue = (_adjustedParams[key] ?? 0).toDouble();
    double currentValue = rawValue.clamp(min, max);

    // If value was out of range, update it
    if (rawValue != currentValue) {
      _adjustedParams[key] = currentValue;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Slider(
              value: currentValue,
              min: min,
              max: max,
              divisions: ((max - min) * 10).toInt(),
              onChanged: (val) {
                setState(() {
                  _adjustedParams[key] = val;
                });
              },
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              currentValue.toStringAsFixed(1),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderPanel() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            "Adjust Filter",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildAdjustableSlider("Brightness", "brightness", min: -100, max: 100),
                  _buildAdjustableSlider("Contrast", "contrast", min: -100, max: 100),
                  _buildAdjustableSlider("Saturation", "saturation", min: -100, max: 100),
                  _buildAdjustableSlider("Exposure", "exposure", min: -100, max: 100),
                  _buildAdjustableSlider("Temperature", "temperature", min: -100, max: 100),
                  _buildAdjustableSlider("Tint", "tint", min: -100, max: 100),
                  _buildAdjustableSlider("Highlights", "highlights", min: -100, max: 100),
                  _buildAdjustableSlider("Shadows", "shadows", min: -100, max: 100),
                  _buildAdjustableSlider("Vibrance", "vibrance", min: -100, max: 100),
                  _buildAdjustableSlider("Hue", "hue", min: -100, max: 100),
                  _buildAdjustableSlider("Fading", "fading", min: 0, max: 100),
                  _buildAdjustableSlider("Enhance", "enhance", min: -100, max: 100),
                  _buildAdjustableSlider("Smoothness", "smoothness", min: -100, max: 100),
                  _buildAdjustableSlider("Texture", "texture", min: 0, max: 100),
                  _buildAdjustableSlider("Clarity", "clarity", min: 0, max: 100),
                  _buildAdjustableSlider("Dehaze", "dehaze", min: 0, max: 100),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text("Cancel"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _adjustedParams = Map<String, dynamic>.from(_selectedFilter!["params"] ?? {});
                        _showSliders = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("Save to DB"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    onPressed: _saveUpdatedFilter,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🎨 Saved Filters")),
      body: Stack(
        children: [
          Column(
            children: [
              if (_selectedImage != null && _selectedFilter != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: RepaintBoundary(
                    key: _previewKey,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        ColorFiltered(
                          colorFilter: _buildColorFilter(_adjustedParams),
                          child: Image.file(
                            _selectedImage!,
                            height: 300,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                              padding: const EdgeInsets.all(8),
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedImage = null;
                                _selectedFilter = null;
                                _showSliders = false;
                              });
                            },
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "Filter: ${_selectedFilter!['filter_name']}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.tune, size: 18),
                                    label: const Text("Adjust"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    onPressed: () {
                                      setState(() => _showSliders = !_showSliders);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.photo_library, size: 18),
                                    label: const Text("Change"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    onPressed: () => _showImageSourcePicker(_selectedFilter!),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.save_alt, size: 18),
                                    label: const Text("Save"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    onPressed: _saveFilteredImage,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            getAll = true;
                            fetchAllFilters();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: getAll ? Colors.blue : Colors.grey),
                        child: const Text("Get All Filters"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            getAll = false;
                            if (idController.text.isNotEmpty) {
                              fetchById(idController.text);
                            }
                          });
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: !getAll ? Colors.blue : Colors.grey),
                        child: const Text("Get By ID"),
                      ),
                    ),
                  ],
                ),
              ),

              if (!getAll)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TextField(
                    controller: idController,
                    decoration: InputDecoration(
                      labelText: "Enter Filter ID",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          if (idController.text.isNotEmpty) fetchById(idController.text);
                        },
                      ),
                    ),
                  ),
                ),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filters.isEmpty
                    ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.filter_none, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("No filters found"),
                    ],
                  ),
                )
                    : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: filters.length,
                  itemBuilder: (context, index) {
                    final filter = filters[index];
                    final isSelected = _selectedFilter != null &&
                        _selectedFilter!['_id'] == filter['_id'];

                    return InkWell(
                      onTap: () => _showImageSourcePicker(filter),
                      child: Card(
                        elevation: isSelected ? 8 : 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isSelected
                              ? const BorderSide(color: Colors.blue, width: 3)
                              : BorderSide.none,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius:
                                const BorderRadius.vertical(top: Radius.circular(12)),
                                child: buildNetworkImage(filter["image_url"] ?? ""),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                filter["filter_name"] ?? "Unnamed",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isSelected ? Colors.blue : Colors.black,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          // Slider Panel Overlay
          if (_showSliders)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildSliderPanel(),
            ),
        ],
      ),
    );
  }
}
//END OF PHOTOHUBSCREEN

class PhotographyFormScreen extends StatefulWidget {
  const PhotographyFormScreen({Key? key}) : super(key: key);

  @override
  State<PhotographyFormScreen> createState() => _PhotographyFormScreenState();
}

class _PhotographyFormScreenState extends State<PhotographyFormScreen> {
  // --- User selections ---
  String? _age;
  String? _gender;
  String? _pose;
  String? _object;
  String? _location;
  String? _pet;
  String? _height;
  String? _size;

  // Tags and search query
  String _tags = '';
  String _searchQuery = '';

  // Options
  final List<String> ages = ['0-18', '19-35', '36-60', 'Above 60'];
  final List<String> genders = ['Male', 'Female'];
  final List<String> poses = [
    'Driving',
    'Sitting',
    'Writing',
    'Standing',
    'Playing',
    'Swimming',
    'Seeing',
    'Couple',
    'Portrait',
    'Walking',
    'Running',
    'Hitting',
    'Reading',
    'Riding'
  ];
  final List<String> objects = [
    'Laptop', 'Cricket Bat', 'Bike', 'Car', 'Carroms', 'Cricket Ball',
    'Basket Ball', 'Base Ball', 'Chair', 'Table', 'Mobile', 'Chess',
    'Cycle', 'Football', 'Bed'
  ];
  final List<String> locations = [
    'Train',
    'Shopping Mall',
    'Elevator',
    'Temple',
    'Restaurant',
    'Railway Station',
    'Metro Station',
    'Bedroom',
    'Classroom',
    'Park',
    'Factory',
    'Bus Stop',
    'Bus',
    'Movie Hall',
    'Hotel',
    'Tear',
    'Beach',
    'Boat',
    'Road',
    'Fuel Station',
    'School',
    'Subway'
  ];
  final List<String> pets = ['Cow', 'Cat', 'Dog', 'Peacock', 'Rabbit'];
  final List<String> heights = [
    'Below 5 feet',
    'Between 5-6 feet',
    'Above 6 feet'
  ];
  final List<String> sizes = ['Skinny', 'Fat', 'Bold'];

  void _generateTagsAndQuery() {
    List<String> selectedTags = [];
    if (_age != null) selectedTags.add(_age!);
    if (_gender != null) selectedTags.add(_gender!);
    if (_pose != null) selectedTags.add(_pose!);
    if (_object != null) selectedTags.add(_object!);
    if (_location != null) selectedTags.add(_location!);
    if (_pet != null) selectedTags.add(_pet!);
    if (_height != null) selectedTags.add(_height!);
    if (_size != null) selectedTags.add(_size!);

    setState(() {
      _tags = selectedTags.join(", ");

      // Build sentence
      String ageText = '';
      if (_age != null && _gender != null) {
        if (_age == '0-18')
          ageText = _gender == 'Male' ? 'boy' : 'girl';
        else if (_age == '19-35')
          ageText = _gender == 'Male' ? 'man' : 'woman';
        else
          ageText = 'elderly';
      }

      String sizeText = _size != null ? _size!.toLowerCase() : '';
      String heightText = _height != null
          ? (_height == 'Below 5 feet'
          ? 'short'
          : _height == 'Between 5-6 feet'
          ? 'average height'
          : 'tall')
          : '';

      List<String> adjectives = [];
      if (sizeText.isNotEmpty) adjectives.add(sizeText);
      if (heightText.isNotEmpty) adjectives.add(heightText);

      String adjText = adjectives.isNotEmpty ? adjectives.join(" and ") : '';

      String poseText = _pose != null ? _pose!.toLowerCase() : '';
      String objectText = _object != null ? _object!.toLowerCase() : '';
      String petText = _pet != null ? _pet!.toLowerCase() : '';
      String locationText = _location != null ? _location!.toLowerCase() : '';

      _searchQuery =
          "A ${adjText.isNotEmpty ? '$adjText ' : ''}${ageText.isNotEmpty
              ? '$ageText '
              : ''}${poseText.isNotEmpty ? 'using $objectText ' : ''}${poseText
              .isNotEmpty ? '$poseText ' : ''}${petText.isNotEmpty
              ? 'with $petText '
              : ''}${locationText.isNotEmpty ? 'in a $locationText' : ''}"
              .trim();
    });
  }

  Widget _buildDropdown(String label, List<String> options, String? value,
      Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        value: value,
        items: options
            .map((e) =>
            DropdownMenuItem(
              value: e,
              child: Text(e),
            ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Photography Form")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDropdown("Age", ages, _age, (val) {
              setState(() => _age = val);
              _generateTagsAndQuery();
            }),
            _buildDropdown("Gender", genders, _gender, (val) {
              setState(() => _gender = val);
              _generateTagsAndQuery();
            }),
            _buildDropdown("Pose", poses, _pose, (val) {
              setState(() => _pose = val);
              _generateTagsAndQuery();
            }),
            _buildDropdown("Object", objects, _object, (val) {
              setState(() => _object = val);
              _generateTagsAndQuery();
            }),
            _buildDropdown("Location", locations, _location, (val) {
              setState(() => _location = val);
              _generateTagsAndQuery();
            }),
            _buildDropdown("Pet", pets, _pet, (val) {
              setState(() => _pet = val);
              _generateTagsAndQuery();
            }),
            _buildDropdown("Height", heights, _height, (val) {
              setState(() => _height = val);
              _generateTagsAndQuery();
            }),
            _buildDropdown("Size", sizes, _size, (val) {
              setState(() => _size = val);
              _generateTagsAndQuery();
            }),
            const SizedBox(height: 20),
            Text("Tags:", style: Theme
                .of(context)
                .textTheme
                .titleMedium),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_tags.isEmpty ? "No tags selected" : _tags),
            ),
            Text("Photography Search Query:",
                style: Theme
                    .of(context)
                    .textTheme
                    .titleMedium),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_searchQuery.isEmpty
                  ? "No search query generated"
                  : _searchQuery),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          onPressed: () async {
            List<CameraDescription> cameras = await availableCameras();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PhotographyScreen(),
              ),
            );
          },
          icon: const Icon(Icons.camera_alt),
          label: const Text("Go to Photography Screen"),
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50)),
        ),
      ),
    );
  }
}
// end of photographyformscreen
// photographyscreen

class PhotographyScreen extends StatefulWidget {
  const PhotographyScreen({Key? key}) : super(key: key);

  @override
  State<PhotographyScreen> createState() => _PhotographyScreenState();
}

class _PhotographyScreenState extends State<PhotographyScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isBackCamera = true;
  bool _isLoading = false;
  Map<String, dynamic>? _results;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    _startCamera(_isBackCamera ? _cameras!.first : _cameras!.last);
  }

  Future<void> _startCamera(CameraDescription cameraDescription) async {
    _controller = CameraController(cameraDescription, ResolutionPreset.high);
    await _controller!.initialize();
    setState(() => _isCameraInitialized = true);
  }

  Future<void> _toggleCamera() async {
    setState(() => _isBackCamera = !_isBackCamera);
    await _controller?.dispose();
    _startCamera(_isBackCamera ? _cameras!.first : _cameras!.last);
  }

  Future<void> _captureAndSend() async {
    if (!_controller!.value.isInitialized) return;
    setState(() => _isLoading = true);

    try {
      final image = await _controller!.takePicture();
      final file = File(image.path);

      var request = http.MultipartRequest(
        'POST',
        Uri.parse("http://192.168.1.2:5001/capture"), // use your system's IP if testing on device
      );
      request.files.add(await http.MultipartFile.fromPath('image', file.path));

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        setState(() {
          _results = Map<String, dynamic>.from(jsonDecode(responseData.body));
        });
      } else {
        setState(() {
          _results = {"error": "Server error"};
        });
      }
    } catch (e) {
      setState(() {
        _results = {"error": e.toString()};
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isCameraInitialized
          ? Stack(
        children: [
          CameraPreview(_controller!),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              onPressed: _toggleCamera,
              icon: Icon(Icons.cameraswitch, color: Colors.white, size: 32),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  FloatingActionButton(
                    onPressed: _captureAndSend,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.camera, color: Colors.black, size: 30),
                  ),
                const SizedBox(height: 20),
                if (_results != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white.withOpacity(0.8),
                    child: Text(
                      _results.toString(),
                      style: const TextStyle(color: Colors.black, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
        ],
      )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
