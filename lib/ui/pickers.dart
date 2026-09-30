import 'package:flutter/material.dart';

/// Seletor de hora em 24 h. Devolve minutos desde a meia-noite.
Future<int?> pickMinute(
  BuildContext context, {
  required int initial,
  String? help,
}) async {
  final t = await showTimePicker(
    context: context,
    helpText: help,
    initialTime: TimeOfDay(hour: (initial ~/ 60) % 24, minute: initial % 60),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  return t == null ? null : t.hour * 60 + t.minute;
}
