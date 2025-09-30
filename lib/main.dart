import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Image Manipulation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _image;
  Uint8List? _processedImage;
  final picker = ImagePicker();
  Timer? _debounce;
  bool _isProcessing = false;

  // Change this to your Flask server IP
  final String apiUrl = "http://192.168.1.2:5000/edit";
  final String healthUrl = "http://192.168.1.2:5000/";

  final Map<String, double> adjustments = {
    "brightness": 0,
    "contrast": 0,
    "saturation": 0,
    "exposure": 0,
    "highlights": 0,
    "shadows": 0,
    "vibrance": 0,
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
      final androidInfo = await Future.value(Platform.version);
      if (androidInfo.contains('13') || int.tryParse(androidInfo.split('.').first) != null) {
        await Permission.photos.request();
      } else {
        await Permission.storage.request();
      }
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }
  }

  Future<void> _checkApi() async {
    try {
      final res = await http.get(Uri.parse(healthUrl)).timeout(
        const Duration(seconds: 5),
      );
      if (res.statusCode == 200) {
        showSnack("Server connected successfully!", Colors.green);
      } else {
        showSnack("Server returned: ${res.statusCode}", Colors.orange);
      }
    } catch (e) {
      showSnack("Cannot connect to server. Check your IP address.", Colors.red);
    }
  }

  Future<void> _pickImage() async {
    try {
      await _requestPermissions();

      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _processedImage = null;
        });
        showSnack("Image selected successfully!", Colors.green);
        _applyFilters();
      }
    } catch (e) {
      showSnack("Error selecting image: ${e.toString()}", Colors.red);
    }
  }

  Future<void> _applyFilters() async {
    if (_image == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      var request = http.MultipartRequest("POST", Uri.parse(apiUrl));
      request.files.add(
        await http.MultipartFile.fromPath("image", _image!.path),
      );

      adjustments.forEach((key, value) {
        request.fields[key] = value.toString();
      });

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      if (streamedResponse.statusCode == 200) {
        final bytes = await streamedResponse.stream.toBytes();
        if (mounted) {
          setState(() {
            _processedImage = bytes;
            _isProcessing = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        showSnack("Server error: ${streamedResponse.statusCode}", Colors.red);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      showSnack("Failed to process image: ${e.toString()}", Colors.red);
    }
  }

  Future<void> _saveImage() async {
    if (_processedImage == null) {
      showSnack("No edited image to save", Colors.orange);
      return;
    }

    try {
      await _requestPermissions();

      final result = await ImageGallerySaver.saveImage(
        _processedImage!,
        quality: 100,
        name: "edited_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (result != null && result['isSuccess'] == true) {
        showSnack("Image saved to gallery successfully!", Colors.green);
      } else {
        showSnack("Failed to save image", Colors.red);
      }
    } catch (e) {
      showSnack("Error saving image: ${e.toString()}", Colors.red);
    }
  }

  void _onSliderChange(String key, double value) {
    setState(() {
      adjustments[key] = value;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _applyFilters();
    });
  }

  Widget buildSlider(
      String label,
      String key, {
        double min = -100,
        double max = 100,
        int? divisions,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ${adjustments[key]!.toStringAsFixed(1)}",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Slider(
            value: adjustments[key]!,
            min: min,
            max: max,
            divisions: divisions ?? 200,
            label: adjustments[key]!.toStringAsFixed(1),
            onChanged: _image == null
                ? null
                : (val) => _onSliderChange(key, val),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Image Editor"),
        elevation: 2,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _checkApi,
                  icon: const Icon(Icons.wifi, size: 18),
                  label: const Text("Check API"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text("Pick Image"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _processedImage == null ? null : _saveImage,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text("Save"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 250,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: _processedImage != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _processedImage!,
                fit: BoxFit.contain,
              ),
            )
                : _image != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _image!,
                fit: BoxFit.contain,
              ),
            )
                : const Center(
              child: Text(
                "No image selected",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text(
                      "Main Adjustments",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      buildSlider("Brightness", "brightness"),
                      buildSlider("Contrast", "contrast"),
                      buildSlider("Saturation", "saturation"),
                      buildSlider("Exposure", "exposure"),
                      buildSlider("Highlights", "highlights"),
                      buildSlider("Shadows", "shadows"),
                      buildSlider("Vibrance", "vibrance"),
                      buildSlider("Temperature", "temperature"),
                      buildSlider("Hue", "hue"),
                      buildSlider("Fading", "fading"),
                      buildSlider("Enhance", "enhance"),
                      buildSlider("Smoothness", "smoothness"),
                      buildSlider("Ambiance", "ambiance"),
                      buildSlider("Noise", "noise"),
                      buildSlider("Color Noise", "color_noise"),
                      buildSlider("Inner Spotlight", "inner_spotlight"),
                      buildSlider("Outer Spotlight", "outer_spotlight"),
                      buildSlider("Tint", "tint", min: -100, max: 100),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text(
                      "Effects",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      buildSlider("Texture", "texture"),
                      buildSlider("Clarity", "clarity"),
                      buildSlider("Dehaze", "dehaze"),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text(
                      "Grain",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      buildSlider("Amount", "grain_amount"),
                      buildSlider("Size", "grain_size", min: 1, max: 10, divisions: 9),
                      buildSlider("Roughness", "grain_roughness", min: 1, max: 10, divisions: 9),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text(
                      "Sharpening",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      buildSlider("Amount", "sharpen_amount"),
                      buildSlider("Radius", "sharpen_radius", min: 1, max: 10, divisions: 9),
                      buildSlider("Detail", "sharpen_detail", min: 1, max: 10, divisions: 9),
                      buildSlider("Masking", "sharpen_masking", min: 0, max: 255, divisions: 255),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text(
                      "Vignette",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      buildSlider("Amount", "vignette_amount"),
                      buildSlider("Midpoint", "vignette_midpoint", min: 0, max: 100),
                      buildSlider("Feather", "vignette_feather", min: 0, max: 100),
                      buildSlider("Roundness", "vignette_roundness", min: -100, max: 100),
                      buildSlider("Highlights", "vignette_highlights", min: 0, max: 100),
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