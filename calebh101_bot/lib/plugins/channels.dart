import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class ChannelsPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "channels", version: Version.parse("1.0.0A"), description: "Channel utilities.");

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("seticon", "Channels", "Set the icon of this channel.", (T context, [GreedyString? icon]) async {
        final channel = context.channel as GuildTextChannel;
        final name = channel.name;
        final cleared = name.replaceFirst(RegExp(r'^[-\p{Z}\p{P}\p{S}\p{Mn}]+', unicode: true), '');
        final output = icon != null ? "${icon.data}-$cleared" : cleared;

        Logger.print("SetIcon", "Channel ${channel.id}: '$name' => '$cleared' => '$output'");
        await context.respond(MessageBuilder(content: "New name: $output"));
        await channel.update(GuildChannelUpdateBuilder(name: output));
      }, needsGuild: true, permissionsRequired: .admin),
    ];
  }
}