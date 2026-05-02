// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restriction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RestrictionData _$RestrictionDataFromJson(Map json) => RestrictionData(
  type: $enumDecode(_$RestrictionEnumMap, json['type']),
  data: (json['data'] as num).toInt(),
);

Map<String, dynamic> _$RestrictionDataToJson(RestrictionData instance) =>
    <String, dynamic>{
      'type': _$RestrictionEnumMap[instance.type]!,
      'data': instance.data,
    };

const _$RestrictionEnumMap = {
  Restriction.user: 'user',
  Restriction.role: 'role',
  Restriction.channel: 'channel',
  Restriction.notUser: 'notUser',
  Restriction.notRole: 'notRole',
  Restriction.notChannel: 'notChannel',
};

CommandRestrictions _$CommandRestrictionsFromJson(Map json) =>
    CommandRestrictions(
      command: json['command'] as String,
      data: (json['data'] as List<dynamic>)
          .map((e) => RestrictionData.fromJson(e as Map))
          .toList(),
      combination: $enumDecode(
        _$RestrictionCombinationEnumMap,
        json['combination'],
      ),
    );

Map<String, dynamic> _$CommandRestrictionsToJson(
  CommandRestrictions instance,
) => <String, dynamic>{
  'command': instance.command,
  'data': instance.data,
  'combination': _$RestrictionCombinationEnumMap[instance.combination]!,
};

const _$RestrictionCombinationEnumMap = {
  RestrictionCombination.and: 'and',
  RestrictionCombination.or: 'or',
};
