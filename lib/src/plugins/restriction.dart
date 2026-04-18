import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'restriction.g.dart';

class RestrictCommandsPlugin extends BotPlugin {
  RestrictCommandsPlugin() : super(id: "restrict", version: Version.parse("1.0.0A"));
  static bool enabled = false;

  @override
  Future<void> onRegister() async {
    enabled = true;
  }

  @override
  FutureOr<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      enumConverter<RestrictionCombination>(RestrictionCombination.values),
    ];
  }

  // Non-null if false
  static String? getOverrideDefaultPermissions({required KVStore store, required String command, required Snowflake? guildId}) {
    final entry = BotCommand.getCommand(command);
    if (entry == null) return "No command found";
    if (entry.permissionsRequired == BotCommandPermissions.owner) return "Command requires owner";

    if (guildId == null) return "No guild";
    final settings = RestrictServerSettings(store, guildId);
    final map = settings.overrideDefaultPermissions.get() ?? {};
    if (map[command] ?? false) return null;
    return "Not specified (included: ${map.containsKey(command)})";
  }

  // Non-null if succeed
  static Future<String?> check({required NyxxGateway client, required String command, required KVStore store, required Guild? guild, required Snowflake userId, required Snowflake channelId}) async {
    if (!enabled) return "Plugin not enabled";
    if (isOwner(id: userId)) return "Bot owner";
    if (guild == null) return "No guild";

    final settings = RestrictServerSettings(store, guild.id);
    if (isClaimer(settings: settings, id: userId)) return "Bot claimer";
    if (canAdminUseDisabledCommands(settings) && isAdmin(settings: settings, id: userId)) return "Bot admin";
    List<Snowflake>? roleIds;

    Future<List<Snowflake>> getRoleIds() async {
      try {
        if (roleIds != null) return roleIds!;
        final user = await client.users.get(userId);
        final member = await userToMember(user, guild: guild);
        final ids = member!.roleIds;

        roleIds = ids;
        return roleIds!;
      } catch (e) {
        roleIds ??= [];
        return roleIds!;
      }
    }

    final disabled = (settings.disabled.get() ?? {})[command/*.replaceFirst("dev_", "")*/] ?? false;
    if (disabled) return null;

    final restrictions = settings.restrictions.get()?.firstWhereOrNull((x) => x.command/*.replaceFirst("dev_", "")*/ == command/*.replaceFirst("dev_", "")*/);
    if (restrictions == null) return "No restrictions";

    final conditions = await Future.wait(restrictions.data.map((x) async => switch (x.type) {
      Restriction.channel => x.data == channelId.value,
      Restriction.notChannel => x.data != channelId.value,
      Restriction.role => (await getRoleIds()).any((y) => x.data == y.value),
      Restriction.notRole => !(await getRoleIds()).any((y) => x.data == y.value),
      Restriction.user => x.data == userId.value,
      Restriction.notUser => x.data != userId.value,
    }));

    final pass = switch (restrictions.combination) {
      RestrictionCombination.and => conditions.every,
      RestrictionCombination.or => conditions.any,
    }((x) => x);

    return pass ? "Passed ${conditions.length} ${restrictions.combination.name} conditions" : null;
  }

  static bool canAdminUseDisabledCommands(RestrictServerSettings settings) {
    return settings.allowAdminToUseRestrictedCommands.get() ?? true;
  }

  static Future<bool> assureCanEditRestrictions(ChatContext context, RestrictServerSettings settings) async {
    if (!canAdminUseDisabledCommands(settings)) {
      if (await context.assurePerms(BotCommandPermissions.claimer, settings)) {
        await context.respond(MessageBuilder(content: "Due to current permissions, only the bot claimer can set command restrictions."));
        return false;
      }
    }

    return true;
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("setcommandenabled", "Restrictions", "Set if a command is usable or not. It'll always be usable to the bot owner and claimer.", (T context, String command, bool enabled) async {
        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);
        if (await assureCanEditRestrictions(context, settings) == false) return;

        if (BotCommand.getCommand(command) == null) {
          return context.respondWithError("Command not found: `$command`");
        }

        final current = settings.disabled.get() ?? {};
        current[command] = !enabled;
        settings.disabled.set(current);

        await context.respond(MessageBuilder(content: "Command `$command` has been **${enabled ? "enabled" : "disabled"}**."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("setcommandoverridedefault", "Restrictions", "Set if a command's default permissions should be overridden.", (T context, String command, bool override) async {
        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);
        if (await assureCanEditRestrictions(context, settings) == false) return;

        if (BotCommand.getCommand(command) == null) {
          return context.respondWithError("Command not found: `$command`");
        }

        final current = settings.overrideDefaultPermissions.get() ?? {};
        current[command] = override;
        settings.overrideDefaultPermissions.set(current);

        await context.respond(MessageBuilder(content: "Command `$command` permissions will be **${override ? "overridden" : "used"}**."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("checkcommand", "Restrictions", "Check if a command is usable by you.", (T context, String command, [User? user]) async {
        user ??= context.user;
        final entry = BotCommand.getCommand(command);
        if (entry == null) return context.respondWithError("Command not found: `$command`");

        final results = await check(client: context.client, command: command, store: store, guild: context.guild, userId: user.id, channelId: context.channel.id);
        final pass = results != null;

        final restrictions = () {
          if (context.guild == null) return null;
          final settings = RestrictServerSettings(store, context.guild!.id);
          final restrictions = settings.restrictions.get()?.firstWhereOrNull((x) => x.command/*.replaceFirst("dev_", "")*/ == command/*.replaceFirst("dev_", "")*/);
          return restrictions;
        }();

        final override = getOverrideDefaultPermissions(store: store, command: command, guildId: context.guild?.id);

        await context.respond(MessageBuilder(
          content: [
            "Pass: **${pass ? "Yes" : "No"}**",
            if (results != null) "Reason: $results",
            ?restrictions?.toDiscordCodeBlock(),
            if (override == null) "Default permissions overridden" else "Requires permissions: `${entry.permissionsRequired.name}`\n-# Not overriding: $override",
          ].join("\n"),
        ));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("setrestrictions", "Restrictions", "Set command restrictions", (T context, String command, RestrictionCombination mode, GreedyString input) async {
        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);
        if (await assureCanEditRestrictions(context, settings) == false) return;

        if (BotCommand.getCommand(command) == null) {
          return context.respondWithError("Command not found: `$command`");
        }

        final restrictions = RestrictionData.tryParse(input.data) ?? [];
        final data = CommandRestrictions(command: command, data: restrictions, combination: mode);

        final current = settings.restrictions.get() ?? [];
        current.add(data);
        settings.restrictions.set(current);

        await context.respond(MessageBuilder(content: "Found ${restrictions.length} restrictions:\n${data.toDiscordCodeBlock()}"));
      }, permissionsRequired: BotCommandPermissions.admin, extendedDescription: "The first input (and, or) determines if all the restrictions for a command need to be entirely true, or only one of them needs to be true. The input after that are the actual restrictions, which can be the following operators, where `<id>` is an integer:\n\n${[Restriction.values.map((x) {
        return "- `${x.operator}<id>`: ${x.desc}";
      }).join("\n")].join("\n")}"),
    ];
  }
}

class RestrictServerSettings extends ServerSettings {
  RestrictServerSettings(super.store, super.id);

  SettingsObject<bool> get allowAdminToUseRestrictedCommands => SettingsObject(this, "allowAdminToUseRestrictedCommands");
  SettingsObject<Map<String, bool>> get disabled => SettingsObject(this, "disabled", decodeFunction: (input) => input == null ? null : RecursiveCaster.cast<Map<String, bool>>(input));
  SettingsObject<Map<String, bool>> get overrideDefaultPermissions => SettingsObject(this, "overrideDefaultPermissions", decodeFunction: (input) => input == null ? null : RecursiveCaster.cast<Map<String, bool>>(input));
  SettingsObject<List<CommandRestrictions>> get restrictions => SettingsObject(this, "restrictions", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => CommandRestrictions.fromJson(x)).toList());
}

enum Restriction {
  user("user=", "Current user's ID matches `<id>`."),
  role("role=", "One of the current user's role IDs matches `<id>`."),
  channel("channel=", "Current channel ID matches `<id>`."),
  notUser("user!=", "Current user's ID does not `<id>`."),
  notRole("role!=", "None of the current user's role IDs matches `<id>`."),
  notChannel("channel!=", "Current channel ID does not match `<id>`.");

  final String operator;
  final String desc;
  const Restriction(this.operator, this.desc);
}

enum RestrictionCombination {
  and,
  or,
}

@JsonSerializable(anyMap: true)
class RestrictionData {
  final Restriction type;
  final int data;

  RestrictionData({required this.type, required this.data});
  factory RestrictionData.fromJson(Map json) => _$RestrictionDataFromJson(json);
  Map<String, dynamic> toJson() => _$RestrictionDataToJson(this);

  static List<RestrictionData>? tryParse(String input) {
    final elements = input.trim().split(" ").map((x) => x.trim()).toList();
    if (elements.isEmpty) return null;
    List<RestrictionData> results = [];

    outer: for (var element in elements) {
      for (final x in Restriction.values) {
        if (element.startsWith(x.operator)) {
          final o = element;
          element = element.replaceFirst(x.operator, "");
          final value = int.tryParse(element);

          if (value != null) {
            results.add(RestrictionData(type: x, data: value));
            continue outer;
          } else {
            Logger.warn("Restrictions", "Invalid restriction: ${x.operator} (from: $o)");
          }
        }
      }
    }

    return results.isEmpty ? null : results;
  }

  @override
  String toString() {
    return "${type.operator}$data";
  }
}

@JsonSerializable(anyMap: true)
class CommandRestrictions {
  final String command;
  final List<RestrictionData> data;
  final RestrictionCombination combination;

  const CommandRestrictions({required this.command, required this.data, required this.combination});
  factory CommandRestrictions.fromJson(Map json) => _$CommandRestrictionsFromJson(json);
  Map<String, dynamic> toJson() => _$CommandRestrictionsToJson(this);

  @override
  String toString() {
    return data.map((x) => x.toString()).join(" ${combination.name} ");
  }
}