import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';

BotCommand fart() => BotCommand.command("fart", "Fart.", (ChatContext context, [int amount = 1]) async {
  if (amount != 1 && !isOwner(id: context.user.id)) return context.respondWithError("You cannot control the amount.");
  if (amount < 1) return context.respondWithError("Invalid amount: $amount");

  int rn(int min, int max) {
    // Inclusive
    return Random().nextInt(max - min + 1) + min;
  }

  String random(int min, int max, String phrase) {
    return phrase * rn(min, max);
  }

  T ro<T>(List<T> options) {
    return options[Random().nextInt(options.length)];
  }

  String maybe(String option, [int factor = 1]) {
    return ro([option, ...List.generate(factor, (_) => "")]);
  }

  final List<String Function()> farts = [
    () => "P${random(2, 20, "o")}t",
    () => "P${random(4, 40, "r")}t",
    () => "F${random(1, 5, "a")}rt",
    () => "Th${List.generate(rn(4, 20), (_) => random(1, 4, ro(["h", "t"]))).join("")}",
    () => "B${maybe("h")}l${random(6, 24, "a")}${maybe("h")}n${maybe("h")}k",
    () => "Squ${random(1, 2, ro(["i", "e"]))}rk",
  ];

  await context.respond(MessageBuilder(
    content: List.generate(amount, (_) => ro(farts).call()).join("\n"),
  ));
}, CommandAttributes(category: "Fun"));