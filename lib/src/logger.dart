import 'dart:io';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:intl/intl.dart';

class Logger {
  const Logger._();

  static int leftOfMessagePadding = 85;
  static DateFormat dateFormat = DateFormat("h:mm:ss.SSS a");

  static void _log({required Level level, required String module, required Object? input, StackTrace? trace}) {
    final lines = input.toString().split("\n");

    for (int i = 0; i < lines.length; i++) {
      final x = lines[i];
      final first = "> ${effect([0, 1, level.toColor()])}${level.toId()} ${effect([0, 2])}${dateFormat.format(DateTime.now())}${effect()} ${effect([1])}[${effect([95])}$module${effect([0, 1])}]${effect()}";
      final input = "$x${trace != null ? "${effect([2])}\n$trace\n${effect([0, level.toColor()])}$x" : ""}";
      final spacing = leftOfMessagePadding - first.length;

      stdout.writeln("${effect()}${i == 0 ? first : (" " * first.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '').length)}${" " * max(2, spacing)}> $input${effect()}");
    }
  }

  static String effect([List<int> codes = const [0]]) {
    return '\x1b[${codes.join(";")}m';
  }

  static void log(Level level, String module, Object? input, {StackTrace? trace}) {
    _log(level: level, module: module, input: input);
  }

  static void print(String module, Object? input) {
    _log(level: Level.INFO, module: module, input: input);
  }

  static void warn(String module, Object? input, {StackTrace? trace}) {
    _log(level: Level.WARNING, module: module, input: input, trace: trace);
  }

  static void error(String module, Object? input, {StackTrace? trace}) {
    _log(level: Level.SEVERE, module: module, input: input, trace: trace);
  }
}

extension on Level {
  String toId() {
    return switch (this) {
      Level.CONFIG => "CFG",
      Level.FINE => "LOG",
      Level.FINER => "LOG",
      Level.FINEST => "LOG",
      Level.INFO => "LOG",
      Level.SEVERE => "ERR",
      Level.SHOUT => "ERR",
      Level.WARNING => "WRN",
      Level() => throw UnimplementedError(),
    };
  }

  int toColor() {
    final red = 31;
    final yellow = 33;
    final green = 32;

    return switch (this) {
      Level.CONFIG => green,
      Level.FINE => green,
      Level.FINER => green,
      Level.FINEST => green,
      Level.INFO => green,
      Level.SEVERE => red,
      Level.SHOUT => red,
      Level.WARNING => yellow,
      Level() => throw UnimplementedError(),
    };
  }
}