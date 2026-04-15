// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remind.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Reminder _$ReminderFromJson(Map json) => Reminder(
      name: json['name'] as String,
      time: DateTime.parse(json['time'] as String),
      channelId: (json['channelId'] as num?)?.toInt(),
      id: (json['id'] as num).toInt(),
      clientId: (json['clientId'] as num).toInt(),
      sentMessageId: (json['sentMessageId'] as num).toInt(),
      sentChannelId: (json['sentChannelId'] as num).toInt(),
      sentGuildId: (json['sentGuildId'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ReminderToJson(Reminder instance) => <String, dynamic>{
      'name': instance.name,
      'time': instance.time.toIso8601String(),
      'channelId': instance.channelId,
      'id': instance.id,
      'clientId': instance.clientId,
      'sentMessageId': instance.sentMessageId,
      'sentChannelId': instance.sentChannelId,
      'sentGuildId': instance.sentGuildId,
    };
