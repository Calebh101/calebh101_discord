import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class Calebh101Bet extends BetPlugin<double> {
  @override
  void add<C extends ChatContext>(C context, KVStore store, User user, Guild guild, double amount) {
    final settings = Calebh101BotUserPerServerSettings(store, guild.id, user.id);
    final current = settings.xp.get() ?? 0;
    settings.xp.set(current + amount);
  }

  @override
  double get<C extends ChatContext>(C context, KVStore store, User user, Guild guild) {
    final settings = Calebh101BotUserPerServerSettings(store, guild.id, user.id);
    final current = settings.xp.get() ?? 0;
    return current;
  }
}