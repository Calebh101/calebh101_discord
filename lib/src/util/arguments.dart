import 'package:calebh101_discord/calebh101_discord.dart';

class StringList {
  final List<String> data;
  const StringList(this.data);

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

class GreedyString {
  final String data;
  const GreedyString(this.data);

  @override
  String toString() {
    return data;
  }

  static BotCommand converter() {
    return BotCommand.converter((_) => Converter<GreedyString>((value, context) {
      if (value.remaining.trim().isEmpty) return null;
      final result = GreedyString(value.remaining.trim());
      value.index = value.end;
      return result;
    }));
  }
}

BotConverter durationConverter() {
  return BotConverter("duration", (_) => Converter<Duration>((value, context) {
    final text = value.getQuotedWord();
    return parseDuration(text);
  }));
}