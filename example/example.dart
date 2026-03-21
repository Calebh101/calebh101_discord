import 'package:calebh101_discord/calebh101_discord.dart';

void main(List<String> arguments) async {
  final a = await load(settings: BotSettings(), permissions: [...GatewayIntents.allUnprivileged, GatewayIntents.messageContent], prefix: mentionOr((_) => "!"));
  if (a == null) return;
  Logger.print("main", "Bot loaded! ID: ${a.bot?.id}");
}
