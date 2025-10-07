import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Image Editor',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
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
  Uint8List? _beforeEnhanceImage;
  Uint8List? _afterEnhanceImage;
  final picker = ImagePicker();
  Timer? _debounce;
  bool _isProcessing = false;
  int _selectedTab = 0;

  final String apiUrl = "http://192.168.157.4:5000/edit";
  final String blurUrl = "http://192.168.157.4:5000/blur";
  final String enhanceUrl = "http://192.168.157.4:5000/enhance";
  final String healthUrl = "http://192.168.157.4:5000/";

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

  // Blur parameters
  String _blurType = 'linear';
  double _blurStrength = 51;
  double _stripPosition = 0.5;
  double _stripWidth = 0.3;
  double _radiusRatio = 0.3;
  double _widthRatio = 0.45;
  double _heightRatio = 0.25;
  double _feather = 51;
  String _focusRegion = 'center';

  // Gesture tracking
  Offset? _gestureStart;
  Offset? _gestureEnd;
  Size? _imageSize;

  // Hand blur tracking
  Offset? _handCenter;
  double _handRadius = 50;


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
      final res = await http.get(Uri.parse(healthUrl)).timeout(const Duration(seconds: 5));
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
    try {
      await _requestPermissions();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _processedImage = null;
          _beforeEnhanceImage = null;
          _afterEnhanceImage = null;
        });
        showSnack("✓ Image selected successfully!", Colors.green);
      }
    } catch (e) {
      showSnack("Error selecting image: ${e.toString()}", Colors.red);
    }
  }

  Future<void> _applyFilters() async {
    if (_image == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      var request = http.MultipartRequest("POST", Uri.parse(apiUrl));
      request.files.add(await http.MultipartFile.fromPath("image", _image!.path));

      // Only send adjustments, no blur_strength here
      adjustments.forEach((key, value) {
        request.fields[key] = value.toString();
      });

      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      if (streamedResponse.statusCode == 200) {
        final bytes = await streamedResponse.stream.toBytes();
        if (mounted) {
          setState(() {
            _processedImage = bytes;
            _isProcessing = false;
          });
        }
      } else {
        setState(() => _isProcessing = false);
        showSnack("Server error: ${streamedResponse.statusCode}", Colors.red);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      showSnack("Failed to process image: ${e.toString()}", Colors.red);
    }
  }

  Future<void> _applyBlur() async {
    if (_image == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      var request = http.MultipartRequest("POST", Uri.parse(blurUrl));
      request.files.add(await http.MultipartFile.fromPath("image", _image!.path));

      // Hand blur specific fields
      if (_blurType == 'hand' && _handCenter != null) {
        request.fields['hand_x'] = _handCenter!.dx.toInt().toString();
        request.fields['hand_y'] = _handCenter!.dy.toInt().toString();
        request.fields['hand_radius'] = _handRadius.toInt().toString();
        request.fields['hand_feather'] = _feather.toInt().toString();
      }

      // Common blur fields
      request.fields['blur_type'] = _blurType;
      request.fields['blur_strength'] = _blurStrength.toInt().toString(); // fixed name
      request.fields['strip_position'] = _stripPosition.toString();
      request.fields['strip_width'] = _stripWidth.toString();
      request.fields['radius_ratio'] = _radiusRatio.toString();
      request.fields['width_ratio'] = _widthRatio.toString();
      request.fields['height_ratio'] = _heightRatio.toString();
      request.fields['feather'] = _feather.toInt().toString();
      request.fields['focus_region'] = _focusRegion;

      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      if (streamedResponse.statusCode == 200) {
        final bytes = await streamedResponse.stream.toBytes();
        if (mounted) {
          setState(() {
            _processedImage = bytes;
            _isProcessing = false;
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

  void _handleGesture(Offset start, Offset end, Size imageSize) {
    double dx = (end.dx - start.dx).abs();
    double dy = (end.dy - start.dy).abs();
    double centerX = (start.dx + end.dx) / 2;
    double centerY = (start.dy + end.dy) / 2;

    switch (_blurType) {
      case 'linear':
        if (dx > dy) {
          _stripPosition = (centerX / imageSize.width).clamp(0.0, 1.0);
          _stripWidth = (dx / imageSize.width).clamp(0.1, 0.8);
        } else {
          _stripPosition = (centerY / imageSize.height).clamp(0.0, 1.0);
          _stripWidth = (dy / imageSize.height).clamp(0.1, 0.8);
        }
        break;

      case 'hand':
        double centerX = (start.dx + end.dx) / 2;
        double centerY = (start.dy + end.dy) / 2;
        double radius = ((end - start).distance / 2).clamp(10.0, 300.0); // radius in pixels

        // Store values for _applyBlur
        _handCenter = Offset(centerX, centerY);
        _handRadius = radius;
        break;

      case 'circular':
        _radiusRatio = ((dx + dy) / 2 / (imageSize.width / 2)).clamp(0.1, 0.8);
        break;
      case 'oval':
        _widthRatio = (dx / imageSize.width).clamp(0.1, 0.9);
        _heightRatio = (dy / imageSize.height).clamp(0.1, 0.9);
        break;
      case 'radial':
        _radiusRatio = ((dx + dy) / 2 / (imageSize.width / 2)).clamp(0.1, 0.6);
        break;
      case 'focus':
        double relX = centerX / imageSize.width;
        double relY = centerY / imageSize.height;
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
                      Text("• Enhanced clarity and sharpness"),
                      Text("• Improved texture details"),
                      Text("• Optimized for 4MB+ file size"),
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

  Widget buildSlider(String label, String key, {double min = -100, double max = 100}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label: ${adjustments[key]!.toStringAsFixed(1)}",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          Slider(
            value: adjustments[key]!,
            min: min,
            max: max,
            divisions: 100,
            onChanged: (val) {
              setState(() => adjustments[key] = val);
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _applyFilters);
            },
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
          buildSlider("Brightness", "brightness"),
          buildSlider("Contrast", "contrast"),
          buildSlider("Saturation", "saturation"),
          buildSlider("Exposure", "exposure"),
          buildSlider("Highlights", "highlights"),
          buildSlider("Shadows", "shadows"),
          buildSlider("Vibrance", "vibrance"),
          buildSlider("Temperature", "temperature"),
          buildSlider("Hue", "hue"),
          buildSlider("Tint", "tint"),
          buildSlider("Fading", "fading"),
          buildSlider("Enhance", "enhance"),
          buildSlider("Smoothness", "smoothness"),
          buildSlider("Ambiance", "ambiance"),
          buildSlider("Inner Spotlight", "inner_spotlight"),
          buildSlider("Outer Spotlight", "outer_spotlight"),
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

  Widget _buildBlurTab() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text("Blur Effects", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Wrap(
          spacing: 8,
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
          ],
        ),
        ChoiceChip(
          label: const Text("Hand"),
          selected: _blurType == 'hand',
          onSelected: (selected) {
            setState(() => _blurType = 'hand');
            _applyBlur();
          },
        ),

        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Text("Blur Strength: ${_blurStrength.toInt()}"),
              Slider(
                value: _blurStrength,
                min: 1,
                max: 101,
                divisions: 50,
                onChanged: (val) {
                  if (val % 2 == 0) val += 1;
                  setState(() => _blurStrength = val);
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), _applyBlur);
                },
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            "Draw on the image to adjust blur area",
            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          ),
        ),
      ],
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
            onPressed: () {
              showSnack("Save functionality coming soon!", Colors.blue);
            },
            icon: const Icon(Icons.save),
            tooltip: "Save (Not Implemented)",
          ),
        ],
      ),
      body: Column(
        children: [
          // Three main buttons
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
          // Image display with gesture handling
          if (_image != null)
            Expanded(
              flex: 2,
              child: GestureDetector(
                onPanStart: _selectedTab == 2 ? (details) => _gestureStart = details.localPosition : null,
                onPanUpdate: _selectedTab == 2 ? (details) => _gestureEnd = details.localPosition : null,
                onPanEnd: _selectedTab == 2
                    ? (details) {
                  if (_gestureStart != null && _gestureEnd != null && _imageSize != null) {
                    _handleGesture(_gestureStart!, _gestureEnd!, _imageSize!);
                  }
                  _gestureStart = null;
                  _gestureEnd = null;
                }
                    : null,
                child: LayoutBuilder(builder: (ctx, constraints) {
                  _imageSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return _processedImage != null
                      ? Image.memory(_processedImage!, fit: BoxFit.contain)
                      : Image.file(_image!, fit: BoxFit.contain);
                }),
              ),
            ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          // Controls area
          Expanded(
            flex: 3,
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
