import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class SupportPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "support", version: Version.parse("1.0.0A"), description: "Several utilities for support-based servers.");

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyGuildChannelList.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("supportchannels", "Support", "Get the current support channels.", (T context) async {
        final settings = Calebh101BotServerSettings(store, context.guildId!);
        final ids = settings.supportChannels.get();

        await context.respond(MessageBuilder(content: ids.map((x) => x.value.toChannel()).nullIfEmpty?.join(", ") ?? "No support channels set."));
      }, needsGuild: true),

      BotCommand("setsupportchannels", "Support", "Set the channels that are recognized as support channels.", (T context, [GreedyGuildChannelList? channels]) async {
        final settings = Calebh101BotServerSettings(store, context.guildId!);

        if (channels == null) {
          settings.supportChannels.delete();
          await context.respond(MessageBuilder(content: "Support channels **reset**."));
          return;
        }

        settings.supportChannels.set(channels.data.mapToList((x) => x.id));
        await context.respond(MessageBuilder(content: "Support channels set to **${channels.data.length}** channels."));
      }, permissionsRequired: .admin, needsGuild: true),

      BotCommand("ns", "Support", "You are here, but you *want* to be here.", (T context) async {
        final settings = Calebh101BotServerSettings(store, context.guildId!);
        final ids = settings.supportChannels.get();

        if (ids.isEmpty) {
          return context.respondWithError("No support channels set.");
        }

        await context.respond(MessageBuilder(
          content: "## You are *here*:\n:point_right: ${context.channel.toMention()}\n## You *want* to be here:\n${ids.map((x) => ":point_right: ${x.value.toChannel()}").join("\n")}",
        ));
      }, needsGuild: true),
    ];
  }
}