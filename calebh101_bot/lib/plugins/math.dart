import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class MathPlugin extends BotPlugin {
  MathPlugin() : super(id: "math", version: Version.parse("1.0.0A"));

  @override FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("setmathchannel", "Fun", "Set the channel for mathing. Pass without a value to disable.", (ChatContext context, [GuildTextChannel? channel]) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        settings.mathChannel.set(channel?.id);

        await context.respond(MessageBuilder(
          content: "Math channel ${channel != null ? "set to ${channel.toMention()}" : "**reset**"}!",
        ));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("mathchannel", "Fun", "Get the current math channel.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final id = settings.mathChannel.get();

        await context.respond(MessageBuilder(
          content: "Math channel ${id != null ? "is currently set to ${id.value.toChannel()}" : "not set"}."
        ));
      }),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) => client.onMessageCreate.listen((event) {
      if (event.guildId == null) return;
      final settings = Calebh101BotServerSettings(store, event.guildId!);
      if (settings.mathChannel.get() == null || settings.mathChannel.get() != event.message.channelId) return;

      final math = settings.currentMath.get();
      if (math == null) return;

      final int? number = int.tryParse(event.message.content.trim());
      if (number == null) return;
    }));
  }
}