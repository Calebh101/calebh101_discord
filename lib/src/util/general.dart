import 'package:calebh101_discord/calebh101_discord.dart';

List<T> flatten<T>(List<List<T>> lists) => lists.expand((e) => e).toList();

Future<String> Function(MessageCreateEvent) prefixFromServerSettings(ServerSettings? Function(PartialGuild guild) getSettings) => (MessageCreateEvent event) async {
  if (event.guild == null) return defaultPrefix;
  final settings = getSettings.call(event.guild!);
  if (settings == null) return defaultPrefix;

  final prefix = settings.prefix.get() ?? defaultPrefix;
  return prefix;
};