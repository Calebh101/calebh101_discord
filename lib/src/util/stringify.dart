import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

FutureOr<String?> memberToString(Member? member, {bool detailed = false, required NyxxGateway client}) async {
  if (member == null) return null;
  final user = member.user ?? await client.users[member.id].get();

  try {
    return [
      "**${member.nick ?? user.globalName ?? user.username}**",
      "(*${user.username}*)",
      if (detailed) "(`${member.id}`)",
    ].join(" ");
  } catch (e) {
    Logger.print("memberToString", "$e (member=${member.runtimeType}, user=${member.user.runtimeType}, nick=${member.nick}, id=${member.id}, detailed=$detailed)");
    return userToString(user);
  }
}

FutureOr<String?> memberFromUserToString(User? user, {bool detailed = false, required NyxxGateway client, required Guild? guild}) async {
  if (user == null) return null;
  final member = await userToMember(user, guild: guild);

  try {
    return [
      "**${member!.nick ?? user.globalName ?? user.username}**",
      "(*${user.username}*)",
      if (detailed) "(`${member.id}`)",
    ].join(" ");
  } catch (e) {
    Logger.print("memberToString", "$e (member=${member.runtimeType}, user=${member?.user.runtimeType}, nick=${member?.nick}, id=${member?.id}, detailed=$detailed)");
    return await userToString(user);
  }
}

FutureOr<String?> userToString(User? user, {bool detailed = false}) async {
  if (user == null) return null;

  try {
    return [
      "**${user.globalName ?? user.username}** (*${user.username}*)",
      if (detailed) "(`${user.id}`)",
    ].join(" ");
  } catch (_) {
    return null;
  }
}

FutureOr<String> userOrMemberToString(Member? member, User user, {bool detailed = false, required NyxxGateway client}) async {
  return await memberToString(member, detailed: detailed, client: client) ?? await userToString(user, detailed: detailed) ?? "`${user.id}`";
}

Future<String?> roleToString(Role? role) async {
  if (role == null) return null;
  return "**${role.name}**";
}

String formatLatency(Duration latency) {
  return "${(latency.inMicroseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(3)}ms";
}

extension ToMention on int {
  String toMention() {
    return "<@$this>";
  }

  String toRoleMention() {
    return "<@&$this>";
  }

  String toChannel() {
    return "<#$this>";
  }
}

extension RoleToMention on Role {
  String toMention() {
    return this.id.value.toRoleMention();
  }
}

extension UserToMention on User {
  String toMention() {
    return this.id.value.toMention();
  }
}

extension MemberToMention on Member {
  String toMention() {
    return this.id.value.toMention();
  }
}

extension ChannelToMention on Channel {
  String toMention() {
    return this.id.value.toChannel();
  }
}

extension ToDiscordCodeBlock on Object? {
  String toDiscordCodeBlock({String? language}) {
    final x = toString().trim();
    return "```${language != null && x.isNotEmpty ? language : ""}\n$x\n```";
  }

  String toDiscordCodeString() {
    return "`$this`";
  }
}

extension DiscordTimestamp on DateTime {
  String toDiscordTimestamp([String? flag]) {
    return "<t:${((toUtc().millisecondsSinceEpoch) / Duration.millisecondsPerSecond).floor()}${flag != null ? ":$flag" : ""}>";
  }

  /// Short time (e.g. `9:30 AM`)
  static const String shortTime = 't';

  /// Long time (e.g. `9:30:00 AM`)
  static const String longTime = 'T';

  /// Short date (e.g. `03/24/2026`)
  static const String shortDate = 'd';

  /// Long date (e.g. `March 24, 2026`)
  static const String longDate = 'D';

  /// Short date and time — default (e.g. `March 24, 2026 9:30 AM`)
  static const String shortDateTime = 'f';

  /// Long date and time (e.g. `Tuesday, March 24, 2026 9:30 AM`)
  static const String longDateTime = 'F';

  /// Relative time (e.g. `in 5 minutes` / `3 hours ago`)
  static const String relative = 'R';
}