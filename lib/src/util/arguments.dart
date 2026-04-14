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
      final result = GreedyString(value.remaining);
      value.index = value.end;
      return result;
    }));
  }
}

BotConverter durationConverter() {
  return BotConverter("duration", (_) => Converter<Duration>((value, context) {
    final text = value.getQuotedWord();

    final regex = RegExp(
      r'(?:(\d+)y)?(?:(\d+)mo)?(?:(\d+)w)?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?',
    );

    final match = regex.firstMatch(text);
    if (match == null) return null;

    return Duration(
      days: (int.tryParse(match[1] ?? '') ?? 0) * 365  // years
        + (int.tryParse(match[2] ?? '') ?? 0) * 30     // months ~
        + (int.tryParse(match[3] ?? '') ?? 0) * 7      // weeks
        + (int.tryParse(match[4] ?? '') ?? 0),         // days
      hours: int.tryParse(match[5] ?? '') ?? 0,
      minutes: int.tryParse(match[6] ?? '') ?? 0,
      seconds: int.tryParse(match[7] ?? '') ?? 0,
    );
  }));
}