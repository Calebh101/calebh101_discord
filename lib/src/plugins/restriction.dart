import 'dart:async';
import 'dart:convert';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'restriction.g.dart';

class RestrictCommandsPlugin extends BotPluginLegacy {
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

    if (guild == null) {
      final dmDisabled = RestrictBotSettings(store).disabledCommandsDm.get();
      if (dmDisabled.contains(command)) return null;
      return "No guild";
    }

    final settings = RestrictServerSettings(store, guild.id);
    if (isClaimer(settings: settings, id: userId)) return "Bot claimer";
    if (canAdminUseDisabledCommands(settings) && isAdmin(settings: settings, member: await guild.members.get(userId))) return "Bot admin";
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

    final disabled = (settings.disabled.get() ?? {})[command] ?? false;
    if (disabled) return null;

    final restrictionsOld = settings.restrictions.get()?.firstWhereOrNull((x) => x.command == command);
    final restrictions = settings.restrictionsAdvanced.get().firstWhereOrNull((x) => x.command == command);
    final totalRestrictions = (restrictionsOld?.data.length ?? 0) + (restrictions?.ors.map((x) => x.length).sum ?? 0);

    Future<List<bool>> checkConditions(List<RestrictionData> data) async {
      return await Future.wait(data.map((x) async => switch (x.type) {
        Restriction.channel => x.data == channelId.value,
        Restriction.notChannel => x.data != channelId.value,
        Restriction.role => (await getRoleIds()).any((y) => x.data == y.value),
        Restriction.notRole => !(await getRoleIds()).any((y) => x.data == y.value),
        Restriction.user => x.data == userId.value,
        Restriction.notUser => x.data != userId.value,
      }));
    }

    if (restrictionsOld != null) {
      final restrictions = restrictionsOld;
      final conditions = await checkConditions(restrictions.data);

      final pass = switch (restrictions.combination) {
        RestrictionCombination.and => conditions.every,
        RestrictionCombination.or => conditions.any,
      }((x) => x);

      if (!pass) return null;
    }

    if (restrictions == null) return "No advanced restrictions";
    bool passed = false;
    String? passedConditions;

    for (final ands in restrictions.ors) {
      final conditions = await checkConditions(ands);

      if (conditions.every((x) => x)) {
        passedConditions = ands.join(" and ");
        passed = true;
        break;
      }
    }

