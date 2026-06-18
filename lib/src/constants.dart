import 'package:calebh101_discord/calebh101_discord.dart';

const defaultPrefix = "!";
const enableKill = true;

typedef DefinedUser = ({String name, String username, Snowflake id});
typedef DefinedServer = ({Snowflake id, Uri? invite});

const DefinedUser calebh101 = (
  name: "Caleb",
  username: "calebh101",
  id: Snowflake(1225628518021599264),
);

final DefinedServer calebh101Server = (
  id: Snowflake(1300649617381396480),
  invite: Uri.parse("https://discord.gg/gbZyPuqZ6n"),
);

final Map<String? Function(MessageCreateEvent event), num> pingPhrases = {
  (_) => "WHAT'S ALL THAT NOISE??": 50,
  (_) => "Ow!": 100,
  (_) => "Pong!": 100,
  (_) => "Hey there!": 100,
  (e) => "Hi there, <@${e.member!.id}>!": 100,
  (_) => "AGHGHGHGHGHGHGHGHGHGHGHGHGHGHGHHGHG": 5,
};

const maxUniqueReactionsPerMessage = 20;

final checkmark = ReactionBuilder(name: "✅", id: null);