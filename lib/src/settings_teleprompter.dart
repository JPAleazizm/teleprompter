import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' show ColorPicker;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'teleprompter_settings.dart';

/// Widget that exposes teleprompter display options.
///
/// This is shown as a bottom sheet from the main recorder UI and allows the
/// user to change speed, font, font size and font color. Changes are applied
/// to `TeleprompterSettings` which is a global `ValueNotifier` used by the
/// recorder.
class SettingsTeleprompterWidget extends StatefulWidget {
  const SettingsTeleprompterWidget({super.key});

  @override
  State<SettingsTeleprompterWidget> createState() =>
      _SettingsTeleprompterWidgetState();
}

class _SettingsTeleprompterWidgetState
    extends State<SettingsTeleprompterWidget> {
  final selectedFont = ValueNotifier<String>('Roboto');
  final selectedSpeed = ValueNotifier<String>('Lenta');
  final selectedFontSize = ValueNotifier<int>(18);
  final selectedFontColor = ValueNotifier<Color>(Colors.white);
  final isOn = ValueNotifier<bool>(true);
  final List<String> speeds = ['Lenta', 'Média', 'Rápida'];
  final List<String> fonts = [
    'Quicksand',
    'Roboto',
    'Open Sans',
    'DM Sans',
    'Lato',
    'Montserrat',
    'Poppins',
    'Inter',
    'Nunito',
    'Raleway',
    'Ubuntu',
    'Noto Sans',
    'Source Sans Pro',
    'Merriweather',
    'Playfair Display',
  ];

  final List<int> fontsSize = [10, 12, 14, 16, 18, 20];

  String _speedLabelFromSeconds(int seconds) {
    if (seconds >= 60) return 'Lenta';
    if (seconds >= 30) return 'Média';
    return 'Rápida';
  }

  void _onExternalSettingsChanged() {
    final s = TeleprompterSettings.value;
    // avoid redundant updates
    if (selectedFont.value != s.fontName && fonts.contains(s.fontName)) {
      selectedFont.value = s.fontName;
    }
    if (selectedFontSize.value != s.fontSize &&
        fontsSize.contains(s.fontSize)) {
      selectedFontSize.value = s.fontSize;
    }
    if (selectedFontColor.value != s.fontColor) {
      selectedFontColor.value = s.fontColor;
    }
    final label = _speedLabelFromSeconds(s.speedSeconds);
    if (selectedSpeed.value != label) selectedSpeed.value = label;
  }

  @override
  void initState() {
    super.initState();
    final s = TeleprompterSettings.value;
    selectedFont.value = fonts.contains(s.fontName) ? s.fontName : fonts.first;
    selectedFontSize.value = fontsSize.contains(s.fontSize)
        ? s.fontSize
        : fontsSize.first;
    selectedFontColor.value = s.fontColor;

    selectedSpeed.value = _speedLabelFromSeconds(s.speedSeconds);

    TeleprompterSettings.notifier.addListener(_onExternalSettingsChanged);
  }

  String colorToHex(Color color) {
    final a = ((color.a * 255.0).round() & 0xff);
    final r = ((color.r * 255.0).round() & 0xff);
    final g = ((color.g * 255.0).round() & 0xff);
    final b = ((color.b * 255.0).round() & 0xff);

    String toHex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

    return a == 0xFF
        ? '#${toHex(r)}${toHex(g)}${toHex(b)}'
        : '#${toHex(a)}${toHex(r)}${toHex(g)}${toHex(b)}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SizedBox(
          height: size.height,
          width: size.width,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: EdgeInsets.only(top: size.height * 0.05),
                child: Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: size.width * 0.18,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();

                          Navigator.pop(context);
                          FocusScope.of(context).unfocus();
                        },
                        child: Text(
                          'Voltar',
                          style: GoogleFonts.quicksand(
                            color: Colors.blue,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'Teleprompter',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  'Velocidade',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: selectedSpeed,
                builder: (_, value, _) {
                  return DropdownButtonFormField<String>(
                    initialValue: selectedSpeed.value,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                    ),
                    hint: Text(
                      'Selecione a velocidade',
                      style: GoogleFonts.quicksand(),
                    ),
                    items: speeds
                        .map(
                          (speed) => DropdownMenuItem(
                            value: speed,
                            child: Text(speed, style: GoogleFonts.quicksand()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      HapticFeedback.selectionClick();

                      selectedSpeed.value = value ?? '';
                      // map speed string to seconds
                      final seconds = value == 'Lenta'
                          ? 60
                          : value == 'Média'
                          ? 30
                          : 15;
                      TeleprompterSettings.update(speedSeconds: seconds);
                    },
                  );
                },
              ),

              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  'Fonte',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: selectedFont,
                builder: (_, value, _) {
                  return DropdownButtonFormField<String>(
                    initialValue: value,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                    ),
                    hint: Text(
                      'Selecione a fonte',
                      style: GoogleFonts.quicksand(),
                    ),
                    items: fonts
                        .map(
                          (font) => DropdownMenuItem(
                            value: font,
                            child: Text(font, style: GoogleFonts.quicksand()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      HapticFeedback.selectionClick();

                      selectedFont.value = value ?? '';
                      TeleprompterSettings.update(fontName: value);
                    },
                  );
                },
              ),

              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  'Tamanho Fonte',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: selectedFontSize,
                builder: (_, value, _) {
                  return DropdownButtonFormField<int>(
                    initialValue: selectedFontSize.value,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                    ),
                    hint: Text(
                      'Selecione a fonte',
                      style: GoogleFonts.quicksand(),
                    ),
                    items: fontsSize
                        .map(
                          (fontSize) => DropdownMenuItem(
                            value: fontSize,
                            child: Text(
                              fontSize.toString(),
                              style: GoogleFonts.quicksand(),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        HapticFeedback.selectionClick();

                        selectedFontSize.value = value;
                        TeleprompterSettings.update(fontSize: value);
                      }
                    },
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Cor da Fonte',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();

                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => SizedBox(
                      height: size.height * 0.7,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 50),
                        child: ColorPicker(
                          pickerColor: selectedFontColor.value,
                          onColorChanged: (Color value) {
                            selectedFontColor.value = value;
                            TeleprompterSettings.update(fontColor: value);
                          },
                        ),
                      ),
                    ),
                  );
                },
                child: ValueListenableBuilder(
                  valueListenable: selectedFontColor,
                  builder: (_, value, _) {
                    return Container(
                      height: 100,
                      width: 100,
                      decoration: BoxDecoration(
                        color: value,
                        shape: BoxShape.circle,
                        border: Border.all(width: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    TeleprompterSettings.notifier.removeListener(_onExternalSettingsChanged);
    selectedFont.dispose();
    selectedSpeed.dispose();
    isOn.dispose();
    selectedFontSize.dispose();
    selectedFontColor.dispose();
    super.dispose();
  }
}
