import 'dart:io';
import 'package:flutter/material.dart';
import '../services/media_storage_service.dart';

class PhotoViewerScreen extends StatelessWidget {
  final String imagePath;

  const PhotoViewerScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: MediaStorageService.resolvePath(imagePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }
        
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(''),
            ),
            body: const Center(
              child: Text(
                'Error loading photo',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        
        final resolvedPath = snapshot.data!;
        
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(''),
            automaticallyImplyLeading: true,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(resolvedPath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      'Photo not found',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
