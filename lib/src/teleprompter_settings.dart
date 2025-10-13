import 'package:flutter/material.dart';

/// Simple immutable data object storing teleprompter display settings.
class TeleprompterSettingsData {
  TeleprompterSettingsData({
    required this.speedSeconds,
    required this.fontName,
    required this.fontSize,
    required this.fontColor,
  });

  final int speedSeconds;
  final String fontName;
  final int fontSize;
  final Color fontColor;

  TeleprompterSettingsData copyWith({
    int? speedSeconds,
    String? fontName,
    int? fontSize,
    Color? fontColor,
  }) {
    return TeleprompterSettingsData(
      speedSeconds: speedSeconds ?? this.speedSeconds,
      fontName: fontName ?? this.fontName,
      fontSize: fontSize ?? this.fontSize,
      fontColor: fontColor ?? this.fontColor,
    );
  }
}

/// Global settings singleton for the teleprompter UI.
///
/// Consumers can listen to `TeleprompterSettings.notifier` to react to
/// changes. Use `TeleprompterSettings.update(...)` to change values.
class TeleprompterSettings {
  // initial defaults - can be adjusted if desired
  static final ValueNotifier<TeleprompterSettingsData> notifier =
      ValueNotifier<TeleprompterSettingsData>(
        TeleprompterSettingsData(
          speedSeconds: 30,
          fontName: 'Quicksand',
          fontSize: 18,
          fontColor: Colors.white,
        ),
      );

  /// Current settings snapshot.
  static TeleprompterSettingsData get value => notifier.value;

  /// Update one or more settings. Only provided fields are changed.
  static void update({
    bool? isOn,
    int? speedSeconds,
    String? fontName,
    int? fontSize,
    Color? fontColor,
  }) {
    notifier.value = notifier.value.copyWith(
      speedSeconds: speedSeconds,
      fontName: fontName,
      fontSize: fontSize,
      fontColor: fontColor,
    );
  }
}
