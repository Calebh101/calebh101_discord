import 'package:calebh101_discord/calebh101_discord.dart';

List<T> flatten<T>(List<List<T>> lists) => lists.expand((e) => e).toList();

Future<String> Function(MessageCreateEvent) prefixFromServerSettings(ServerSettings? Function(PartialGuild guild) getSettings) => (MessageCreateEvent event) async {
  if (event.guild == null) return defaultPrefix;
  final settings = getSettings.call(event.guild!);
  if (settings == null) return defaultPrefix;

  final prefix = settings.prefix.get() ?? defaultPrefix;
  return prefix;
};

BotCommand enumConverter<T extends Enum>(List<T> values) => BotCommand.converter((plugin) => Converter<T>(
  (value, context) {
    for (final x in values) {
      if (x.name == value.getQuotedWord()) {
        return x;
      }
    }

    return null;
  },
  choices: values.map(
    (e) => CommandOptionChoiceBuilder(name: e.name, value: e.name),
  ).toList(),
));