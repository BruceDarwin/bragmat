import 'dart:io';
import 'package:flutter/material.dart';
import '../services/media_storage_service.dart';

/// A widget that displays an image from a file path.
/// 
/// Automatically resolves relative paths through MediaStorageService
/// and maintains compatibility with absolute paths.
/// Handles missing files gracefully with error display.
class ResolvedImage extends StatelessWidget {
  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const ResolvedImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: MediaStorageService.resolvePath(imagePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder ?? const SizedBox.shrink();
        }
        
        if (snapshot.hasError || !snapshot.hasData) {
          return errorWidget ??
              Container(
                width: width,
                height: height,
                color: Colors.grey[300],
                child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              );
        }
        
        final resolvedPath = snapshot.data!;
        
        return Image.file(
          File(resolvedPath),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return errorWidget ??
                Container(
                  width: width,
                  height: height,
                  color: Colors.grey[300],
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                );
          },
        );
      },
    );
  }
}
