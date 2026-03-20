import 'package:calebh101_discord/calebh101_discord.dart';

void main(List<String> arguments) async {
  final bot = await load(settings: BotSettings(), permissions: []);
  if (bot == null) return;
  Logger.print("main", "Bot loaded! ID: ${bot.bot.id}");
}
