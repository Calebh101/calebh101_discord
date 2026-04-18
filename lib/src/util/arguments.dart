import 'package:calebh101_discord/calebh101_discord.dart';

abstract class ConverterType {
  const ConverterType();

  String get name;
  String get info;

  static ConverterType? lookup<T>(T input) {
    if (input is ConverterType) return input;
    return null;
  }
}

extension GetConverterType on Object? {
  ConverterType? lookupConverterType() {
    return ConverterType.lookup(this);
  }
}

class StringList extends ConverterType {
  final List<String> data;
  const StringList(this.data);

  @override
  String get name => "Item List";

  @override
  String get info => "A comma-separated value list.";

  List<String> validate(List<String> allowed) {
    return data.where((x) => allowed.contains(x)).toList();
  }

  int invalid(List<String> allowed) {
    return data.where((x) => !allowed.contains(x)).length;
  }

  @override
  String toString() {
    return "$data";
  }

  static BotConverter converter() {
    return BotConverter("StringList", (_) => Converter<StringList>((value, context) {
      final data = value.getQuotedWord().split(",").map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      if (data.isNotEmpty) return StringList(data);
      return null;
    }));
  }
}

class GreedyStringList extends StringList {
  const GreedyStringList(super.data);

  static BotConverter converter() {
    return BotConverter("GreedyStringList", (_) => Converter<GreedyStringList>((value, context) {
      final data = value.remaining.split(",").map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      value.index = value.end;
      if (data.isNotEmpty) return GreedyStringList(data);
      return null;
    }));
  }
}

class GreedyString extends ConverterType {
  final String data;
  const GreedyString(this.data);

  @override
  String get name => "Greedy String";

  @override
  String get info => "Takes up the remaining input in the command as one string. Does not need quotes.";

  @override
  String toString() {
    return data;
  }

  static BotConverter converter() {
    return BotConverter("GreedyString", (_) => Converter<GreedyString>((value, context) {
      if (value.remaining.trim().isEmpty) return null;
      final result = GreedyString(trimMatchingQuotes(value.remaining.trim()));
      value.index = value.end;
      return result;
    }));
  }

  static String trimMatchingQuotes(String input) {
    if (input.length >= 2) {
      if ((input.startsWith('"') && input.endsWith('"')) || (input.startsWith("'") && input.endsWith("'"))) {
        return input.substring(1, input.length - 1);
      }
    }

    return input;
  }
}

BotConverter durationConverter() {
  return BotConverter("duration", (_) => Converter<Duration>((value, context) {
    final text = value.getQuotedWord();
    return parseDuration(text);
  }));
}