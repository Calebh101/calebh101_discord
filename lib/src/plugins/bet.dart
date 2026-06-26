import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'bet.g.dart';

abstract class BetPlugin<N extends num> extends BotPlugin {
  @override get info => BotPluginInfo(id: "bet", version: Version.parse("1.0.0A"), description: "Betting.");

  /// [amount] can be negative.
  void add<C extends ChatContext>(C context, KVStore store, User user, Guild guild, N amount);

  /// [amount] can be negative.
  N get<C extends ChatContext>(C context, KVStore store, User user, Guild guild);

  BotCommandPermissions get requiredPerms => .admin;

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyString.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("newbet", "Bet", "Create a bet. Use addoption <id> to add options.", (ChatContext context, String title, [GreedyString? description]) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bet = Bet(title: title, description: description?.data, id: Bet.nextId(settings), choices: {}, bets: {}, winnings: {});

        final current = settings.bets.get();
        current.add(bet);
        settings.bets.set(current);

        await context.respond(MessageBuilder(content: "Added bet **#${bet.id}**."));
      }, needsGuild: true, permissionsRequired: requiredPerms, aliases: ["addbet"]),

      BotCommand("allbets", "Bet", "Get all bets.", (T context, [bool excludeLocked = true]) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get().where((x) => excludeLocked ? (!x.locked) : true);

        await respondWithPagination(context, PaginatedEmbedBuilder(
          title: "All Bets",
          pages: EmbedPage.generate(bets.map((bet) {
            return EmbedFieldBuilder(name: "${bet.title} - Bet #${bet.id}", value: "${bet.choices.length} choices, ${bet.bets.length} votes", isInline: false);
          }).toList()),
          footer: ElementBasedEmbedFooterBuilder(elements: ["${bets.length} bets"]),
          color: await getColor(context.member),
        ), settings: settings);
      }, needsGuild: true),

      BotCommand("deletebet", "Bet", "Delete a bet by ID.", (T context, int id) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) {
          return context.respondWithError("No bet found by ID **$id**.");
        }

        bets.removeWhere((x) => x.id == id);
        settings.bets.set(bets);
        await context.respond(MessageBuilder(content: "Bet **#$id** deleted!"));
      }, needsGuild: true, permissionsRequired: requiredPerms),

      BotCommand("addoption", "Bet", "Add an option to a bet.", (ChatContext context, int id, String name, N amount, N winnings) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        if (bet.choices.containsKey(name)) return context.respondWithError("This choice already exists.");

        bet.choices[name] = amount;
        bet.winnings[name] = winnings;
        settings.bets.set(bets);

        await context.respond(MessageBuilder(content: "Added choice to bet **#${bet.id}**."));
      }, needsGuild: true, permissionsRequired: requiredPerms),

      BotCommand("remoption", "Bet", "Remove an option from a bet.", (ChatContext context, int id, GreedyString name) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        if (!bet.choices.entries.any((x) => x.key.toLowerCase() == name.data.toLowerCase())) return context.respondWithError("This choice doesn't exist.");

        bet.choices.removeWhere((k, v) => k.toLowerCase() == name.data.toLowerCase());
        settings.bets.set(bets);

        await context.respond(MessageBuilder(content: "Removed choice \"${name.data}\" from bet **#${bet.id}**."));
      }, needsGuild: true, permissionsRequired: requiredPerms),

      BotCommand("lockbet", "Bet", "Lock people from betting or removing their bets from a bet.", (ChatContext context, int id) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        bet.locked = !bet.locked;
        settings.bets.set(bets);

        await context.respond(MessageBuilder(content: "${bet.locked ? "Locked" : "Unlocked"} bet $id."));
      }, needsGuild: true, permissionsRequired: requiredPerms),

      BotCommand("getbet", "Bet", "Get a bet by ID.", (T context, int id) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        if (bet.choices.isEmpty) return context.respondWithError("This bet needs at least 1 option.");

        await context.respond(MessageBuilder(embeds: [bet.toEmbed(await getColor(context.member), context.getPrintablePrefix(store: store))]));
      }, needsGuild: true),

      BotCommand("bet", "Bet", "Bet on a choice.", (T context, int id, GreedyString choice) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);
        Logger.print("Bet", "Bet ${bet?.id}, choices: ${bet?.choices}, input: $choice");

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        if (bet.locked) return context.respondWithError("This bet is locked.");
        if (!bet.choices.entries.any((x) => x.key.toLowerCase() == choice.data.toLowerCase())) return context.respondWithError("This choice doesn't exist.");
        if (bet.bets.containsKey(context.user.id.value)) return context.respondWithError("You already bet on bet #$id! Use `rembet` to remove your bet.");

        final choiceEntry = bet.choices.entries.firstWhere(
          (x) => x.key.toLowerCase() == choice.data.toLowerCase(),
        );

        final payment = choiceEntry.value;
        final actualChoiceName = choiceEntry.key;
        final amount = get(context, store, context.user, context.guild!);

        if (amount < payment) return context.respondWithError("You don't have enough! You have **$amount**, you need **$payment**.");
        bet.bets[context.user.id.value] = actualChoiceName;

        if (payment is! N) return context.respondWithError("Something went wrong.\n```Expected type $N, got ${payment.runtimeType}```");
        settings.bets.set(bets);

        add(context, store, context.user, context.guild!, -payment as N);
        await context.respond(MessageBuilder(content: "Bet **$payment** on **${choice.data}**!"));
      }, needsGuild: true),

      BotCommand("mybet", "Bet", "Get my bet.", (T context, int id) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        if (bet.locked) return context.respondWithError("This bet is locked.");

        final choice = bet.bets[context.user.id.value];
        final amount = get(context, store, context.user, context.guild!);

        await context.respond(MessageBuilder(content: choice != null ? "Your choice:\n$choice" : "You haven't bet on bet #$id yet!"));
      }, needsGuild: true),

      BotCommand("rembet", "Bet", "Remove your bet for a bet.", (T context, int id) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        if (bet.locked) return context.respondWithError("This bet is locked.");
        if (!bet.bets.containsKey(context.user.id.value)) return context.respondWithError("You don't have a bet on bet #$id!");

        final choice = bet.bets[context.user.id.value]!;
        final payment = bet.choices[choice]!;

        bet.bets.remove(context.user.id.value);
        if (payment is! N) return context.respondWithError("Something went wrong.\n```Expected type $N, got ${payment.runtimeType}```");
        settings.bets.set(bets);

        add(context, store, context.user, context.guild!, payment);
        await context.respond(MessageBuilder(content: "Removed bet of **$payment** on **${bet.title}**!"));
      }, needsGuild: true, aliases: ["unbet"]),

      BotCommand("betpay", "Bet", "Pay out a bet option.", (T context, int id, String name) async {
        final settings = BetServerSettings(store, context.guild!.id);
        final bets = settings.bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);

        if (bet == null) return context.respondWithError("No bet found by ID **$id**.");
        if (!bet.choices.entries.any((x) => x.key.toLowerCase() == name.toLowerCase())) return context.respondWithError("This choice doesn't exist.");

        final entries = bet.bets.entries.where((x) => x.value == name);
        final payout = bet.choices.entries.firstWhere((x) => x.key.toLowerCase() == name).value;

        for (final entry in entries) {
          final user = await context.client.users.get(Snowflake(entry.key));
          add(context, store, user, context.guild!, bet.winnings[name]! as N);
        }

        await context.respond(MessageBuilder(content: "Paid out **${entries.length}** users."));
      }, needsGuild: true, permissionsRequired: requiredPerms, aliases: ["payout"]),

      BotCommand("betupdate", "Bet", "Update a bet's message.", (MessageChatContext context) async {
        final message = context.message.referencedMessage;
        if (message == null || message.author.id != context.client.user.id || message.embeds.length != 1) return context.respondWithError("Invalid message.");

        final id = int.tryParse(message.embeds.firstOrNull?.footer?.text.replaceFirst("#", "") ?? "");
        if (id == null) return context.respondWithError("Unable to parse ID.");

        final bets = BetServerSettings(store, context.guildId!).bets.get();
        final bet = bets.firstWhereOrNull((x) => x.id == id);
        if (bet == null) return context.respondWithError("Invalid ID: `$id`");

        await message.edit(MessageUpdateBuilder(embeds: [bet.toEmbed(await getColor(context.member), context.getPrintablePrefix(store: store))]));
        await context.message.react(ReactionBuilder(name: "✅", id: null));
      }, options: BotCommandOptions(type: .textOnly), permissionsRequired: .admin, needsGuild: true, triggerTyping: false, aliases: ["updatebet"]),
    ];
  }
}

