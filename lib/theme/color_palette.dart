import 'package:flutter/material.dart';

/// Represents a color palette for the app, allowing for different
/// themes (e.g., Bragmat, TEBS seasons) without hard-coding colors.
class ColorPalette {
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color surface;
  final Color background;
  final Color white;
  final Color mutedTeal;
  final Color mutedGrey;

  const ColorPalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.surface,
    required this.background,
    required this.white,
    required this.mutedTeal,
    required this.mutedGrey,
  });

  /// The default Bragmat color palette
  static const ColorPalette bragmat = ColorPalette(
    primary: Color(0xFF183800), // Primary Green
    secondary: Color(0xFF439779), // Teal
    tertiary: Color(0xFFdfb10a), // Gold Accent
    surface: Color(0xFFcde6e4), // Light Background
    background: Color(0xFFcde6e4), // Light Background
    white: Color(0xFFffffff), // White
    mutedTeal: Color(0xFF5A7A6A), // Muted Teal
    mutedGrey: Color(0xFF9E9E9E), // Muted Grey
  );

  /// A TEBS competition palette (example - can be customized per season)
  static const ColorPalette tebs = ColorPalette(
    primary: Color(0xFF183800), // Primary Green (same as Bragmat)
    secondary: Color(0xFF439779), // Teal (same as Bragmat)
    tertiary: Color(0xFFdfb10a), // Gold Accent (same as Bragmat)
    surface: Color(0xFFcde6e4), // Light Background (same as Bragmat)
    background: Color(0xFFcde6e4), // Light Background (same as Bragmat)
    white: Color(0xFFffffff), // White (same as Bragmat)
    mutedTeal: Color(0xFF5A7A6A), // Muted Teal (same as Bragmat)
    mutedGrey: Color(0xFF9E9E9E), // Muted Grey (same as Bragmat)
  );

  /// Create a custom palette for a specific competition season
  factory ColorPalette.custom({
    required Color primary,
    required Color secondary,
    required Color tertiary,
    Color? surface,
    Color? background,
    Color? white,
    Color? mutedTeal,
    Color? mutedGrey,
  }) {
    return ColorPalette(
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: surface ?? const Color(0xFFcde6e4),
      background: background ?? const Color(0xFFcde6e4),
      white: white ?? const Color(0xFFffffff),
      mutedTeal: mutedTeal ?? const Color(0xFF5A7A6A),
      mutedGrey: mutedGrey ?? const Color(0xFF9E9E9E),
    );
  }

  /// Copy with method for creating variations
  ColorPalette copyWith({
    Color? primary,
    Color? secondary,
    Color? tertiary,
    Color? surface,
    Color? background,
    Color? white,
    Color? mutedTeal,
    Color? mutedGrey,
  }) {
    return ColorPalette(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      surface: surface ?? this.surface,
      background: background ?? this.background,
      white: white ?? this.white,
      mutedTeal: mutedTeal ?? this.mutedTeal,
      mutedGrey: mutedGrey ?? this.mutedGrey,
    );
  }
}
