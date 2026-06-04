import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

extension CommandContextHelper on CommandContext {
  Snowflake get userId => user.id;
  Snowflake? get guildId => guild?.id;

  void respondWithError(String message, {ResponseLevel? level}) async {
    try {
      await respond(MessageBuilder(content: message), level: level);
    } catch (e) {
      Logger.warn("respondWithError", "Unable to respond with error '$message': $e");
    }
  }

  bool verifyPerms(BotCommandPermissions perms, ServerSettings? settings) {
    final override = settings != null ? RestrictCommandsPlugin.getOverrideDefaultPermissions(store: settings.store, command: command.name, guildId: guild?.id) : "No settings";
    final o = override == null;

    switch (perms) {
      case BotCommandPermissions.any: return true;
      case BotCommandPermissions.mod: return o ? true : (member == null ? false : isMod(settings: settings!, member: member!));
      case BotCommandPermissions.admin: return o ? true : (member == null ? false : isAdmin(settings: settings!, member: member!));
      case BotCommandPermissions.claimer: return o ? true : isClaimer(settings: settings!, id: user.id);
      case BotCommandPermissions.owner: return o ? true : isOwner(id: user.id);
    }
  }

  Future<bool> assurePerms(BotCommandPermissions perms, ServerSettings? settings) async {
    final result = verifyPerms(perms, settings);

    if (result == false) {
      await respond(MessageBuilder(content: "You don't have the required permissions to access this command.\n-# Permissions required: `${perms.name}`"));
      return false;
    }

    return true;
  }

  Future<bool> assureOwner() async {
    final result = verifyPerms(BotCommandPermissions.owner, null);

    if (result == false) {
      await respond(MessageBuilder(content: "You don't have the required permissions to access this command.\n-# Permissions required: `${BotCommandPermissions.owner.name}`"));
      return false;
    }

    return true;
  }

  FutureOr<String?> userString(NyxxGateway client, {bool detailed = false}) async => userOrMemberToString(member, user, detailed: detailed, client: client);

  Future<Message> updateMessage(Message message, MessageUpdateBuilder builder) async {
    if (this is InteractionChatContext) {
      return await (this as InteractionChatContext).interaction.updateOriginalResponse(builder);
    } else {
      return await message.update(builder);
    }
  }

  Future<bool> assureGuild() async {
    final success = guild != null && member != null;

    if (!success) {
      respondWithError("No guild/member found.");
      return false;
    }

    return true;
  }

  Uri createDiscordLink([Snowflake? message]) {
    return discordLink(guild?.id, channel.id, message);
  }
}

enum PrefixMode {
  text,
  slash,
}

final _gPP = getPrintablePrefix;

extension ContextHelper on ChatContext {
  String getPrintablePrefix({required KVStore store, PrefixMode defaultMode = .slash}) {
    return _gPP(guildId: guildId, store: store, defaultMode: defaultMode);
  }
}