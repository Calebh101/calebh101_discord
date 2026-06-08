import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class ChannelsPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "channels", version: Version.parse("1.0.0A"), description: "Channel utilities.");

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyGuildTextChannelList.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("seticon", "Channels", "Set the icon of this channel.", (T context, [GreedyString? icon]) async {
        final channel = context.channel as GuildTextChannel;
        final name = channel.name;
        final result = processNameWithDetails(name: name, icon: icon?.data);

        final output = result.output;
        final cleared = result.cleared;

        Logger.print("SetIcon", "Channel ${channel.id}: '$name' => '$cleared' => '$output'");
        await context.respond(MessageBuilder(content: "New name: $output"));
        await channel.update(GuildChannelUpdateBuilder(name: output));
      }, needsGuild: true, permissionsRequired: .admin),

      BotCommand("iconsetup", "Channels", "Run through a list of channels, asking for their icons. Use allInGuild for all channels, or allInCategory:name for whole categories.", (MessageChatContext context, GreedyGuildTextChannelList channels) async {
        int updated = 0;

        for (int i = 0; i < channels.input.length; i++) {
          final channel = channels.input[i];
          final result = await askForEmojis(context, required: 1, prompt: "React with 1 emoji for the new icon of ${channel.toMention()} (`${channel.id}`) (**${i + 1}/${channels.input.length}**).\nReact with :stop_button: to skip, :record_button: to cancel.\nCustom emojis are **not** allowed.", allowCustom: false);

          Logger.print("Channels", "Processing result of type ${result.runtimeType}");
          if (result == null || result.emojis.isEmpty) continue;

          if (result.emojis.first.name == "⏺️") {
            await context.respond(MessageBuilder(content: "Cancelled after channel **${i + 1}**/${channels.input.length}."));
            return;
          }

          final name = processName(name: channel.name, icon: result.emojis.first.name);
          await result.sentMessage.edit(MessageUpdateBuilder(content: "New name: `#$name`"));
          await channel.update(GuildTextChannelUpdateBuilder(name: name));
          updated++;
        }

        await context.respond(MessageBuilder(content: "Updated **$updated/${channels.input.length}** channels."));
      }, permissionsRequired: .admin, needsGuild: true, options: BotCommandOptions(type: .textOnly), aliases: ["seticons"]),
    ];
  }
}

String processName({required String name, String? icon}) {
  return processNameWithDetails(name: name, icon: icon).output;
}

({String output, String cleared}) processNameWithDetails({required String name, String? icon}) {
  final cleared = name.replaceFirst(RegExp(r'^[-\p{Z}\p{P}\p{S}\p{Mn}]+', unicode: true), '');
  final output = icon != null ? "$icon-$cleared" : cleared;
  return (cleared: cleared, output: output);
}