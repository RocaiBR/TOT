import 'package:flutter/material.dart';

/// Notifier global de tema — importe este arquivo em qualquer widget
/// que precise ler ou alterar o tema do app.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
