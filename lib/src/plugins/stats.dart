import 'dart:async';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:system_info2/system_info2.dart';

class StatsPlugin extends BotPlugin {
  StatsPlugin() : super(id: "stats", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [
      aboutCommand(store),
      statusCommand(),
      pingCommand(),
    ];
  }

  BotCommand aboutCommand(KVStore? store) => BotCommand.command("about", "See stats about this bot.", (ChatContext context) async {
    final settings = store != null && context.guild != null ? ServerSettings(store, context.guild!.id) : null;
    final prefix = settings?.prefix.get() ?? defaultPrefix;

    await context.respond(MessageBuilder(
      content: [
        "**$globalBotName**: A bot that does something",
        "Version $botVersion by [Calebh101](<https://github.com/Calebh101>)",
        null,
        "Current prefix: `$prefix`",
        "To see all commands, run `help`.",
        null,
        [
          "${SysInfo.operatingSystemName} ${SysInfo.kernelArchitecture} ${SysInfo.operatingSystemVersion}".trim(),
          (() {
            final processor = SysInfo.cores.first;
            return "${processor.vendor} ${processor.name}".trim();
          }()),
          "Kernel: ${SysInfo.kernelName} ${SysInfo.kernelVersion} ${SysInfo.kernelArchitecture.name}"
        ].join("\n").trim().toDiscordCodeBlock(),
        null,
        "Built with [nyxx](<https://pub.dev/packages/nyxx>), running on Dart:",
        Platform.version.trim().toDiscordCodeBlock(),
        if (globalSupportServer != null) ...["For support: ${globalSupportServer!.invite}"],
      ].map((x) => x ?? "").join("\n"),
    ));
  }, CommandAttributes(category: "Bot"));

  BotCommand statusCommand() => BotCommand("status", "Bot", "See the bot's status.", (ChatContext context) async {
    const factor = 1024;
    final m = await context.respond(MessageBuilder(content: "Fetching status..."));
    Map<String, String> elements = {};

    final memory = await getMemory();
    final rss = ProcessInfo.currentRss;
    final maxRss = ProcessInfo.maxRss;
    final storage = await getStorage();

    String megabytes(num input) {
      return "${input ~/ (factor * factor)} MiB";
    }

    String gigabytes(num input) {
      return "${input ~/ (factor * factor * factor)} GiB";
    }

    elements["System"] = [
      "${SysInfo.operatingSystemName} ${SysInfo.kernelArchitecture} ${SysInfo.operatingSystemVersion} ${SysInfo.kernelVersion}".trim(),
      (() {
        final processor = SysInfo.cores.first;
        return "${processor.vendor} ${processor.name}".trim();
      }()),
      "Kernel: ${SysInfo.kernelName} ${SysInfo.kernelVersion} ${SysInfo.kernelArchitecture.name}",
      "Dart: ${Platform.version.trim()}",
    ].join("\n").trim();

    elements["Memory/Storage"] = [
      "Memory: ${gigabytes(memory.free)} Free / ${gigabytes(memory.total)},",
      "Memory for this process: ${megabytes(rss)} used (max since started: ${megabytes(maxRss)})",
      "Storage: ${gigabytes(storage.free)} Free / ${gigabytes(storage.total)}",
    ].join("\n").trim();

    elements["Machine"] = await getStatus() ?? "No machine-defined status found.";
    await context.updateMessage(m, MessageUpdateBuilder(content: elements.entries.map((x) => "### ${x.key}\n${x.value.toDiscordCodeBlock()}").join("\n")));
  });

  Future<({int free, int total})> getStorage() async {
    if (Platform.isMacOS || Platform.isLinux) {
      final result = await Process.run('df', ['-k', '/']);
      final parts = result.stdout.toString().trim().split('\n')[1].split(RegExp(r'\s+'));

      return (
        total: int.parse(parts[1]) * 1024,
        free: int.parse(parts[3]) * 1024,
      );
    } else if (Platform.isWindows) {
      final result = await Process.run('wmic', ['logicaldisk', 'where', 'DeviceID="C:"', 'get', 'Size,FreeSpace']);
      final parts = result.stdout.toString().trim().split('\n').last.trim().split(RegExp(r'\s+'));

      return (
        total: int.parse(parts[0]),
        free: int.parse(parts[1]),
      );
    } else {
      throw UnsupportedError('Unsupported OS: ${Platform.operatingSystem}');
    }
  }

  Future<({int free, int total})> getMemory() async {
    if (Platform.isMacOS) {
      final totalResult = await Process.run('sysctl', ['-n', 'hw.memsize']);
      final total = int.parse(totalResult.stdout.toString().trim());

      final vmResult = await Process.run('vm_stat', []);
      final lines = vmResult.stdout.toString().split('\n');
      final pageSize = 16384; // macOS default page size

      int getPages(String key) {
        final line = lines.firstWhere((l) => l.contains(key), orElse: () => '0');
        return int.tryParse(line.split(':').last.trim().replaceAll('.', '')) ?? 0;
      }

      final free = (getPages('Pages free') + getPages('Pages inactive')) * pageSize;
      return (total: total, free: free);
    } else {
      return (
        total: SysInfo.getTotalPhysicalMemory(),
        free: SysInfo.getAvailablePhysicalMemory(),
      );
    }
  }

  BotCommand pingCommand() => BotCommand.command(
    "ping", "Pong!",
    (ChatContext context) async {
      final latency = context.client.httpHandler.latency;
      final realLatency = context.client.httpHandler.realLatency;
      final gatewayLatency = context.client.gateway.latency;

      final Map<String, String> keys = {
        "HTTP latency": formatLatency(latency),
        "Real latency": formatLatency(realLatency),
        if (gatewayLatency.inMicroseconds > 0) "Gateway latency": formatLatency(gatewayLatency),
      };

      await context.respond(MessageBuilder(content: "<@${context.user.id}>, pong!\n\n${keys.entries.map((x) {
        return "> ${x.key}: **${x.value}**";
      }).join("\n")}"));
    },
    CommandAttributes(category: "Bot"),
  );
}