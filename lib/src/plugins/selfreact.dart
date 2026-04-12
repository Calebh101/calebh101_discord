import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class SelfReactPlugin extends BotPlugin {
  SelfReactPlugin() : super(id: "selfreact", version: Version.parse("1.0.0A"));

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) => client.onMessageReactionAdd.listen((event) async {
      try {
        if (event.guildId == null) return;
        final settings = ServerSettings(context.store, event.guildId!);
        if (settings.selfReactAllowed.get() != false) return;
        final message = await event.message.fetch();

        if (event.userId == message.author.id) {
          await message.deleteReaction(ReactionBuilder.fromEmoji(event.emoji), userId: event.userId);
        }
      } catch (e) {
        Logger.warn("SelfReact", "Error: $e");
      }
    }));
  }

  @override
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [BotCommand("selfreact", "Server", "Enable/disable self-reacting. Defaults to allowed.", (ChatContext context, bool enabled) async {
      if (await context.assureGuild() == false) return;
      final settings = ServerSettings(store, context.guild!.id);
      settings.selfReactAllowed.set(enabled);
      await context.respond(MessageBuilder(content: "Self-reacting set to **${enabled ? "allowed" : "not allowed"}**."));
    }, permissionsRequired: BotCommandPermissions.admin)];
  }
}