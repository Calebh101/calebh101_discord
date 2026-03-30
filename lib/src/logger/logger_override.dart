import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:calebh101_discord/calebh101_discord.dart' as c;

/// Listen for logs in Nyxx's Logger class, and use our own logger to print them.
void loggerOverride() {
  Logger.root.onRecord.listen((record) {
    if (record.error is CommandNotFoundException) return;
    c.Logger.log(record.level, record.loggerName, record.message);
  });
}