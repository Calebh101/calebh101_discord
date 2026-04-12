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

@JsonSerializable(anyMap: true)
class Math {
  final int a;
  final int b;
  final int result;
  final Operand operand;

  Math({required this.a, required this.b, required this.result, required this.operand});
  factory Math.fromJson(Map input) => _$MathFromJson(input);
  Map toJson() => _$MathToJson(this);
}

enum Operand {
  add,
  subtract,
  multiply,
  divide
}