import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullScreenImage extends StatefulWidget {
  final String imageUrl;

  const FullScreenImage({super.key, required this.imageUrl});

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<FullScreenImage> {
  bool _isFullScreen = false;

  @override
  void dispose() {
    // CRITICAL: Return to normal app mode when the user presses back
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); 
    super.dispose();
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });

    if (_isFullScreen) {
      // Enter true media mode: hides bars without resizing the Flutter window
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // Return to normal mode
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      
      // These two lines prevent the "jump" when system bars appear
      extendBodyBehindAppBar: true, 
      extendBody: true,             
      
      // Hide the AppBar completely if we are in full screen mode
      appBar: _isFullScreen 
          ? null 
          : AppBar(
              backgroundColor: Colors.black.withOpacity(0.4), 
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            
      // Wrap the screen in a GestureDetector to listen for taps
      body: GestureDetector(
        onTap: _toggleFullScreen,
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.network(
              widget.imageUrl,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain, // Keeps it from cropping while stretching
            ),
          ),
        ),
      ),
    );
  }
}