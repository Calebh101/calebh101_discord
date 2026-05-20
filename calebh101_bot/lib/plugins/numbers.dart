import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:math_expressions/math_expressions.dart';

class NumbersPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "numbers", version: Version.parse("1.0.0A"), description: "Utilities for numbers.");
  static ContextModel model = ContextModel();

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyQuotedList.converter(),
      numConverter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("number", "Numbers", "Get numbers from a list.", (T context, GreedyQuotedList input) async {
        final converter = numConverter().callback.call(context.commands)!;
        final numbers = (await Future.wait(input.input.map((x) async => await converter.convert.call(StringView(x), context)))).toList();
        final data = Map.fromEntries(numbers.mapIndexed((i, x) => MapEntry(x, input.input[i].trim())));

        await context.respond(MessageBuilder(
          content: data.entries.map((x) {
            final input = x.key;
            if (input == null) return "${x.value.toDiscordCodeBlock()}\nNo number was able to be parsed.";
            return "${"${x.value} => $input".toDiscordCodeBlock()}\nType: ${input.runtimeType.toDiscordCodeString()}\nState: ${(input > 0 ? "positive" : (input < 0 ? "negative" : "zero")).toUpperCase().toDiscordCodeString()}";
          }).join("\n\n"),
        ));
      }),

      // Taken from CorpNewt's CorpBot.py
      BotCommand("math", "Numbers", "Calculate an expression.", (T context, GreedyString input) async {
        final RegExp hex = RegExp(r'(?:0x|#)[0-9a-fA-F]+');
        final formula = input.data;

        String preprocessLine(String line) {
          final buffer = StringBuffer();
          int lastEnd = 0;

          for (final match in hex.allMatches(line)) {
            final start = match.start;
            final end = match.end;
            final hexStr = match.group(0)!.replaceFirst('#', '0x');
            final intValue = int.parse(hexStr, radix: 16).toString();

            buffer.write(line.substring(lastEnd, start));
            buffer.write(intValue);
            lastEnd = end;
          }

          buffer.write(line.substring(lastEnd));
          return buffer.toString();
        }

        String evaluateLine(String line) {
          final parser = ShuntingYardParser();
          final exp = parser.parse(line);
          final result = RealEvaluator(model).evaluate(exp);

          if (result == result.truncateToDouble()) return result.toInt().toString();
          return result.toString();
        }

        final parserLines = formula
          .replaceAll(';', '\n')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

        if (parserLines.isEmpty) {
          return context.respondWithError("No formula provided.");
        }

        final cleanLines = <String>[];
        String lastResult = '';

        try {
          for (var line in parserLines) {
            final processedLine = preprocessLine(line);
            final result = evaluateLine(processedLine);
            lastResult = result;

            final displayLine = line
                .split(RegExp(r'\s+'))
                .join(' ')
                .replaceAll('`', '')
                .replaceAll('\\', '');

            cleanLines.add('$displayLine = $result');
          }
        } catch (e) {
          return context.respondWithError(
            "Invalid formula.\n"
            '```\n${e.toString().replaceAll('`', 'back tick')}\n```\n'
            'This function uses [`math_expressions`](https://pub.dev/packages/math_expressions).\n\n'
            '**Additional syntax supported**\n${[
              'Newlines or semicolons (`;`) separate lines passed to the parser',
              '`0x` or `#` prefixes denote hexadecimal values',
              '`&` for bitwise AND',
              '`|` for bitwise OR',
              '`^` for bitwise XOR',
              '`~` for bitwise NOT',
              '`<<` bit shift left',
              '`>>` bit shift right',
              '`sqrt()` square root',
            ].map((x) => "- $x").join("\n")}'
          );
        }

        var output = cleanLines.join('\n');
        final totalLen = output.length + lastResult.length + 8;
        final overAmount = totalLen - 2000;

        if (overAmount > 0) {
          output = '...${output.substring(overAmount + 3)}';
        }

        await context.respond(MessageBuilder(content: '```\n$output\n```'));
      }, aliases: ["calc", "calculate"]),

      BotCommand("var", "Numbers", "Set a variable.", (T context, String name, num input) async {
        name = name.trim();
        final isAlpha = RegExp(r'^[a-zA-Z]+$').hasMatch(name);
        if (name.isEmpty || !isAlpha) return context.respondWithError("Invalid variable name.");

        model.bindVariable(Variable(name), Number(input));
        await context.respond(MessageBuilder(content: "$name = $input (${input.runtimeType})".toDiscordCodeBlock()));
      }, aliases: ["setvar"]),
    ];
  }
}