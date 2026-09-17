import 'package:nyxx/nyxx.dart';

mixin CommandsPlugin {
  List<ApplicationCommandBuilder> get builders;

  Future<void> register(NyxxGateway client, {Snowflake? guildId}) async {
    final commands = guildId != null ? client.commands[guildId] : client.commands;
    await client.commands.bulkOverride(builders);
  }
}