import 'package:flutter/material.dart';
import '../theme/color_palette.dart';

/// Service for managing the app's color palette.
/// Allows switching between different palettes (e.g., Bragmat, TEBS seasons)
/// without restarting the app or hard-coding colors.
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  ColorPalette _currentPalette = ColorPalette.bragmat;

  /// Get the current color palette
  ColorPalette get currentPalette => _currentPalette;

  /// Set a new color palette and notify listeners
  void setPalette(ColorPalette palette) {
    if (_currentPalette != palette) {
      _currentPalette = palette;
      notifyListeners();
    }
  }

  /// Reset to the default Bragmat palette
  void resetToBragmat() {
    setPalette(ColorPalette.bragmat);
  }

  /// Switch to TEBS palette
  void setTEBSPalette() {
    setPalette(ColorPalette.tebs);
  }

  /// Create a custom palette for a specific competition season
  void setCustomPalette({
    required Color primary,
    required Color secondary,
    required Color tertiary,
    Color? surface,
    Color? background,
    Color? white,
    Color? mutedTeal,
    Color? mutedGrey,
  }) {
    setPalette(ColorPalette.custom(
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: surface,
      background: background,
      white: white,
      mutedTeal: mutedTeal,
      mutedGrey: mutedGrey,
    ));
  }
}
