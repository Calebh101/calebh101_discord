import 'dart:io';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:intl/intl.dart';

enum LogLevel {
  config,
  info,
  warning,
  error,
  shout,
  signal,
}

class Logger {
  const Logger._();

  static int leftOfMessagePadding = 50;
  static DateFormat dateFormat = DateFormat("h:mm:ss.SSS a");

  static void _log({required LogLevel level, required String module, required Object? input, StackTrace? trace}) {
    final lines = input.toString().split("\n");

    for (int i = 0; i < lines.length; i++) {
      final x = lines[i];
      final first = "> ${effect([0, 1, ?level.toColor()])}${level.toId()} ${effect([0, 2])}${dateFormat.format(DateTime.now())}${effect()} ${effect([1])}[${effect([95])}$module${effect([0, 1])}]${effect()}";
      final input = "$x${trace != null ? "${effect([2])}\n$trace\n${effect([0, ?level.toColor()])}$x" : ""}";
      final spacing = leftOfMessagePadding - first.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '').length;

      stdout.writeln("${effect()}${i == 0 ? first : (" " * first.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '').length)}${" " * max(2, spacing)}> $input${effect()}");
    }

    if (level == LogLevel.signal) {
      _log(level: LogLevel.warning, module: "Logger", input: "Signals are deprecated and will not function correctly. Please use exit codes.");
    }
  }

  static String effect([List<int> codes = const [0]]) {
    return '\x1b[${codes.join(";")}m';
  }

  static void log(Level level, String module, Object? input, {StackTrace? trace}) {
    _log(level: level.toLogLevel(), module: module, input: input);
  }

  static void print(String module, Object? input) {
    _log(level: LogLevel.info, module: module, input: input);
  }

  static void warn(String module, Object? input, {StackTrace? trace}) {
    _log(level: LogLevel.warning, module: module, input: input, trace: trace);
  }

  static void error(String module, Object? input, {StackTrace? trace}) {
    _log(level: LogLevel.error, module: module, input: input, trace: trace);
  }

  static void signal(String module, String signal) {
    _log(level: LogLevel.signal, module: module, input: signal);
  }
}

extension on LogLevel {
  String toId() {
    return switch (this) {
      LogLevel.config => "LOG",
      LogLevel.info => "LOG",
      LogLevel.warning => "WRN",
      LogLevel.error => "ERR",
      LogLevel.shout => "ERR",
      LogLevel.signal => "SIG",
    };
  }

  int? toColor() {
    final red = 31;
    final yellow = 33;
    final green = 32;

    return switch (this) {
      LogLevel.config => green,
      LogLevel.info => green,
      LogLevel.error => red,
      LogLevel.shout => red,
      LogLevel.warning => yellow,
      LogLevel.signal => null,
    };
  }
}

extension on Level {
  LogLevel toLogLevel() {
    return switch (this) {
      Level.CONFIG => LogLevel.config,
      Level.FINE => LogLevel.info,
      Level.FINER => LogLevel.info,
      Level.FINEST => LogLevel.info,
      Level.INFO => LogLevel.info,
      Level.SEVERE => LogLevel.error,
      Level.SHOUT => LogLevel.shout,
      Level.WARNING => LogLevel.warning,
      Level() => throw UnimplementedError(),
    };
  }
}