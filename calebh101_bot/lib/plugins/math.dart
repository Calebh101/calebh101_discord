import 'dart:async';
import 'dart:math';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:json_annotation/json_annotation.dart';

part 'math.g.dart';

double getCurrentStreakScale(int streak) {
  return min(1, streak / 500);
}

class MathPlugin extends BotPlugin {
  MathPlugin() : super(id: "math", version: Version.parse("1.0.0A"));

  @override
  Future<void> onRegister() {
    // Register each math plugin with their IDs here.

    Math.register("addsubtract", fromJson: AddSubtractMath.fromJson);
    Math.register("multdiv", fromJson: MultDivMath.fromJson);
    Math.register("exponent", fromJson: ExponentMath.fromJson);

    return super.onRegister();
  }

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      enumConverter<Symbol>(Symbol.values),
    ];
  }

  @override FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("setmathchannel", "Math", "Set the channel for mathing. Pass without a value to disable.", (T context, [GuildTextChannel? channel]) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        settings.mathChannel.set(channel?.id);

        await context.respond(MessageBuilder(
          content: "Math channel ${channel != null ? "set to ${channel.toMention()}" : "**reset**"}!",
        ));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("mathchannel", "Math", "Get the current math channel.", (T context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final id = settings.mathChannel.get();

        await context.respond(MessageBuilder(
          content: "Math channel ${id != null ? "is currently set to ${id.value.toChannel()}" : "not set"}."
        ));
      }),
      BotCommand("math", "Math", "Print the current math formula, or make a new one.", (T context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final allowedTypes = settings.allowedMathTypes.get() ?? Math.defaultTypes;
        final math = settings.currentMath.get() ?? newFormula(allowedTypes: allowedTypes, currentStreakScale: 0);
        settings.currentMath.set(math);
        await context.respond(MessageBuilder(embeds: [await math.toEmbed(context.member!, null)]));
      }),
      BotCommand("newmath", "Math", "Print a new math formula.", (T context, [double streakScale = 0]) async {
        if (await context.assureGuild() == false) return;
        if (streakScale < 0 || streakScale > 1) return context.respondWithError("Invalid streak scale: `$streakScale`");

        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final allowedTypes = settings.allowedMathTypes.get() ?? Math.defaultTypes;
        final math = newFormula(allowedTypes: allowedTypes, currentStreakScale: streakScale);
        settings.currentMath.set(math);
        settings.lastMath.set(DateTime.now());
        await context.respond(MessageBuilder(embeds: [await math.toEmbed(context.member!, null)]));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("resetmath", "Math", "Reset the current math formula.", (T context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        settings.currentMath.delete();
        settings.lastMath.set(DateTime.now());
        await context.respond(MessageBuilder(content: "Math formula cleared."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("mathanswer", "Math", "Reset the current math formula.", (T context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final math = settings.currentMath.get();
        if (math == null) return context.respondWithError("No math formula found.");
        await context.respond(MessageBuilder(content: "$math = ${math.result}"));
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand("setmathtypes", "Math", "Set the current allowed math types for the server.", (T context, StringList values) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final allowed = Math.registry.keys.toList();
        final data = values.validate(allowed);
        settings.allowedMathTypes.set(data);
        await context.respond(MessageBuilder(content: "Set math types to **${data.length}** values:\n${data.join(", ").toDiscordCodeBlock()}\n-# **${values.invalid(allowed)}** types invalid"));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("mathtypes", "Math", "Set the current allowed math types for the server.", (T context) async {
        if (await context.assureGuild() == false) return;
        final current = context.guild != null ? Calebh101BotServerSettings(store, context.guild!.id).allowedMathTypes.get() : null;
        final all = Math.registry.keys.toList();

        await context.respond(MessageBuilder(content: [
          if (current != null) "Enabled types: ${current.join(", ").toDiscordCodeString()}",
          "All types: ${all.join(", ").toDiscordCodeString()}",
        ].join("\n")));
      }),
      BotCommand("mathsymbol", "Math", "Print a math symbol.", (T context, Symbol symbol) async {
        await context.respond(MessageBuilder(content: symbol.symbol.toDiscordCodeBlock()));
      }),
      BotCommand("mathstreak", "Math", "Print a math symbol.", (T context, [User? user]) async {
        if (await context.assureGuild() == false) return;
        user ??= context.user;

        final settings = Calebh101BotUserPerServerSettings(store, context.guild!.id, user.id);
        final streak = settings.mathStreak.get() ?? 0;

        await context.respond(MessageBuilder(content: "Current math streak for ${await memberFromUserToString(user, client: context.client, guild: context.guild)}: **$streak**"));
      }),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) => client.onMessageCreate.listen((event) async {
      if (event.guildId == null) return;
      final settings = Calebh101BotServerSettings(store, event.guildId!);
      if (settings.mathChannel.get() == null || settings.mathChannel.get() != event.message.channelId) return;

      final last = settings.lastMath.get();
      if (last != null && DateTime.now().difference(last).inMilliseconds < 1000) return;

      final userSettings = Calebh101BotUserPerServerSettings(store, event.guildId!, event.message.author.id);
      final streak = userSettings.mathStreak.get() ?? 0;

      final math = settings.currentMath.get();
      if (math == null) return;

      final int? number = int.tryParse(event.message.content.trim());
      if (number == null) return;
      final success = math.result == number;

      if (success) {
        final allowedTypes = settings.allowedMathTypes.get() ?? Math.defaultTypes;
        final math = newFormula(allowedTypes: allowedTypes, currentStreakScale: getCurrentStreakScale(streak));

        settings.currentMath.set(math);
        settings.lastMath.set(DateTime.now());
        userSettings.mathStreak.set(streak + 1);

        await event.message.react(ReactionBuilder(name: "✅", id: null));
        await event.message.channel.sendMessage(MessageBuilder(embeds: [await math.toEmbed(await event.member!.get(), streak + 1)]));
      } else {
        userSettings.mathStreak.set(0);
        await event.message.react(ReactionBuilder(name: "❌", id: null));
      }
    }));
  }

  Math newFormula({required List<String> allowedTypes, required double currentStreakScale}) {
    final id = allowedTypes[Random().nextInt(allowedTypes.length)];

    // Each ID you defined above needs to be added as a case here.
    // When making cases, make sure to make numbers reasonable.
    // Things like times 0, divided by 1, times 93, are not reasonable.

    switch (id) {
      case "multdiv":
      case "addsubtract":
        final allowed = id == "addsubtract" ? [Symbol.add, Symbol.subtract] : [Symbol.multiply, Symbol.divide];
        final symbol = allowed[Random().nextInt(allowed.length)];

        late final int a;
        late final int b;
        late final int r;

        switch (symbol) {
          case Symbol.add:
            a = Random().nextInt(50) + 1;
            b = Random().nextInt(50) + 1;
            r = a + b;
            break;
          case Symbol.subtract:
            a = Random().nextInt(100) + 1;
            b = Random().nextInt(a) + 1;
            r = a - b;
            break;
          case Symbol.multiply:
            if (currentStreakScale < 0.3) {
              a = Random().nextInt(20) + 1;
              b = Random().nextInt(6) + 2;
            } else {
              a = Random().nextInt(30) + 1;
              b = Random().nextInt(6) + 2;
            }

            r = a * b;
            break;
          case Symbol.divide:
            b = Random().nextInt(5) + 2;
            r = Random().nextInt(10) + 1;
            a = r * b;
            break;
        }

        return id == "multdiv" ? MultDivMath(a: a, b: b, result: r, symbol: symbol) : AddSubtractMath(a: a, b: b, result: r, symbol: symbol);
      case "exponent":
        final int a = Random().nextInt(9) + 2;
        late final int b;

        if (currentStreakScale < 0.25) {
          b = 2;
        } else if (currentStreakScale < 0.5) {
          b = Random().nextInt(2) + 2;
        } else {
          b = Random().nextInt(3) + 2;
        }

        return ExponentMath(a: a, b: b, result: pow(a, b).toInt());
    }

    throw UnimplementedError("Invalid math ID: $id");
  }
}

/// Extend this class to add a new math plugin.
/// Make sure to register it in [MathPlugin.onRegister].
abstract class Math {
  static const List<String> defaultTypes = ["addsubtract", "multdiv"];
  final int result;
  final String id;

  Math({required this.result, required this.id});
  Map toJson();

  Map _toJson<T extends Math>(Map<String, dynamic> Function(T instance) toJson) {
    return {
      ...toJson(this as T),
      "id": id,
    };
  }

  /// Override this if you need a complex embed.
  FutureOr<EmbedBuilder> toEmbed(Member member, int? streak) async => EmbedBuilder(
    title: "$this",
    color: await getColor(member),
    footer: streak != null ? EmbedFooterBuilder(text: "Streak: $streak") : null,
  );

  factory Math.fromJson(Map input) {
    String id = input["id"] ?? "simple";
    return registry[id]?.call(input) ?? (throw UnimplementedError("Invalid math ID: $id"));
  }

  static void register(String id, {required Math Function(Map input) fromJson}) {
    registry[id] = fromJson;
  }

  static Map<String, Math Function(Map input)> registry = {};
}

@JsonSerializable(anyMap: true)
class AddSubtractMath extends Math {
  final int a;
  final int b;
  final Symbol symbol;

  AddSubtractMath({required this.a, required this.b, required super.result, required this.symbol}) : super(id: "addsubtract");
  factory AddSubtractMath.fromJson(Map input) => _$AddSubtractMathFromJson(input);
  @override Map toJson() => _toJson(_$AddSubtractMathToJson);

  @override
  String toString() {
    return "$a ${symbol.symbol} $b";
  }
}

@JsonSerializable(anyMap: true)
class MultDivMath extends Math {
  final int a;
  final int b;
  final Symbol symbol;

  MultDivMath({required this.a, required this.b, required super.result, required this.symbol}) : super(id: "multdiv");
  factory MultDivMath.fromJson(Map input) => _$MultDivMathFromJson(input);
  @override Map toJson() => _toJson(_$MultDivMathToJson);

  @override
  String toString() {
    return "$a ${symbol.symbol} $b";
  }
}

@JsonSerializable(anyMap: true)
class ExponentMath extends Math {
  final int a;
  final int b;

  ExponentMath({required this.a, required this.b, required super.result}) : super(id: "exponent");
  factory ExponentMath.fromJson(Map input) => _$ExponentMathFromJson(input);
  @override Map toJson() => _toJson(_$ExponentMathToJson);

  @override
  String toString() {
    return "$a${toSuperscript(b)}";
  }

  static String toSuperscript(int n) {
    const superscripts = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];
    return n.toString().split('').map((d) => superscripts[int.parse(d)]).join();
  }
}

enum Symbol {
  add,
  subtract,
  multiply,
  divide;

  String get symbol {
    return switch (this) {
      Symbol.add => "+",
      Symbol.subtract => "-",
      Symbol.multiply => "x",
      Symbol.divide => "/",
    };
  }
}