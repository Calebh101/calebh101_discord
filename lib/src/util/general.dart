import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

Future<DiscordColor> getColor([Member? member]) async {
  return await getPrimaryColor(member) ?? primaryBotColor;
}

extension Flatten<T> on Iterable<Iterable<T>> {
  Iterable<T> flatten() => expand((e) => e);
}

extension ToFuture<T> on FutureOr<T> {
  Future<T> toFuture() async {
    return this;
  }
}

Future<String> Function(MessageCreateEvent) prefixFromServerSettings(ServerSettings? Function(PartialGuild guild) getSettings) => (MessageCreateEvent event) async {
  if (event.guild == null) return defaultPrefix;
  final settings = getSettings.call(event.guild!);
  if (settings == null) return defaultPrefix;

  final prefix = settings.prefix.get() ?? defaultPrefix;
  return prefix;
};

BotCommand enumConverter<T extends Enum>(List<T> values) => BotCommand.converter((plugin) => Converter<T>(
  (value, context) {
    final input = value.getQuotedWord();

    for (final x in values) {
      if (x.name == input) {
        return x;
      }
    }

    return null;
  },
  choices: values.map(
    (e) => CommandOptionChoiceBuilder(name: e.name, value: e.name),
  ).toList(),
));

Future<Member?> userToMember(User? user, {required Guild? guild}) async {
  if (user == null || guild == null) return null;

  try {
    return guild.members.get(user.id);
  } catch (_) {
    return null;
  }
}

extension PrettyDuration on Duration {
  String pretty() {
    if (inSeconds < 60) return '${inSeconds}s';
    if (inMinutes < 60) return '${inMinutes}m ${inSeconds.remainder(60)}s';
    if (inHours < 24) return '${inHours}h ${inMinutes.remainder(60)}m';
    return '${inDays}d ${inHours.remainder(24)}h';
  }
}