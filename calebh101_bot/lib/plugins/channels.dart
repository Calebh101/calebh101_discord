import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class ChannelsPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "channels", version: Version.parse("1.0.0A"), description: "Channel utilities.");

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    context.clients.run((client) {
      client.onMessageCreate.listen((event) async {
        if (event.guildId == null || event.member == null) return;

        final channel = event.message.channel;
        final user = event.message.author;
        final channelSettings = ChannelSettings(store, channel.id);
        final serverSettings = Calebh101BotServerSettings(store, event.guildId!);

        if (user is! User || user.isBot || user.isSystem) return;
        if (channelSettings.mediaOnly.get() == false) return;
        if (event.message.attachments.isNotEmpty || event.message.embeds.isNotEmpty) return;

        final member = await event.member!.get();
        if (isAdmin(settings: serverSettings, member: member)) return;
        if (serverSettings.modsBypassMediaOnly.get() && isMod(settings: serverSettings, member: member)) return;

        Logger.print("Channels", "Handling message ${event.message.id} in media-only channel ${channel.id} from user ${member.id}");

        await tryCatchA(() => event.message.delete(), onCatch: (e) {
          Logger.warn("Channels", "Unable to delete message ${event.message.id}: $e");
        },);
      });
    });
  }

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

      BotCommand("mediaonly", "Channels", "Set if this channels should be media only. Media counts as any attachments or embeds. Messages without attachments or embeds will be deleted.", (T context, bool value) async {
        final settings = ChannelSettings(store, context.channelId);
        settings.mediaOnly.set(value);

        await context.respond(MessageBuilder(content: "Channel is ${value ? "**media-only**" : "**not** media only"}."));
      }, needsGuild: true, permissionsRequired: .admin),

      BotCommand("modsbypassmediaonly", "Channels", "Set if mods bypass restrictions in media-only channels. Defaults to true.", (T context, bool value) async {
        final settings = Calebh101BotServerSettings(store, context.guildId!);
        settings.modsBypassMediaOnly.set(value);

        await context.respond(MessageBuilder(content: "Mods ${value ? "**will**" : "will **not**"} be able to bypass media-only channels."));
      }, needsGuild: true, permissionsRequired: .admin),
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