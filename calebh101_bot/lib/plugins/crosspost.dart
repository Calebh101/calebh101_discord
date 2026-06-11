import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

const int defaultMinChannels = 3;
const Duration window = Duration(seconds: 10);

final Map<Snowflake, List<({String content, Snowflake channelId, DateTime timestamp})>> messages = {};

class CrosspostPlugin extends BotPluginLegacy {
  CrosspostPlugin() : super(id: "crosspost", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("crosspost", "Admin", "Set if the bot should delete crossposted messages.", (T context, bool value) async {
        if (await context.assureGuild() == false) return;
        final settings = CrosspostServerSettings(store, context.guild!.id);
        settings.enabled.set(value);
        await context.respond(MessageBuilder(content: "Anti-crossposting rules will now ${value ? "be **enforced**" : "**not** be enforced"}."));
      }, permissionsRequired: .admin),
      BotCommand("crosspostchannels", "Admin", "Set how many channels someone has to crosspost in to trigger the warning. Defaults to $defaultMinChannels.", (T context, [int? value]) async {
        if (await context.assureGuild() == false) return;
        value ??= defaultMinChannels;
        if (value < 2) return context.respondWithError("Value must be 2 or greater.");
        final settings = CrosspostServerSettings(store, context.guild!.id);
        settings.amount.set(value);
        await context.respond(MessageBuilder(content: "A crossposting warning will now be shown when the user crossposts in **$value** channels."));
      }, permissionsRequired: .admin),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) {
      client.onMessageCreate.listen((event) async {
        if (event.guildId == null) return;
        final settings = CrosspostServerSettings(context.store, event.guildId!);
        if (settings.warningChannel.get() == null) return;
        if (settings.enabled.get() != true) return;

        final message = event.message;
        final userId = message.author.id;
        final content = message.content.trim().toLowerCase();
        final now = DateTime.now();

        messages[userId] ??= [];
        if (message.author is! User) return;
        final user = message.author as User;

        if (user.isBot || user.isSystem) return;
        if (event.member != null && isAdmin(settings: settings, member: await event.member!.get())) return;

        messages[userId]!.removeWhere(
          (entry) => now.difference(entry.timestamp) > window,
        );

        messages[userId]!.add((
          content: content,
          channelId: message.channelId,
          timestamp: now,
        ));

        final entries = messages[userId]!.where((e) => e.content == content).toList();
        final channels = entries.map((e) => e.channelId).toSet();

        if (channels.length >= (settings.amount.get() ?? defaultMinChannels)) {
          await handle(context: context, message: message, guild: await event.guild!.get(), channels: channels, client: client);
        }
      });
    });

    Timer.periodic(Duration(seconds: 30), (_) {
      final now = DateTime.now();

      messages.removeWhere(
        (_, entries) {
          entries.removeWhere((e) => now.difference(e.timestamp) > window);
          return entries.isEmpty;
        },
      );
    });
  }
}

Future<void> handle({
  required BotContext context,
  required Message message,
  required Guild guild,
  required NyxxGateway client,
  required Set<Snowflake> channels,
}) async {
  try {
    await message.delete();
    final settings = CrosspostServerSettings(context.store, guild.id);
    final channelId = settings.warningChannel.get()!;
    final channel = await client.channels.get(Snowflake(channelId));

    if (channel is GuildTextChannel) {
      await channel.sendMessage(MessageBuilder(
        content: [
          message.author.id.value.toMention(),
          "Please don't crosspost your message in multiple channels.",
          "If you'd like to move a message to a different channel, first delete the original message.",
          "-# Channel #${channels.length}: ${message.channelId.value.toChannel()}, guild `${guild.id}`"
        ].join("\n"),
      ));
    }
  } catch (e) {
    Logger.warn("Crosspost", "Unable to handle message ${message.id}: $e");
  }
}

class CrosspostServerSettings extends ServerSettings {
  CrosspostServerSettings(super.store, super.id);

  SettingsObject<bool> get enabled => SettingsObject(this, "crosspostEnabled");
  SettingsObject<int> get amount => SettingsObject(this, "crosspostAmount");
}