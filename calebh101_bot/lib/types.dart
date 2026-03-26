import 'package:json_annotation/json_annotation.dart';

part 'types.g.dart';

@JsonSerializable(anyMap: true)
class XPLevel {
  final int roleId;
  int requiredXp;

  XPLevel({required this.requiredXp, required this.roleId});
  factory XPLevel.fromJson(Map input) => _$XPLevelFromJson(input);
  Map toJson() => _$XPLevelToJson(this);
}