    return passed ? "Passed condition: `$passedConditions`" : null;
  }

  static bool canAdminUseDisabledCommands(RestrictServerSettings settings) {
    return settings.allowAdminToUseRestrictedCommands.get() ?? true;
  }

  static Future<bool> assureCanEditRestrictions(ChatContext context, RestrictServerSettings settings) async {
    if (!canAdminUseDisabledCommands(settings)) {
      if (!context.verifyPerms(BotCommandPermissions.claimer, settings)) {
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
        final found = BotCommand.getCommand(command);

        if (found == null) {
          return context.respondWithError("Command not found: `$command`");
        }

        if (found.permissionsRequired == .owner) {
          return context.respondWithError("You can't override this command.");
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
          return [settings.restrictions.get()?.firstWhereOrNull((x) => x.command == command), settings.restrictionsAdvanced.get().firstWhereOrNull((x) => x.command == command)].whereType<BaseCommandRestrictions>().join(", ");
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
      BotCommand("setrestrictions", "Restrictions", "Set command restrictions", (T context, String command, GreedyStringList input) async {
        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);
        if (await assureCanEditRestrictions(context, settings) == false) return;

        if (BotCommand.getCommand(command) == null) {
          return context.respondWithError("Command not found: `$command`");
        }

        final restrictions = RestrictionData.tryParse(input.data);
        final data = AdvancedCommandRestrictions(command: command, ors: restrictions);
        Logger.print("Restrictions", "Found restrictions from input: $input\n$data");

        final current = settings.restrictionsAdvanced.get();
        current.removeWhere((x) => x.command == command);
        current.add(data);
        settings.restrictionsAdvanced.set(current);

        final currentOld = settings.restrictions.get() ?? [];
        currentOld.removeWhere((x) => x.command == command);
        settings.restrictions.set(currentOld);

        await context.respond(MessageBuilder(content: "Found ${restrictions.length} restrictions:\n${data.toDiscordCodeBlock()}"));
      }, permissionsRequired: BotCommandPermissions.admin, extendedDescription: "The first input (and, or) determines if all the restrictions for a command need to be entirely true, or only one of them needs to be true. The input after that are the actual restrictions, which can be the following operators, where `<id>` is an integer:\n\n${[Restriction.values.map((x) {
        return "- `${x.operator}<id>`: ${x.desc}";
      }).join("\n")].join("\n")}"),
      BotCommand("remrestrictions", "Restrictions", "Remove all restrictions from a command.", (T context, String command) async {
        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);
        if (await assureCanEditRestrictions(context, settings) == false) return;

        if (BotCommand.getCommand(command) == null) {
          return context.respondWithError("Command not found: `$command`");
        }

        final current = settings.restrictions.get() ?? [];
        current.removeWhere((x) => x.command == command);
        settings.restrictions.set(current);

        final currentOld = settings.restrictions.get() ?? [];
        currentOld.removeWhere((x) => x.command == command);
        settings.restrictions.set(currentOld);

        await context.respond(MessageBuilder(content: "Removed all restrictions for command `$command`."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("allrestrictions", "Restrictions", "View all restrictions for all commands.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);

        final restrictions = settings.restrictions.get() ?? [];
        final advanced = settings.restrictionsAdvanced.get();

        Map<String, String?> results = Map.fromEntries(BotCommand.commandRegistry.keys.map((x) => MapEntry(x, advanced.firstWhereOrNull((y) => y.command == x)?.serialize())).where((x) => x.value != null));

        await context.respond(MessageBuilder(content: "Found **${results.length}** commands, of which **${results.values.whereType<String>().length}** had restrictions.", attachments: [
          AttachmentBuilder(data: utf8.encode(jsonEncode(results)), fileName: "restrictions.txt"),
        ]));
      }, permissionsRequired: BotCommandPermissions.admin, aliases: ["saverestrictions"]),
      BotCommand("clearrestrictions", "Restrictions", "Clear all restrictions for all commands, after dumping them.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);

        final restrictions = settings.restrictions.get() ?? [];
        final advanced = settings.restrictionsAdvanced.get();

        Map<String, String?> results = Map.fromEntries(BotCommand.commandRegistry.keys.map((x) => MapEntry(x, advanced.firstWhereOrNull((y) => y.command == x)?.serialize())).where((x) => x.value != null));

        settings.restrictions.delete();
        settings.restrictionsAdvanced.delete();

        await context.respond(MessageBuilder(content: "Found **${results.length}** commands, of which **${results.values.whereType<String>().length}** had restrictions.\nAll restrictions have been deleted.", attachments: [
          AttachmentBuilder(data: utf8.encode(jsonEncode(results)), fileName: "restrictions.txt"),
        ]));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("restrictionsreact", "Restrictions", "Whether to react :no_entry_sign: when a user uses commands that are restricted.", (T context, bool value) async {
        final settings = RestrictServerSettings(store, context.guild!.id);
        settings.restrictionsReact.set(value);
        await context.respond(MessageBuilder(content: "Restriction reacts **${value ? "enabled" : "disabled"}**."));
      }, needsGuild: true, permissionsRequired: .admin),

      BotCommand("loadrestrictions", "Restrictions", "Load restrictions from a JSON input.", (ChatContext context) async {
        String? attachment;
        Map<String, String>? input;

        if (context is MessageChatContext) {
          final data = await context.message.attachments.firstOrNull?.fetch();
          attachment = data == null ? null : utf8.decode(data);
        } else if (context is InteractionChatContext) {
          final data = await context.interaction.data.resolved?.attachments?.values.firstOrNull?.fetch();
          attachment = data == null ? null : utf8.decode(data);
        }

        if (attachment == null) {
          return context.respondWithError("No attachment found. Please make sure you're including a valid attachment.");
        }

        try {
          input = RecursiveCaster.cast<Map<String, String>>(jsonDecode(attachment) as Map);
        } catch (e) {
          final v = () {
            try {
              return jsonDecode(attachment!);
            } catch (_) {
              return null;
            }
          }();

          Logger.warn("LoadRestrictions", "Unable to parse input: $e");
          return context.respondWithError("The first attachment you passed was not a valid JSON map.\n-# Expected: `${Map<String, String>}`, got: `${v?.runtimeType ?? "<unable to parse>"}`");
        }

        if (await context.assureGuild() == false) return;
        final settings = RestrictServerSettings(store, context.guild!.id);
        final results = <AdvancedCommandRestrictions>[];

        for (final entry in input.entries) {
          try {
            if (BotCommand.getCommand(entry.key) == null) continue;
            final items = entry.value.split(",");
            results.add(AdvancedCommandRestrictions(command: entry.key, ors: RestrictionData.tryParse(items)));
          } catch (e) {
            Logger.print("LoadRestrictions", "Unable to parse command ${entry.key}: $e");
          }
        }

        settings.restrictionsAdvanced.set(results);
        await context.respond(MessageBuilder(content: "Imported **${results.length}** restrictions from **${input.length}** entries."));
      }, permissionsRequired: BotCommandPermissions.admin),

      BotCommand("dmdisabled", "Restrictions", "Get the commands that are disabled in DMs, or a specific one.", (T context, [String? command]) async {
        final disabled = RestrictBotSettings(store).disabledCommandsDm.get();

        if (command != null) {
          final found = BotCommand.getCommand(command);
          if (found == null) return context.respondWithError("Invalid command: `$command`");

          return (await context.respond(MessageBuilder(content: "Command `$command` ${disabled.contains(command) ? "**is**" : "is **not**"} disabled in DMs."))).toVoid();
        }

        if (disabled.isEmpty) return (await context.respond(MessageBuilder(content: "No commands disabled in DMs."))).toVoid();
        await context.respond(MessageBuilder(content: "**${disabled.length}** commands disabled in DMs:\n\n${disabled.map((x) => '- `$x`').join("\n")}"));
      }, permissionsRequired: BotCommandPermissions.owner),

      BotCommand("dmdisable", "Restrictions", "Disable a command in DMs.", (T context, String command) async {
        final settings = RestrictBotSettings(store);
        final disabled = settings.disabledCommandsDm.get();

        final found = BotCommand.getCommand(command);
        if (found == null) return context.respondWithError("Invalid command: `$command`");

        disabled.add(command);
        settings.disabledCommandsDm.set(disabled);
        await context.respond(MessageBuilder(content: "Command `$command` **disabled** in DMs."));
      }, permissionsRequired: BotCommandPermissions.owner),

      BotCommand("dmenable", "Restrictions", "Enable a command in DMs.", (T context, String command) async {
        final settings = RestrictBotSettings(store);
        final disabled = settings.disabledCommandsDm.get();

        final found = BotCommand.getCommand(command);
        if (found == null) return context.respondWithError("Invalid command: `$command`");
        if (!disabled.contains(command)) return context.respondWithError("Command not disabled.");

        disabled.remove(command);
        settings.disabledCommandsDm.set(disabled);
        await context.respond(MessageBuilder(content: "Command `$command` **enabled** in DMs."));
      }, permissionsRequired: BotCommandPermissions.owner),
    ];
  }
}

