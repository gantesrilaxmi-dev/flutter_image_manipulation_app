import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';

void main() => runApp(MyApp());

// -------------------------
// MyApp: Entry Point
// -------------------------
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image API Client',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ImageScreen(apiType: 'edit'),
    );
  }
}

// -------------------------
// ImageScreen: Main Logic
// -------------------------
class ImageScreen extends StatefulWidget {
  final String apiType;
  ImageScreen({required this.apiType});

  @override
  _ImageScreenState createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  File? _image;
  Uint8List? _processedImage;
  final picker = ImagePicker();
  Map<String, double> sliders = {};
  Timer? _debounce;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    if (widget.apiType == 'edit') {
      // 18 sliders for image manipulation (removed edge_detection)
      List<String> keys = [
        "brightness","contrast","saturation","fading","exposure","highlights",
        "shadows","vibrance","temperature","hue","sharpness","vignette","enhance",
        "dehaze","ambiance","noise","colorNoise","innerSpotlight","outerSpotlight"
      ];
      for (var k in keys) sliders[k] = 0.0;
    }
  }

  // -------------------------
  // Pick Image
  // -------------------------
  Future<void> pickImage() async {
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _processedImage = null;
        });
        postToApi();
      }
    } catch (e) {
      showSnack("Error picking image: $e", Colors.red);
    }
  }

  // -------------------------
  // Show SnackBar
  // -------------------------
  void showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: Duration(seconds: 2)),
    );
  }

  // -------------------------
  // Reset Image
  // -------------------------
  void resetImage() {
    setState(() {
      _processedImage = null;
      sliders.updateAll((key, value) => 0.0);
    });
  }

  // -------------------------
  // POST API Call (for image manipulation)
  // -------------------------
  Future<void> postToApi() async {
    if (_image == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    String url = "http://192.168.253.4:5000/edit";

    try {
      Uri uri = Uri.parse(url);
      var request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('image', _image!.path));
      sliders.forEach((key, val) => request.fields[key] = val.toString());
      var response = await request.send().timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        var bytes = await response.stream.toBytes();
        setState(() {
          _processedImage = bytes;
          _isProcessing = false;
        });
        showSnack("Image processed successfully!", Colors.green);
      } else {
        setState(() => _isProcessing = false);
        showSnack("Server Error: ${response.statusCode}", Colors.orange);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      showSnack("Connection Error: $e", Colors.red);
    }
  }

  // -------------------------
  // GET API Call
  // -------------------------
  Future<void> getFromApi() async {
    String url = "http://192.168.253.4:5000/edit";
    try {
      var response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));
      showSnack(response.statusCode == 200
          ? "Server reachable!"
          : "Server error: ${response.statusCode}", response.statusCode == 200 ? Colors.green : Colors.orange);
    } catch (e) {
      showSnack("Cannot connect: $e", Colors.red);
    }
  }

  // -------------------------
  // Save Image
  // -------------------------
  Future<void> saveImage() async {
    if (_processedImage == null) {
      showSnack("No processed image to save", Colors.red);
      return;
    }
    try {
      await ImageGallerySaver.saveImage(_processedImage!);
      showSnack("Image saved to gallery!", Colors.green);
    } catch (e) {
      showSnack("Error saving image: $e", Colors.red);
    }
  }

  // -------------------------
  // Slider Change
  // -------------------------
  void onSliderChange(String key, double val) {
    setState(() => sliders[key] = val);
    if (_image != null) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(Duration(milliseconds: 500), () {
        postToApi();
      });
    }
  }

  // -------------------------
  // UI Widgets
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Image Manipulation"),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          SizedBox(height: 10),
          // Image display
          Container(
            height: 300,
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
            child: Stack(
              children: [
                Center(
                  child: _processedImage != null
                      ? Image.memory(_processedImage!, fit: BoxFit.contain, height: 290)
                      : _image != null
                      ? Image.file(_image!, fit: BoxFit.contain, height: 290)
                      : Text("No Image Selected", style: TextStyle(color: Colors.grey[600])),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          SizedBox(height: 10),
          // Buttons
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(child: ElevatedButton(onPressed: pickImage, child: Text("Pick Image"))),
                SizedBox(width: 10),
                Expanded(child: ElevatedButton(onPressed: getFromApi, child: Text("Get API"))),
                SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton(onPressed: _processedImage != null ? saveImage : null, child: Text("Save"))),
              ],
            ),
          ),
          SizedBox(height: 10),
          // Sliders
          Expanded(child: buildSliders()),
        ],
      ),
    );
  }

  Widget buildSliders() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 10),
      itemCount: sliders.length,
      itemBuilder: (context, index) {
        String key = sliders.keys.elementAt(index);
        double value = sliders[key]!;

        return Card(
          margin: EdgeInsets.symmetric(vertical: 3),
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
                        .split(' ')
                        .map((w) => w[0].toUpperCase() + w.substring(1))
                        .join(' '),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(value.toInt().toString(),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                ]),
                Slider(
                  value: value,
                  min: -100,
                  max: 100,
                  divisions: 200,
                  onChanged: (val) => onSliderChange(key, val),
                  activeColor: Colors.blue,
                  inactiveColor: Colors.grey[300],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}



