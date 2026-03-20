import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:calebh101_discord/calebh101_discord.dart' as c;

void loggerOverride() {
  Logger.root.onRecord.listen((record) {
    final section = "Nyxx.${record.loggerName}";
    if (record.error is CommandNotFoundException) return;

    if (record.level == Level.WARNING) {
      c.Logger.warn(section, record.message, trace: record.stackTrace);
    } else if (record.level == Level.SEVERE || record.level == Level.SHOUT) {
      c.Logger.error(section, record.message, trace: record.stackTrace);
    } else {
      c.Logger.print(section, record.message);
    }
  });
}