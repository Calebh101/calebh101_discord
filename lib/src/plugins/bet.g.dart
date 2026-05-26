// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bet.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Bet _$BetFromJson(Map json) => Bet(
  title: json['title'] as String,
  description: json['description'] as String?,
  id: (json['id'] as num).toInt(),
  choices: Map<String, num>.from(json['choices'] as Map),
  bets: (json['bets'] as Map).map(
    (k, e) => MapEntry(int.parse(k as String), e as String),
  ),
  locked: json['locked'] as bool? ?? false,
);

Map<String, dynamic> _$BetToJson(Bet instance) => <String, dynamic>{
  'title': instance.title,
  'description': instance.description,
  'id': instance.id,
  'choices': instance.choices,
  'bets': instance.bets.map((k, e) => MapEntry(k.toString(), e)),
  'locked': instance.locked,
};