@JsonSerializable(anyMap: true)
class Bet {
  final String title;
  final String? description;
  final int id;
  final Map<String, num> choices;
  final Map<String, num> winnings;
  final Map<int, String> bets;
  bool locked;

  static int nextId(BetServerSettings settings) {
    final id = settings.currentBetId.get() + 1;
    settings.currentBetId.set(id);
    return id;
  }

  Bet({required this.title, required this.description, required this.id, required this.choices, required this.bets, this.locked = false, required this.winnings});
  factory Bet.fromJson(Map input) => _$BetFromJson(input);
  Map toJson() => _$BetToJson(this);

  EmbedBuilder toEmbed(DiscordColor? color, String prefix) {
    return EmbedBuilder(
      title: "$title - Bet #$id - ${locked ? "Locked" : "Unlocked"}",
      description: description,
      color: color,
      footer: EmbedFooterBuilder(text: "#$id"),
      fields: choices.mapTo((k, v) {
        final whoBetted = bets.entries.where((x) => x.value == k);
        return EmbedFieldBuilder(name: k, value: [
          "**$v** gabes - **${winnings[k]}** if you win - **${whoBetted.length}** bets",
          (whoBetted.map((x) => x.key.toMention()).join(", ")),
          if (!locked) "To bet this option, use: `${prefix}bet $id $k`",
        ].join("\n"), isInline: false);
      }).toList(),
    );
  }
}

class BetServerSettings extends ServerSettings {
  BetServerSettings(super.store, super.id);

  SettingsObjectNotNull<int> get currentBetId => SettingsObjectNotNull(this, "betId", defaultFunction: () => 0);
  SettingsObjectNotNull<List<Bet>> get bets => SettingsObject.list(this, "bets", encodeFunction: (x) => x.toJson(), decodeFunction: (input) => Bet.fromJson(input));
}