class RestrictBotSettings extends BotSettings {
  RestrictBotSettings(super.store);

  SettingsObjectNotNull<List<String>> get disabledCommandsDm => SettingsObject.list(this, "disabledCommandsDm");
}

class RestrictServerSettings extends ServerSettings {
  RestrictServerSettings(super.store, super.id);

  SettingsObject<bool> get allowAdminToUseRestrictedCommands => SettingsObject(this, "allowAdminToUseRestrictedCommands");
  SettingsObject<Map<String, bool>> get disabled => SettingsObject(this, "disabled", decodeFunction: (input) => input == null ? null : RecursiveCaster.cast<Map<String, bool>>(input));
  SettingsObject<Map<String, bool>> get overrideDefaultPermissions => SettingsObject(this, "overrideDefaultPermissions", decodeFunction: (input) => input == null ? null : RecursiveCaster.cast<Map<String, bool>>(input));
  SettingsObject<List<CommandRestrictions>> get restrictions => SettingsObject(this, "restrictions", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => CommandRestrictions.fromJson(x)).toList());
  SettingsObjectNotNull<List<AdvancedCommandRestrictions>> get restrictionsAdvanced => SettingsObject.list(this, "restrictionsA", encodeFunction: (x) => x.toJson(), decodeFunction: (x) => AdvancedCommandRestrictions.fromJson(x));
  SettingsObjectNotNull<bool> get restrictionsReact => SettingsObjectNotNull(this, "restrictionsReact", defaultFunction: () => true);
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

  static List<List<RestrictionData>> tryParse(List<String> input) {
    return input.mapToList((data) {
      final elements = data.trim().split(" ").map((x) => x.trim()).toList();
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
    }).whereType<List<RestrictionData>>().toList();
  }

  @override
  String toString() {
    return "${type.operator}$data";
  }
}

abstract class BaseCommandRestrictions {
  final String command;

  const BaseCommandRestrictions({required this.command});

  String serialize();
}

@Deprecated("Use AdvancedCommandRestrictions instead.")
@JsonSerializable(anyMap: true)
class CommandRestrictions extends BaseCommandRestrictions {
  final List<RestrictionData> data;
  final RestrictionCombination combination;

  const CommandRestrictions({required super.command, required this.data, required this.combination});
  factory CommandRestrictions.fromJson(Map json) => _$CommandRestrictionsFromJson(json);
  Map<String, dynamic> toJson() => _$CommandRestrictionsToJson(this);

  @override
  String toString() {
    return data.map((x) => x.toString()).join(" ${combination.name} ");
  }

  @override
  String serialize() {
    return "${combination.name} ${data.map((x) => x.toString()).join(",")}";
  }
}

@JsonSerializable(anyMap: true)
class AdvancedCommandRestrictions extends BaseCommandRestrictions {
  final List<List<RestrictionData>> ors;

  const AdvancedCommandRestrictions({required super.command, required this.ors});
  factory AdvancedCommandRestrictions.fromJson(Map json) => _$AdvancedCommandRestrictionsFromJson(json);
  Map<String, dynamic> toJson() => _$AdvancedCommandRestrictionsToJson(this);

  @override
  String toString() {
    return ors.map((ands) => "(${ands.join(" and ")})").join(" or ");
  }

  @override
  String serialize() {
    return ors.map((ands) => ands.join(" ")).join(",");
  }
}