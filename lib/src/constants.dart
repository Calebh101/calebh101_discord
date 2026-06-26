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

final x = ReactionBuilder(name: "❌", id: null);
final checkmark = ReactionBuilder(name: "✅", id: null);

final List<String> npcNameOptions1 = [
  "Sleepy",
  "Angry",
  "Happy",
  "Sneaky",
  "Mighty",
  "Tiny",
  "Fuzzy",
  "Wobbly",
  "Epic",
  "Turbo",
  "Shadow",
  "Golden",
  "Silver",
  "Crimson",
  "Frozen",
  "Stormy",
  "Cosmic",
  "Lucky",
  "Wild",
  "Ancient",
  "Brave",
  "Clever",
  "Dizzy",
  "Electric",
  "Fluffy",
  "Glowing",
  "Grumpy",
  "Hyper",
  "Jolly",
  "Mystic",
  "Nimble",
  "Rapid",
  "Rusty",
  "Shiny",
  "Silent",
  "Spicy",
  "Swift",
  "Thunder",
  "Velvet",
  "Wicked",
  "Zen",
];

final List<String> npcNameOptions2 = [
  "Gorilla",
  "Dragon",
  "Phoenix",
  "Tiger",
  "Wolf",
  "Bear",
  "Otter",
  "Panda",
  "Falcon",
  "Hawk",
  "Raven",
  "Shark",
  "Kraken",
  "Mammoth",
  "Badger",
  "Buffalo",
  "Cobra",
  "Jaguar",
  "Lynx",
  "Moose",
  "Penguin",
  "Rabbit",
  "Turtle",
  "Viper",
  "Yak",
  "Zombie",
  "Wizard",
  "Knight",
  "Samurai",
  "Ninja",
  "Pirate",
  "Robot",
  "Goblin",
  "Troll",
  "Wizard",
  "Warden",
  "Specter",
  "Titan",
  "Golem",
  "Nomad",
  "Bandit",
];