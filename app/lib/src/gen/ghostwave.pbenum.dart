// This is a generated file - do not edit.
//
// Generated from ghostwave.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class Error_Code extends $pb.ProtobufEnum {
  static const Error_Code NONE = Error_Code._(0, _omitEnumNames ? '' : 'NONE');
  static const Error_Code BAD_FRAME =
      Error_Code._(1, _omitEnumNames ? '' : 'BAD_FRAME');
  static const Error_Code BAD_VERSION =
      Error_Code._(2, _omitEnumNames ? '' : 'BAD_VERSION');
  static const Error_Code UNKNOWN_REQUEST =
      Error_Code._(3, _omitEnumNames ? '' : 'UNKNOWN_REQUEST');
  static const Error_Code NEED_HELLO =
      Error_Code._(4, _omitEnumNames ? '' : 'NEED_HELLO');
  static const Error_Code BAD_ARGUMENT =
      Error_Code._(5, _omitEnumNames ? '' : 'BAD_ARGUMENT');
  static const Error_Code TOO_LONG =
      Error_Code._(6, _omitEnumNames ? '' : 'TOO_LONG');
  static const Error_Code RATE_LIMITED =
      Error_Code._(7, _omitEnumNames ? '' : 'RATE_LIMITED');
  static const Error_Code NOT_FOUND =
      Error_Code._(8, _omitEnumNames ? '' : 'NOT_FOUND');
  static const Error_Code KEY_REJECTED =
      Error_Code._(9, _omitEnumNames ? '' : 'KEY_REJECTED');
  static const Error_Code SEND_FAILED =
      Error_Code._(10, _omitEnumNames ? '' : 'SEND_FAILED');
  static const Error_Code TOO_MANY_CLIENTS =
      Error_Code._(11, _omitEnumNames ? '' : 'TOO_MANY_CLIENTS');
  static const Error_Code NO_IDENTITY =
      Error_Code._(12, _omitEnumNames ? '' : 'NO_IDENTITY');
  static const Error_Code CHANNEL_LIMIT =
      Error_Code._(13, _omitEnumNames ? '' : 'CHANNEL_LIMIT');
  static const Error_Code BAD_PIN =
      Error_Code._(14, _omitEnumNames ? '' : 'BAD_PIN');
  static const Error_Code NO_KEY =
      Error_Code._(15, _omitEnumNames ? '' : 'NO_KEY');

  static const $core.List<Error_Code> values = <Error_Code>[
    NONE,
    BAD_FRAME,
    BAD_VERSION,
    UNKNOWN_REQUEST,
    NEED_HELLO,
    BAD_ARGUMENT,
    TOO_LONG,
    RATE_LIMITED,
    NOT_FOUND,
    KEY_REJECTED,
    SEND_FAILED,
    TOO_MANY_CLIENTS,
    NO_IDENTITY,
    CHANNEL_LIMIT,
    BAD_PIN,
    NO_KEY,
  ];

  static final $core.List<Error_Code?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 15);
  static Error_Code? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Error_Code._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
