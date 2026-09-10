import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

abstract class PermOverridePlugin extends BotPlugin {
  final String function;
  final String category;

  new(this.function, this.category);

  @override
  BotPluginInfo get info => .new(id: function, version: .parse("1.0.0A"), description: "Perm overrides: $function");

  Flags<Permissions> get allow;
  Flags<Permissions> get deny;

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [GreedyGuildTextChannelList.converter()];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("sync$function", "$category", "Sync the $function role.", (T context) async {
        final settings = PermOverrideSettings(store, context.guild!.id, function);
        final role = settings.pRole.get();
        final ignore = settings.pIgnore.get() ?? [];

        if (role == null) {
          return context.respondWithError("No $function role set.");
        }

        final channels = await context.guild!.fetchChannels();
        final m = await context.respond(MessageBuilder(content: "Updating 0/${channels.length} channels..."));

        for (int i = 0; i < channels.length; i++) {
          final channel = channels[i];
          final ignored = ignore.contains(channel.id);

          if ((i + 1) % 10 == 0) {
            Logger.print("$category", "Syncing channel $i/${channels.length - 1}. ${channel.id} (${channel.name})... (ignore: $ignored/${ignore.length})");
            await context.updateMessage(m, MessageUpdateBuilder(content: "Updating ${i + 1}/${channels.length} channels..."));
          }

          if (ignored) {
            continue;
          }

          final existing = channel.permissionOverwrites.firstWhereOrNull(
            (x) => x.id == role && x.type == PermissionOverwriteType.role,
          );

          await channel.updatePermissionOverwrite(
            PermissionOverwriteBuilder(
              id: role,
              type: PermissionOverwriteType.role,
              allow: allow,
              deny: deny,
            ),
          );

          /*await channel.updatePermissionOverwrite(PermissionOverwriteBuilder(id: role, type: PermissionOverwriteType.role, deny:
            ((channel.permissionOverwrites.firstWhereOrNull((x) => x.id == role && x.type == PermissionOverwriteType.role)?.deny ?? Permissions(0)) | (ignored ? Permissions(0) : Permissions.addReactions | Permissions.sendMessages | Permissions.sendMessagesInThreads | Permissions.createPublicThreads | Permissions.createPrivateThreads | Permissions.speak | Permissions.requestToSpeak | Permissions.stream | Permissions.useSoundboard)),
          allow: channel.permissionOverwrites.firstWhereOrNull((x) => x.id == role && x.type == PermissionOverwriteType.role)?.allow));*/
        }

        await context.updateMessage(m, MessageUpdateBuilder(content: "Updated ${channels.length} channels!"));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("set${function}role", "$category", "Set the $function role.", (T context, [Role? role]) async {
        final settings = PermOverrideSettings(store, context.guild!.id, function);

        if (role == null) {
          settings.pRole.delete();
          await context.respond(MessageBuilder(content: "$category role deleted."));
          return;
        }

        settings.pRole.set(role.id);
        await context.respond(MessageBuilder(content: "$category role set to ${await roleToString(role)}! Run `sync$function` to sync permissions."));
      }, needsGuild: true, permissionsRequired: .admin),
      BotCommand("set${function}ignored", "$category", "Set channels that are ignored from syncing the $function role.", (T context, [GreedyGuildTextChannelList? channels]) async {
        final settings = PermOverrideSettings(store, context.guild!.id, function);
        settings.pIgnore.set(channels?.input.map((x) => x.id).toList());
        await context.respond(MessageBuilder(content: "Now ignoring **${channels?.input.length ?? 0}** channels."));
      }, needsGuild: true, permissionsRequired: .admin),
      BotCommand("${function}role", "$category", "Get the current $function role.", (T context) async {
        final settings = PermOverrideSettings(store, context.guild!.id, function);
        final id = settings.pRole.get();
        final role = await tryCatchA(() => context.guild!.roles.get(id!));
        await context.respond(MessageBuilder(content: role != null ? "Current $function role: ${await roleToString(role)}" : (id != null ? "Invalid role set: ${id.toDiscordCodeString()}" : "No $function role set.")));
      }, needsGuild: true),
      BotCommand("${function}ignored", "$category", "Get the current $function role ignored channels.", (T context) async {
        final settings = PermOverrideSettings(store, context.guild!.id, function);
        final channels = settings.pIgnore.get() ?? [];

        await context.respond(MessageBuilder(content: channels.isEmpty ? "No channels ignored." : "**${channels.length}** ignored $function channels:\n\n${channels.map((x) {
          return "- ${x.value.toChannel()} (`$x`)";
        }).join("\n")}"));
      }, needsGuild: true),
      BotCommand("${function}info", "$category", "Get info about $function.", (T context) async {
        await context.respond(MessageBuilder(
          content: "Allow: `${allow.value}` (${allow.length})\nDeny: `${deny.value}` (${deny.length})",
        ));
      }),
    ];
  }
}

class PermOverrideSettings extends EntitySettings {
  new(super.store, Snowflake id, String function) : super(id: "$function.$id", scope: .server);

  SettingsObject<Snowflake> get pRole => SettingsObject.snowflake(this, "muteRole");
  SettingsObject<List<Snowflake>> get pIgnore => SettingsObject.listSnowflake(this, "muteIgnore");
}