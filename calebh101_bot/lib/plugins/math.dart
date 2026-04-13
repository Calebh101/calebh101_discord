import 'dart:async';
import 'dart:math';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_bot/types.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class MathPlugin extends BotPlugin {
  MathPlugin() : super(id: "math", version: Version.parse("1.0.0A"));

  @override FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("setmathchannel", "Math", "Set the channel for mathing. Pass without a value to disable.", (ChatContext context, [GuildTextChannel? channel]) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        settings.mathChannel.set(channel?.id);

        await context.respond(MessageBuilder(
          content: "Math channel ${channel != null ? "set to ${channel.toMention()}" : "**reset**"}!",
        ));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("mathchannel", "Math", "Get the current math channel.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final id = settings.mathChannel.get();

        await context.respond(MessageBuilder(
          content: "Math channel ${id != null ? "is currently set to ${id.value.toChannel()}" : "not set"}."
        ));
      }),
      BotCommand("mathmultdiv", "Math", "Enable/disable multiplication and division.", (ChatContext context, bool value) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        settings.mathMultDiv.set(value);
        await context.respond(MessageBuilder(content: "Set to **${value ? "allow" : "not allow"}** multiplication/division."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("math", "Math", "Print the current math formula, or make a new one.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final math = settings.currentMath.get() ?? newFormula(allowMultiplicationDivision: settings.mathMultDiv.get() ?? false);
        settings.currentMath.set(math);
        await context.respond(MessageBuilder(embeds: [await math.toEmbed(context.member!)]));
      }),
      BotCommand("newmath", "Math", "Print a new math formula.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final math = newFormula(allowMultiplicationDivision: settings.mathMultDiv.get() ?? false);
        settings.currentMath.set(math);
        await context.respond(MessageBuilder(embeds: [await math.toEmbed(context.member!)]));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("resetmath", "Math", "Reset the current math formula.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        settings.currentMath.delete();
        await context.respond(MessageBuilder(content: "Math formula cleared."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("mathanswer", "Math", "Reset the current math formula.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final math = settings.currentMath.get();
        if (math == null) return context.respondWithError("No math formula found.");
        await context.respond(MessageBuilder(content: "$math = ${math.result}"));
      }, permissionsRequired: BotCommandPermissions.owner),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) => client.onMessageCreate.listen((event) async {
      if (event.guildId == null) return;
      final settings = Calebh101BotServerSettings(store, event.guildId!);
      if (settings.mathChannel.get() == null || settings.mathChannel.get() != event.message.channelId) return;

      final math = settings.currentMath.get();
      if (math == null) return;

      final int? number = int.tryParse(event.message.content.trim());
      if (number == null) return;
      final success = math.result == number;

      if (success) {
        await event.message.react(ReactionBuilder(name: "✅", id: null));
        final math = newFormula(allowMultiplicationDivision: settings.mathMultDiv.get() ?? false);
        settings.currentMath.set(math);
        await event.message.channel.sendMessage(MessageBuilder(embeds: [await math.toEmbed(await event.member!.get())]));
      } else {
        await event.message.react(ReactionBuilder(name: "❌", id: null));
      }
    }));
  }

  Math newFormula({required bool allowMultiplicationDivision}) {
    final allowed = [Operand.add, Operand.subtract, if (allowMultiplicationDivision) ...[Operand.multiply, Operand.divide]];
    final operand = allowed[Random().nextInt(allowed.length)];

    late final int a;
    late final int b;
    late final int r;

    switch (operand) {
      case Operand.add:
        a = Random().nextInt(50) + 1;
        b = Random().nextInt(50) + 1;
        r = a + b;
        break;
      case Operand.subtract:
        a = Random().nextInt(100) + 1;
        b = Random().nextInt(a) + 1;
        r = a - b;
        break;
      case Operand.multiply:
        a = Random().nextInt(30) + 1;
        b = Random().nextInt(6) + 2;
        r = a * b;
        break;
      case Operand.divide:
        b = Random().nextInt(5) + 2;
        r = Random().nextInt(10) + 1;
        a = r * b;
        break;
    }

    return Math(a: a, b: b, result: r, operand: operand);
  }
}