import 'dart:convert';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';

const logbotPort = 4040;

Future<void> connectLogbot() async {
  Logger.addOnLogCallback((log) async {
    try {
      final socket = await Socket.connect('127.0.0.1', 4040);
      socket.writeln(jsonEncode(log.toJson()));
    } catch (e) {
      if (!dev) Logger.warn("Logbot", "Error connecting to socket on port $logbotPort: $e");
    }
  });

  Logger.print("Logbot", "Logbot set up on port $logbotPort");
}