import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class ModMailPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "modmail", version: Version.parse("1.0.0A"), description: "Contact mods easily.");

  static final List<String> modmailRules = [
    "This feature is only for moderation matters. No support or general questions that can be answered by non-mods.",
    "Be respectful in your interactions.",
    "We do not moderate things that happen outside of this server. Don't report anything from other servers/platforms. This also applies to DMs unless the user is scamming or soliciting, or is otherwise related to this server.",
  ];

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    context.clients.run((client) {
      client.onInteractionCreate.listen((event) async {
        final interaction = event.interaction;
        final member = interaction.member;
        final user = interaction.user ?? member?.user;

        if (user == null) return;
        if (isIgnored(context.store, user.id)) return;

        final guild = await interaction.guild?.get();
        if (guild == null) return;

        final settings = ModMailServerSettings(context.store, guild.id);
        final blocked = settings.modmailBlocked.get().contains(user.id);

        if (interaction is MessageComponentInteraction && interaction.data.customId == "modmail_ticket_open") {
          Logger.print("ModMail", "Opening dialog for user ${user.username} (${user.id}) and guild ${guild.id}");

          if (blocked) {
            await interaction.respond(MessageBuilder(
              content: "You are currently blocked from ModMail.",
              flags: MessageFlags.ephemeral,
            ));

            return;
          }

          await interaction.respondModal(
            ModalBuilder(
              customId: 'modmail_modal',
              title: 'Open ModMail Ticket',
              components: [
                TextDisplayComponentBuilder(content: "Before you open your ticket, make sure it follows our rules! Tickets not following the ModMail rules will be closed immediately, and if repeated, you will be blocked from opening new tickets.\n\n${modmailRules.map((x) => "- $x").join("\n")}\n\nUse `Cancel` to stop, and `Submit` to open your ticket."),
              ],
            ),
          );
        }

        if (interaction is ModalSubmitInteraction && interaction.data.customId == "modmail_modal") {
          Logger.print("ModMail", "Opening ticket for user ${user.username} (${user.id}) and guild ${guild.id}");

          if (blocked) {
            await interaction.respond(MessageBuilder(
              content: "You are currently blocked from ModMail.",
              flags: MessageFlags.ephemeral,
            ));

            return;
          }

          final id = settings.nextModmailId();
          late GuildTextChannel channel;

          try {
            channel = await client.channels.get(settings.modmailChannel.get()!) as GuildTextChannel;
          } catch (e) {
            Logger.warn("ModMail", "Unable to get ModMail channel for guild ${guild.id} and channel ID ${settings.modmailChannel.get()} (user=${user.id}): $e");
            await interaction.respond(MessageBuilder(content: "We couldn't create a ModMail ticket.", flags: MessageFlags.ephemeral));
            return;
          }

          final thread = await channel.createThread(ThreadBuilder.privateThread(
            name: "❌ #$id: ${member?.nick ?? user.globalName ?? user.username} (${user.username})",
            invitable: false,
          )) as PrivateThread;

          await thread.addThreadMember(user.id);

          await thread.sendMessage(MessageBuilder(
            embeds: [
              EmbedBuilder(
                title: "ModMail Thread #$id",
                description: "**Hey there, ${user.mention}! This is your ModMail thread!**\nYou may now send any messages and add any attachments that you need to.\nA mod will be with you shortly!",
                color: await getColor(member),
                timestamp: DateTime.now().toUtc(),
              ),
            ],
          ));

          await interaction.respond(MessageBuilder(
            flags: MessageFlags.ephemeral,
            content: "ModMail ticket **#$id** for ${user.mention} opened.",
          ));
        }
      });
    });
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("modmailchannel", "ModMail", "Get the current ModMail channel.", (T context) async {
        final settings = ModMailServerSettings(store, context.guildId!);
        final id = settings.modmailChannel.get();

        await context.respond(MessageBuilder(
          content: id?.value.toChannel() ?? "Not set.",
        ));
      }, needsGuild: true),
      BotCommand("setmodmailchannel", "ModMail", "Set the current ModMail channel.", (T context, [GuildTextChannel? channel]) async {
        final settings = ModMailServerSettings(store, context.guildId!);
        settings.modmailChannel.set(channel?.id);

        await context.respond(MessageBuilder(
          content: channel?.toMention() ?? "Unset.",
        ));
      }, needsGuild: true, permissionsRequired: .admin),
      BotCommand("modmailinfo", "ModMail", "Get the current ModMail info as an embed.", (T context) async {
        final settings = ModMailServerSettings(store, context.guildId!);
        final channelId = settings.modmailChannel.get();

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            title: "ModMail Info for ${context.guild?.name}",
            description: """
This thing is used for when you need to contact mods in private!
Reminder: **do not DM mods** if this is an option.

## ModMail Rules
${modmailRules.map((x) => "- $x").join("\n")}

Click the button below to create a new ticket!
**If you misuse this, you will be blocked from creating tickets.**
""".trim(),
            color: await getColor(context.member),
            url: channelId != null && context.channel.id != channelId ? discordLink(context.guildId, channelId) : null,
          ),
        ], components: [
          if (channelId != null)
          ActionRowBuilder(components: [
              ButtonBuilder.primary(
              label: "Open Ticket",
              customId: "modmail_ticket_open",
            ),
          ]),
        ]));
      }, needsGuild: true),
      BotCommand("modmailresolve", "ModMail", "Resolve a ModMail thread.", (T context) async {
        final settings = ModMailServerSettings(store, context.guildId!);
        final channel = context.channel;

        if (channel is! PrivateThread || channel.parentId == null || channel.parentId != settings.modmailChannel.get()) {
          return context.respondWithError("This thread isn't a ModMail thread.");
        }

        final id = int.tryParse(channel.name.split(":").firstOrNull?.split("#").lastOrNull ?? "");
        if (id == null) return context.respondWithError("This thread doesn't have a ModMail ID!");

        await channel.update(ThreadUpdateBuilder(name: channel.name.replaceFirst("❌", "✅"), isLocked: true, isArchived: true));
        await context.respond(MessageBuilder(content: "ModMail ticket **#$id** resolved."));
      }, permissionsRequired: .admin, needsGuild: true, aliases: ["mmresolve", "resolvemm", "resolvemodmail"]),
    ];
  }
}

class ModMailServerSettings extends ServerSettings {
  ModMailServerSettings(super.store, super.id);

  SettingsObject<Snowflake> get modmailChannel => SettingsObject.snowflake(this, "modmailChannel");
  SettingsObjectNotNull<int> get modmailId => SettingsObjectNotNull(this, "modmailId", defaultFunction: () => 0);
  SettingsObjectNotNull<List<Snowflake>> get modmailBlocked => SettingsObject.listSnowflake(this, "modmailBlocked");

  int nextModmailId() {
    modmailId.set(modmailId.get() + 1);
    return modmailId.get();
  }
}

extension FlagListExtension<T extends Flags<T>> on Iterable<Flags<T>> {
  Flags<T> toFlags() {
    return Flags<T>(
      fold(0, (value, flag) => value | flag.value),
    );
  }
}