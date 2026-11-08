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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'ghostwave.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'ghostwave.pbenum.dart';

/// A GPS fix in 1e-7 degrees (WGS84). An absent Position means "no fix".
class Position extends $pb.GeneratedMessage {
  factory Position({
    $core.int? latE7,
    $core.int? lonE7,
  }) {
    final result = Position._();
    if (latE7 != null) result.latE7 = latE7;
    if (lonE7 != null) result.lonE7 = lonE7;
    return result;
  }

  Position._();

  factory Position.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Position()..mergeFromBuffer(data, registry);
  factory Position.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Position()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Position',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Position.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'latE7', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'lonE7', fieldType: $pb.PbFieldType.OS3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Position clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Position copyWith(void Function(Position) updates) =>
      super.copyWith((message) => updates(message as Position)) as Position;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Position() / Position.new instead')
  static Position create() => Position._();
  static $pb.GeneratedMessage $_createMessage() => Position._();
  @$core.override
  Position createEmptyInstance() => Position._();
  @$core.pragma('dart2js:noInline')
  static Position getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Position>(Position.$_createMessage);
  static Position? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get latE7 => $_getIZ(0);
  @$pb.TagNumber(1)
  set latE7($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatE7() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatE7() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get lonE7 => $_getIZ(1);
  @$pb.TagNumber(2)
  set lonE7($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLonE7() => $_has(1);
  @$pb.TagNumber(2)
  void clearLonE7() => $_clearField(2);
}

enum ToRadio_Request {
  hello,
  sendText,
  addContact,
  listContacts,
  setKnownPosition,
  sosStart,
  sosStop,
  sosAck,
  getStatus,
  getPosition,
  setOwnPosition,
  sendChannelText,
  addChannel,
  removeChannel,
  listChannels,
  setName,
  notSet
}

class ToRadio extends $pb.GeneratedMessage {
  factory ToRadio({
    $core.int? reqId,
    Hello? hello,
    SendText? sendText,
    AddContact? addContact,
    ListContacts? listContacts,
    SetKnownPosition? setKnownPosition,
    SosStart? sosStart,
    SosStop? sosStop,
    SosAck? sosAck,
    GetStatus? getStatus,
    GetPosition? getPosition,
    SetOwnPosition? setOwnPosition,
    SendChannelText? sendChannelText,
    AddChannel? addChannel,
    RemoveChannel? removeChannel,
    ListChannels? listChannels,
    SetName? setName,
  }) {
    final result = ToRadio._();
    if (reqId != null) result.reqId = reqId;
    if (hello != null) result.hello = hello;
    if (sendText != null) result.sendText = sendText;
    if (addContact != null) result.addContact = addContact;
    if (listContacts != null) result.listContacts = listContacts;
    if (setKnownPosition != null) result.setKnownPosition = setKnownPosition;
    if (sosStart != null) result.sosStart = sosStart;
    if (sosStop != null) result.sosStop = sosStop;
    if (sosAck != null) result.sosAck = sosAck;
    if (getStatus != null) result.getStatus = getStatus;
    if (getPosition != null) result.getPosition = getPosition;
    if (setOwnPosition != null) result.setOwnPosition = setOwnPosition;
    if (sendChannelText != null) result.sendChannelText = sendChannelText;
    if (addChannel != null) result.addChannel = addChannel;
    if (removeChannel != null) result.removeChannel = removeChannel;
    if (listChannels != null) result.listChannels = listChannels;
    if (setName != null) result.setName = setName;
    return result;
  }

  ToRadio._();

  factory ToRadio.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ToRadio()..mergeFromBuffer(data, registry);
  factory ToRadio.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ToRadio()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ToRadio_Request> _ToRadio_RequestByTag = {
    10: ToRadio_Request.hello,
    11: ToRadio_Request.sendText,
    12: ToRadio_Request.addContact,
    13: ToRadio_Request.listContacts,
    14: ToRadio_Request.setKnownPosition,
    15: ToRadio_Request.sosStart,
    16: ToRadio_Request.sosStop,
    17: ToRadio_Request.sosAck,
    18: ToRadio_Request.getStatus,
    19: ToRadio_Request.getPosition,
    20: ToRadio_Request.setOwnPosition,
    21: ToRadio_Request.sendChannelText,
    22: ToRadio_Request.addChannel,
    23: ToRadio_Request.removeChannel,
    24: ToRadio_Request.listChannels,
    25: ToRadio_Request.setName,
    0: ToRadio_Request.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToRadio',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: ToRadio.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
    ..aI(1, _omitFieldNames ? '' : 'reqId', fieldType: $pb.PbFieldType.OU3)
    ..aOM<Hello>(10, _omitFieldNames ? '' : 'hello',
        subBuilder: Hello.$_createMessage)
    ..aOM<SendText>(11, _omitFieldNames ? '' : 'sendText',
        subBuilder: SendText.$_createMessage)
    ..aOM<AddContact>(12, _omitFieldNames ? '' : 'addContact',
        subBuilder: AddContact.$_createMessage)
    ..aOM<ListContacts>(13, _omitFieldNames ? '' : 'listContacts',
        subBuilder: ListContacts.$_createMessage)
    ..aOM<SetKnownPosition>(14, _omitFieldNames ? '' : 'setKnownPosition',
        subBuilder: SetKnownPosition.$_createMessage)
    ..aOM<SosStart>(15, _omitFieldNames ? '' : 'sosStart',
        subBuilder: SosStart.$_createMessage)
    ..aOM<SosStop>(16, _omitFieldNames ? '' : 'sosStop',
        subBuilder: SosStop.$_createMessage)
    ..aOM<SosAck>(17, _omitFieldNames ? '' : 'sosAck',
        subBuilder: SosAck.$_createMessage)
    ..aOM<GetStatus>(18, _omitFieldNames ? '' : 'getStatus',
        subBuilder: GetStatus.$_createMessage)
    ..aOM<GetPosition>(19, _omitFieldNames ? '' : 'getPosition',
        subBuilder: GetPosition.$_createMessage)
    ..aOM<SetOwnPosition>(20, _omitFieldNames ? '' : 'setOwnPosition',
        subBuilder: SetOwnPosition.$_createMessage)
    ..aOM<SendChannelText>(21, _omitFieldNames ? '' : 'sendChannelText',
        subBuilder: SendChannelText.$_createMessage)
    ..aOM<AddChannel>(22, _omitFieldNames ? '' : 'addChannel',
        subBuilder: AddChannel.$_createMessage)
    ..aOM<RemoveChannel>(23, _omitFieldNames ? '' : 'removeChannel',
        subBuilder: RemoveChannel.$_createMessage)
    ..aOM<ListChannels>(24, _omitFieldNames ? '' : 'listChannels',
        subBuilder: ListChannels.$_createMessage)
    ..aOM<SetName>(25, _omitFieldNames ? '' : 'setName',
        subBuilder: SetName.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToRadio clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToRadio copyWith(void Function(ToRadio) updates) =>
      super.copyWith((message) => updates(message as ToRadio)) as ToRadio;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ToRadio() / ToRadio.new instead')
  static ToRadio create() => ToRadio._();
  static $pb.GeneratedMessage $_createMessage() => ToRadio._();
  @$core.override
  ToRadio createEmptyInstance() => ToRadio._();
  @$core.pragma('dart2js:noInline')
  static ToRadio getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToRadio>(ToRadio.$_createMessage);
  static ToRadio? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  ToRadio_Request whichRequest() => _ToRadio_RequestByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  void clearRequest() => $_clearField($_whichOneof(0));

  /// Echoed in every reply to this request. 0 = no reply correlation wanted.
  @$pb.TagNumber(1)
  $core.int get reqId => $_getIZ(0);
  @$pb.TagNumber(1)
  set reqId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReqId() => $_has(0);
  @$pb.TagNumber(1)
  void clearReqId() => $_clearField(1);

  @$pb.TagNumber(10)
  Hello get hello => $_getN(1);
  @$pb.TagNumber(10)
  set hello(Hello value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasHello() => $_has(1);
  @$pb.TagNumber(10)
  void clearHello() => $_clearField(10);
  @$pb.TagNumber(10)
  Hello ensureHello() => $_ensure(1);

  @$pb.TagNumber(11)
  SendText get sendText => $_getN(2);
  @$pb.TagNumber(11)
  set sendText(SendText value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasSendText() => $_has(2);
  @$pb.TagNumber(11)
  void clearSendText() => $_clearField(11);
  @$pb.TagNumber(11)
  SendText ensureSendText() => $_ensure(2);

  @$pb.TagNumber(12)
  AddContact get addContact => $_getN(3);
  @$pb.TagNumber(12)
  set addContact(AddContact value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasAddContact() => $_has(3);
  @$pb.TagNumber(12)
  void clearAddContact() => $_clearField(12);
  @$pb.TagNumber(12)
  AddContact ensureAddContact() => $_ensure(3);

  @$pb.TagNumber(13)
  ListContacts get listContacts => $_getN(4);
  @$pb.TagNumber(13)
  set listContacts(ListContacts value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasListContacts() => $_has(4);
  @$pb.TagNumber(13)
  void clearListContacts() => $_clearField(13);
  @$pb.TagNumber(13)
  ListContacts ensureListContacts() => $_ensure(4);

  @$pb.TagNumber(14)
  SetKnownPosition get setKnownPosition => $_getN(5);
  @$pb.TagNumber(14)
  set setKnownPosition(SetKnownPosition value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasSetKnownPosition() => $_has(5);
  @$pb.TagNumber(14)
  void clearSetKnownPosition() => $_clearField(14);
  @$pb.TagNumber(14)
  SetKnownPosition ensureSetKnownPosition() => $_ensure(5);

  @$pb.TagNumber(15)
  SosStart get sosStart => $_getN(6);
  @$pb.TagNumber(15)
  set sosStart(SosStart value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasSosStart() => $_has(6);
  @$pb.TagNumber(15)
  void clearSosStart() => $_clearField(15);
  @$pb.TagNumber(15)
  SosStart ensureSosStart() => $_ensure(6);

  @$pb.TagNumber(16)
  SosStop get sosStop => $_getN(7);
  @$pb.TagNumber(16)
  set sosStop(SosStop value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasSosStop() => $_has(7);
  @$pb.TagNumber(16)
  void clearSosStop() => $_clearField(16);
  @$pb.TagNumber(16)
  SosStop ensureSosStop() => $_ensure(7);

  @$pb.TagNumber(17)
  SosAck get sosAck => $_getN(8);
  @$pb.TagNumber(17)
  set sosAck(SosAck value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasSosAck() => $_has(8);
  @$pb.TagNumber(17)
  void clearSosAck() => $_clearField(17);
  @$pb.TagNumber(17)
  SosAck ensureSosAck() => $_ensure(8);

  @$pb.TagNumber(18)
  GetStatus get getStatus => $_getN(9);
  @$pb.TagNumber(18)
  set getStatus(GetStatus value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasGetStatus() => $_has(9);
  @$pb.TagNumber(18)
  void clearGetStatus() => $_clearField(18);
  @$pb.TagNumber(18)
  GetStatus ensureGetStatus() => $_ensure(9);

  @$pb.TagNumber(19)
  GetPosition get getPosition => $_getN(10);
  @$pb.TagNumber(19)
  set getPosition(GetPosition value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasGetPosition() => $_has(10);
  @$pb.TagNumber(19)
  void clearGetPosition() => $_clearField(19);
  @$pb.TagNumber(19)
  GetPosition ensureGetPosition() => $_ensure(10);

  @$pb.TagNumber(20)
  SetOwnPosition get setOwnPosition => $_getN(11);
  @$pb.TagNumber(20)
  set setOwnPosition(SetOwnPosition value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasSetOwnPosition() => $_has(11);
  @$pb.TagNumber(20)
  void clearSetOwnPosition() => $_clearField(20);
  @$pb.TagNumber(20)
  SetOwnPosition ensureSetOwnPosition() => $_ensure(11);

  /// protocol 1.1 (NodeInfo.protocol_minor >= 1)
  @$pb.TagNumber(21)
  SendChannelText get sendChannelText => $_getN(12);
  @$pb.TagNumber(21)
  set sendChannelText(SendChannelText value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasSendChannelText() => $_has(12);
  @$pb.TagNumber(21)
  void clearSendChannelText() => $_clearField(21);
  @$pb.TagNumber(21)
  SendChannelText ensureSendChannelText() => $_ensure(12);

  @$pb.TagNumber(22)
  AddChannel get addChannel => $_getN(13);
  @$pb.TagNumber(22)
  set addChannel(AddChannel value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasAddChannel() => $_has(13);
  @$pb.TagNumber(22)
  void clearAddChannel() => $_clearField(22);
  @$pb.TagNumber(22)
  AddChannel ensureAddChannel() => $_ensure(13);

  @$pb.TagNumber(23)
  RemoveChannel get removeChannel => $_getN(14);
  @$pb.TagNumber(23)
  set removeChannel(RemoveChannel value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasRemoveChannel() => $_has(14);
  @$pb.TagNumber(23)
  void clearRemoveChannel() => $_clearField(23);
  @$pb.TagNumber(23)
  RemoveChannel ensureRemoveChannel() => $_ensure(14);

  @$pb.TagNumber(24)
  ListChannels get listChannels => $_getN(15);
  @$pb.TagNumber(24)
  set listChannels(ListChannels value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasListChannels() => $_has(15);
  @$pb.TagNumber(24)
  void clearListChannels() => $_clearField(24);
  @$pb.TagNumber(24)
  ListChannels ensureListChannels() => $_ensure(15);

  @$pb.TagNumber(25)
  SetName get setName => $_getN(16);
  @$pb.TagNumber(25)
  set setName(SetName value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasSetName() => $_has(16);
  @$pb.TagNumber(25)
  void clearSetName() => $_clearField(25);
  @$pb.TagNumber(25)
  SetName ensureSetName() => $_ensure(16);
}

/// Must be the first request. Reply: NodeInfo, then any replayed events.
class Hello extends $pb.GeneratedMessage {
  factory Hello({
    $core.int? protocolVersion,
    $core.String? clientName,
    $core.List<$core.int>? clientShare,
    $core.List<$core.int>? pinProof,
  }) {
    final result = Hello._();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (clientName != null) result.clientName = clientName;
    if (clientShare != null) result.clientShare = clientShare;
    if (pinProof != null) result.pinProof = pinProof;
    return result;
  }

  Hello._();

  factory Hello.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Hello()..mergeFromBuffer(data, registry);
  factory Hello.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Hello()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Hello',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Hello.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'clientName')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'clientShare', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'pinProof', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello copyWith(void Function(Hello) updates) =>
      super.copyWith((message) => updates(message as Hello)) as Hello;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Hello() / Hello.new instead')
  static Hello create() => Hello._();
  static $pb.GeneratedMessage $_createMessage() => Hello._();
  @$core.override
  Hello createEmptyInstance() => Hello._();
  @$core.pragma('dart2js:noInline')
  static Hello getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Hello>(Hello.$_createMessage);
  static Hello? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get clientName => $_getSZ(1);
  @$pb.TagNumber(2)
  set clientName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClientName() => $_has(1);
  @$pb.TagNumber(2)
  void clearClientName() => $_clearField(2);

  /// protocol 1.3, answering PinChallenge (docs/CLIENT_PROTOCOL.md §7)
  @$pb.TagNumber(3)
  $core.List<$core.int> get clientShare => $_getN(2);
  @$pb.TagNumber(3)
  set clientShare($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientShare() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientShare() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get pinProof => $_getN(3);
  @$pb.TagNumber(4)
  set pinProof($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPinProof() => $_has(3);
  @$pb.TagNumber(4)
  void clearPinProof() => $_clearField(4);
}

/// Reply: SendQueued (msg_id assigned), later Delivered when the destination's
/// end-to-end ACK arrives. Errors: TOO_LONG, BAD_ARGUMENT, SEND_FAILED.
class SendText extends $pb.GeneratedMessage {
  factory SendText({
    $core.int? dest,
    $core.List<$core.int>? text,
    $core.int? clientMsgId,
  }) {
    final result = SendText._();
    if (dest != null) result.dest = dest;
    if (text != null) result.text = text;
    if (clientMsgId != null) result.clientMsgId = clientMsgId;
    return result;
  }

  SendText._();

  factory SendText.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SendText()..mergeFromBuffer(data, registry);
  factory SendText.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SendText()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendText',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SendText.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'dest', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'text', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'clientMsgId',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendText clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendText copyWith(void Function(SendText) updates) =>
      super.copyWith((message) => updates(message as SendText)) as SendText;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SendText() / SendText.new instead')
  static SendText create() => SendText._();
  static $pb.GeneratedMessage $_createMessage() => SendText._();
  @$core.override
  SendText createEmptyInstance() => SendText._();
  @$core.pragma('dart2js:noInline')
  static SendText getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendText>(SendText.$_createMessage);
  static SendText? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get dest => $_getIZ(0);
  @$pb.TagNumber(1)
  set dest($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDest() => $_has(0);
  @$pb.TagNumber(1)
  void clearDest() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get text => $_getN(1);
  @$pb.TagNumber(2)
  set text($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get clientMsgId => $_getIZ(2);
  @$pb.TagNumber(3)
  set clientMsgId($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientMsgId() => $_clearField(3);
}

/// Pins a contact's key, as carried by a QR code. Reply: Ok, or KEY_REJECTED.
class AddContact extends $pb.GeneratedMessage {
  factory AddContact({
    $core.int? nodeId,
    $core.List<$core.int>? ed25519Pub,
    $core.List<$core.int>? x25519Pub,
    $core.String? name,
  }) {
    final result = AddContact._();
    if (nodeId != null) result.nodeId = nodeId;
    if (ed25519Pub != null) result.ed25519Pub = ed25519Pub;
    if (x25519Pub != null) result.x25519Pub = x25519Pub;
    if (name != null) result.name = name;
    return result;
  }

  AddContact._();

  factory AddContact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddContact()..mergeFromBuffer(data, registry);
  factory AddContact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddContact()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AddContact',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: AddContact.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ed25519Pub', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'x25519Pub', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddContact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddContact copyWith(void Function(AddContact) updates) =>
      super.copyWith((message) => updates(message as AddContact)) as AddContact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AddContact() / AddContact.new instead')
  static AddContact create() => AddContact._();
  static $pb.GeneratedMessage $_createMessage() => AddContact._();
  @$core.override
  AddContact createEmptyInstance() => AddContact._();
  @$core.pragma('dart2js:noInline')
  static AddContact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AddContact>(AddContact.$_createMessage);
  static AddContact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nodeId => $_getIZ(0);
  @$pb.TagNumber(1)
  set nodeId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ed25519Pub => $_getN(1);
  @$pb.TagNumber(2)
  set ed25519Pub($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEd25519Pub() => $_has(1);
  @$pb.TagNumber(2)
  void clearEd25519Pub() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get x25519Pub => $_getN(2);
  @$pb.TagNumber(3)
  set x25519Pub($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX25519Pub() => $_has(2);
  @$pb.TagNumber(3)
  void clearX25519Pub() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get name => $_getSZ(3);
  @$pb.TagNumber(4)
  set name($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasName() => $_has(3);
  @$pb.TagNumber(4)
  void clearName() => $_clearField(4);
}

/// Reply: one Contact per peer key the node holds, then ContactsEnd.
class ListContacts extends $pb.GeneratedMessage {
  factory ListContacts() => ListContacts._();

  ListContacts._();

  factory ListContacts.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListContacts()..mergeFromBuffer(data, registry);
  factory ListContacts.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListContacts()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListContacts',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: ListContacts.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListContacts clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListContacts copyWith(void Function(ListContacts) updates) =>
      super.copyWith((message) => updates(message as ListContacts))
          as ListContacts;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListContacts() / ListContacts.new instead')
  static ListContacts create() => ListContacts._();
  static $pb.GeneratedMessage $_createMessage() => ListContacts._();
  @$core.override
  ListContacts createEmptyInstance() => ListContacts._();
  @$core.pragma('dart2js:noInline')
  static ListContacts getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListContacts>(
          ListContacts.$_createMessage);
  static ListContacts? _defaultInstance;
}

/// Seeds where a node is believed to be (contact card, map pin). Reply: Ok.
class SetKnownPosition extends $pb.GeneratedMessage {
  factory SetKnownPosition({
    $core.int? nodeId,
    Position? pos,
  }) {
    final result = SetKnownPosition._();
    if (nodeId != null) result.nodeId = nodeId;
    if (pos != null) result.pos = pos;
    return result;
  }

  SetKnownPosition._();

  factory SetKnownPosition.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetKnownPosition()..mergeFromBuffer(data, registry);
  factory SetKnownPosition.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetKnownPosition()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetKnownPosition',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SetKnownPosition.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..aOM<Position>(2, _omitFieldNames ? '' : 'pos',
        subBuilder: Position.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetKnownPosition clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetKnownPosition copyWith(void Function(SetKnownPosition) updates) =>
      super.copyWith((message) => updates(message as SetKnownPosition))
          as SetKnownPosition;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetKnownPosition() / SetKnownPosition.new instead')
  static SetKnownPosition create() => SetKnownPosition._();
  static $pb.GeneratedMessage $_createMessage() => SetKnownPosition._();
  @$core.override
  SetKnownPosition createEmptyInstance() => SetKnownPosition._();
  @$core.pragma('dart2js:noInline')
  static SetKnownPosition getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetKnownPosition>(
          SetKnownPosition.$_createMessage);
  static SetKnownPosition? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nodeId => $_getIZ(0);
  @$pb.TagNumber(1)
  set nodeId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  Position get pos => $_getN(1);
  @$pb.TagNumber(2)
  set pos(Position value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPos() => $_has(1);
  @$pb.TagNumber(2)
  void clearPos() => $_clearField(2);
  @$pb.TagNumber(2)
  Position ensurePos() => $_ensure(1);
}

/// Starts or updates our SOS (repeats until SosStop). Reply: Ok, or RATE_LIMITED.
class SosStart extends $pb.GeneratedMessage {
  factory SosStart({
    $core.List<$core.int>? text,
    $core.int? batteryPct,
    $core.int? accuracyM,
  }) {
    final result = SosStart._();
    if (text != null) result.text = text;
    if (batteryPct != null) result.batteryPct = batteryPct;
    if (accuracyM != null) result.accuracyM = accuracyM;
    return result;
  }

  SosStart._();

  factory SosStart.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosStart()..mergeFromBuffer(data, registry);
  factory SosStart.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosStart()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SosStart',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SosStart.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'text', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'batteryPct', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'accuracyM', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosStart clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosStart copyWith(void Function(SosStart) updates) =>
      super.copyWith((message) => updates(message as SosStart)) as SosStart;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SosStart() / SosStart.new instead')
  static SosStart create() => SosStart._();
  static $pb.GeneratedMessage $_createMessage() => SosStart._();
  @$core.override
  SosStart createEmptyInstance() => SosStart._();
  @$core.pragma('dart2js:noInline')
  static SosStart getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SosStart>(SosStart.$_createMessage);
  static SosStart? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get text => $_getN(0);
  @$pb.TagNumber(1)
  set text($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get batteryPct => $_getIZ(1);
  @$pb.TagNumber(2)
  set batteryPct($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBatteryPct() => $_has(1);
  @$pb.TagNumber(2)
  void clearBatteryPct() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get accuracyM => $_getIZ(2);
  @$pb.TagNumber(3)
  set accuracyM($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccuracyM() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccuracyM() => $_clearField(3);
}

class SosStop extends $pb.GeneratedMessage {
  factory SosStop() => SosStop._();

  SosStop._();

  factory SosStop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosStop()..mergeFromBuffer(data, registry);
  factory SosStop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosStop()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SosStop',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SosStop.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosStop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosStop copyWith(void Function(SosStop) updates) =>
      super.copyWith((message) => updates(message as SosStop)) as SosStop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SosStop() / SosStop.new instead')
  static SosStop create() => SosStop._();
  static $pb.GeneratedMessage $_createMessage() => SosStop._();
  @$core.override
  SosStop createEmptyInstance() => SosStop._();
  @$core.pragma('dart2js:noInline')
  static SosStop getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SosStop>(SosStop.$_createMessage);
  static SosStop? _defaultInstance;
}

/// Acknowledges an SOS we hold from node_id. Reply: Ok, or NOT_FOUND.
class SosAck extends $pb.GeneratedMessage {
  factory SosAck({
    $core.int? nodeId,
  }) {
    final result = SosAck._();
    if (nodeId != null) result.nodeId = nodeId;
    return result;
  }

  SosAck._();

  factory SosAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosAck()..mergeFromBuffer(data, registry);
  factory SosAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosAck()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SosAck',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SosAck.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosAck copyWith(void Function(SosAck) updates) =>
      super.copyWith((message) => updates(message as SosAck)) as SosAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SosAck() / SosAck.new instead')
  static SosAck create() => SosAck._();
  static $pb.GeneratedMessage $_createMessage() => SosAck._();
  @$core.override
  SosAck createEmptyInstance() => SosAck._();
  @$core.pragma('dart2js:noInline')
  static SosAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SosAck>(SosAck.$_createMessage);
  static SosAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nodeId => $_getIZ(0);
  @$pb.TagNumber(1)
  set nodeId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);
}

class GetStatus extends $pb.GeneratedMessage {
  factory GetStatus() => GetStatus._();

  GetStatus._();

  factory GetStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetStatus()..mergeFromBuffer(data, registry);
  factory GetStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetStatus',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: GetStatus.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetStatus copyWith(void Function(GetStatus) updates) =>
      super.copyWith((message) => updates(message as GetStatus)) as GetStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetStatus() / GetStatus.new instead')
  static GetStatus create() => GetStatus._();
  static $pb.GeneratedMessage $_createMessage() => GetStatus._();
  @$core.override
  GetStatus createEmptyInstance() => GetStatus._();
  @$core.pragma('dart2js:noInline')
  static GetStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetStatus>(GetStatus.$_createMessage);
  static GetStatus? _defaultInstance;
}

class GetPosition extends $pb.GeneratedMessage {
  factory GetPosition() => GetPosition._();

  GetPosition._();

  factory GetPosition.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPosition()..mergeFromBuffer(data, registry);
  factory GetPosition.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPosition()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPosition',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: GetPosition.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPosition clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPosition copyWith(void Function(GetPosition) updates) =>
      super.copyWith((message) => updates(message as GetPosition))
          as GetPosition;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetPosition() / GetPosition.new instead')
  static GetPosition create() => GetPosition._();
  static $pb.GeneratedMessage $_createMessage() => GetPosition._();
  @$core.override
  GetPosition createEmptyInstance() => GetPosition._();
  @$core.pragma('dart2js:noInline')
  static GetPosition getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPosition>(
          GetPosition.$_createMessage);
  static GetPosition? _defaultInstance;
}

/// The phone's GPS fix becomes the node's own position (nodes without GPS).
/// An absent pos clears it. Reply: Ok.
class SetOwnPosition extends $pb.GeneratedMessage {
  factory SetOwnPosition({
    Position? pos,
  }) {
    final result = SetOwnPosition._();
    if (pos != null) result.pos = pos;
    return result;
  }

  SetOwnPosition._();

  factory SetOwnPosition.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetOwnPosition()..mergeFromBuffer(data, registry);
  factory SetOwnPosition.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetOwnPosition()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetOwnPosition',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SetOwnPosition.$_createMessage)
    ..aOM<Position>(1, _omitFieldNames ? '' : 'pos',
        subBuilder: Position.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOwnPosition clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOwnPosition copyWith(void Function(SetOwnPosition) updates) =>
      super.copyWith((message) => updates(message as SetOwnPosition))
          as SetOwnPosition;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetOwnPosition() / SetOwnPosition.new instead')
  static SetOwnPosition create() => SetOwnPosition._();
  static $pb.GeneratedMessage $_createMessage() => SetOwnPosition._();
  @$core.override
  SetOwnPosition createEmptyInstance() => SetOwnPosition._();
  @$core.pragma('dart2js:noInline')
  static SetOwnPosition getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetOwnPosition>(
          SetOwnPosition.$_createMessage);
  static SetOwnPosition? _defaultInstance;

  @$pb.TagNumber(1)
  Position get pos => $_getN(0);
  @$pb.TagNumber(1)
  set pos(Position value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPos() => $_has(0);
  @$pb.TagNumber(1)
  void clearPos() => $_clearField(1);
  @$pb.TagNumber(1)
  Position ensurePos() => $_ensure(0);
}

/// Reply: SendQueued (dest = 0xFFFFFFFF). Errors: NOT_FOUND (no such channel),
/// TOO_LONG (over NodeInfo.max_channel_text_bytes), BAD_ARGUMENT, SEND_FAILED.
class SendChannelText extends $pb.GeneratedMessage {
  factory SendChannelText({
    $core.String? channel,
    $core.List<$core.int>? text,
    $core.int? clientMsgId,
  }) {
    final result = SendChannelText._();
    if (channel != null) result.channel = channel;
    if (text != null) result.text = text;
    if (clientMsgId != null) result.clientMsgId = clientMsgId;
    return result;
  }

  SendChannelText._();

  factory SendChannelText.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SendChannelText()..mergeFromBuffer(data, registry);
  factory SendChannelText.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SendChannelText()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendChannelText',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SendChannelText.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'channel')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'text', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'clientMsgId',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendChannelText clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendChannelText copyWith(void Function(SendChannelText) updates) =>
      super.copyWith((message) => updates(message as SendChannelText))
          as SendChannelText;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SendChannelText() / SendChannelText.new instead')
  static SendChannelText create() => SendChannelText._();
  static $pb.GeneratedMessage $_createMessage() => SendChannelText._();
  @$core.override
  SendChannelText createEmptyInstance() => SendChannelText._();
  @$core.pragma('dart2js:noInline')
  static SendChannelText getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SendChannelText>(
          SendChannelText.$_createMessage);
  static SendChannelText? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get channel => $_getSZ(0);
  @$pb.TagNumber(1)
  set channel($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannel() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannel() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get text => $_getN(1);
  @$pb.TagNumber(2)
  set text($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get clientMsgId => $_getIZ(2);
  @$pb.TagNumber(3)
  set clientMsgId($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientMsgId() => $_clearField(3);
}

/// Joins a channel (kept across node restarts). Reply: Ok; adding the same
/// name with the same key again is Ok too. Errors: BAD_ARGUMENT (name or key
/// malformed, name taken by another key, key joined under another name),
/// CHANNEL_LIMIT (the node holds the most it can).
class AddChannel extends $pb.GeneratedMessage {
  factory AddChannel({
    $core.String? name,
    $core.List<$core.int>? psk,
  }) {
    final result = AddChannel._();
    if (name != null) result.name = name;
    if (psk != null) result.psk = psk;
    return result;
  }

  AddChannel._();

  factory AddChannel.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddChannel()..mergeFromBuffer(data, registry);
  factory AddChannel.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddChannel()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AddChannel',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: AddChannel.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'psk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddChannel clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddChannel copyWith(void Function(AddChannel) updates) =>
      super.copyWith((message) => updates(message as AddChannel)) as AddChannel;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AddChannel() / AddChannel.new instead')
  static AddChannel create() => AddChannel._();
  static $pb.GeneratedMessage $_createMessage() => AddChannel._();
  @$core.override
  AddChannel createEmptyInstance() => AddChannel._();
  @$core.pragma('dart2js:noInline')
  static AddChannel getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AddChannel>(AddChannel.$_createMessage);
  static AddChannel? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get psk => $_getN(1);
  @$pb.TagNumber(2)
  set psk($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPsk() => $_has(1);
  @$pb.TagNumber(2)
  void clearPsk() => $_clearField(2);
}

class RemoveChannel extends $pb.GeneratedMessage {
  factory RemoveChannel({
    $core.String? name,
  }) {
    final result = RemoveChannel._();
    if (name != null) result.name = name;
    return result;
  }

  RemoveChannel._();

  factory RemoveChannel.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RemoveChannel()..mergeFromBuffer(data, registry);
  factory RemoveChannel.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RemoveChannel()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RemoveChannel',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: RemoveChannel.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveChannel clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveChannel copyWith(void Function(RemoveChannel) updates) =>
      super.copyWith((message) => updates(message as RemoveChannel))
          as RemoveChannel;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RemoveChannel() / RemoveChannel.new instead')
  static RemoveChannel create() => RemoveChannel._();
  static $pb.GeneratedMessage $_createMessage() => RemoveChannel._();
  @$core.override
  RemoveChannel createEmptyInstance() => RemoveChannel._();
  @$core.pragma('dart2js:noInline')
  static RemoveChannel getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RemoveChannel>(
          RemoveChannel.$_createMessage);
  static RemoveChannel? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);
}

/// Reply: one Channel per joined channel, then ChannelsEnd.
class ListChannels extends $pb.GeneratedMessage {
  factory ListChannels() => ListChannels._();

  ListChannels._();

  factory ListChannels.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListChannels()..mergeFromBuffer(data, registry);
  factory ListChannels.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListChannels()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListChannels',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: ListChannels.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListChannels clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListChannels copyWith(void Function(ListChannels) updates) =>
      super.copyWith((message) => updates(message as ListChannels))
          as ListChannels;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListChannels() / ListChannels.new instead')
  static ListChannels create() => ListChannels._();
  static $pb.GeneratedMessage $_createMessage() => ListChannels._();
  @$core.override
  ListChannels createEmptyInstance() => ListChannels._();
  @$core.pragma('dart2js:noInline')
  static ListChannels getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListChannels>(
          ListChannels.$_createMessage);
  static ListChannels? _defaultInstance;
}

/// Sets the node's name (IDENT, <= 9 bytes UTF-8), kept across restarts, and
/// announces it. Reply: Ok. Errors: BAD_ARGUMENT, NO_IDENTITY (legacy node).
class SetName extends $pb.GeneratedMessage {
  factory SetName({
    $core.String? name,
  }) {
    final result = SetName._();
    if (name != null) result.name = name;
    return result;
  }

  SetName._();

  factory SetName.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetName()..mergeFromBuffer(data, registry);
  factory SetName.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetName()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetName',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SetName.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetName clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetName copyWith(void Function(SetName) updates) =>
      super.copyWith((message) => updates(message as SetName)) as SetName;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetName() / SetName.new instead')
  static SetName create() => SetName._();
  static $pb.GeneratedMessage $_createMessage() => SetName._();
  @$core.override
  SetName createEmptyInstance() => SetName._();
  @$core.pragma('dart2js:noInline')
  static SetName getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetName>(SetName.$_createMessage);
  static SetName? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);
}

enum FromRadio_Event {
  nodeInfo,
  text,
  delivered,
  sos,
  sosAck,
  neighbor,
  status,
  position,
  error,
  contact,
  contactsEnd,
  sendQueued,
  ok,
  peerIdent,
  keyChange,
  channelMessage,
  channel,
  channelsEnd,
  pinChallenge,
  notSet
}

class FromRadio extends $pb.GeneratedMessage {
  factory FromRadio({
    $core.int? reqId,
    $core.bool? replayed,
    NodeInfo? nodeInfo,
    TextMessage? text,
    Delivered? delivered,
    SosAlert? sos,
    SosAckReceived? sosAck,
    Neighbor? neighbor,
    Status? status,
    OwnPosition? position,
    Error? error,
    Contact? contact,
    ContactsEnd? contactsEnd,
    SendQueued? sendQueued,
    Ok? ok,
    PeerIdent? peerIdent,
    KeyChange? keyChange,
    ChannelMessage? channelMessage,
    Channel? channel,
    ChannelsEnd? channelsEnd,
    PinChallenge? pinChallenge,
  }) {
    final result = FromRadio._();
    if (reqId != null) result.reqId = reqId;
    if (replayed != null) result.replayed = replayed;
    if (nodeInfo != null) result.nodeInfo = nodeInfo;
    if (text != null) result.text = text;
    if (delivered != null) result.delivered = delivered;
    if (sos != null) result.sos = sos;
    if (sosAck != null) result.sosAck = sosAck;
    if (neighbor != null) result.neighbor = neighbor;
    if (status != null) result.status = status;
    if (position != null) result.position = position;
    if (error != null) result.error = error;
    if (contact != null) result.contact = contact;
    if (contactsEnd != null) result.contactsEnd = contactsEnd;
    if (sendQueued != null) result.sendQueued = sendQueued;
    if (ok != null) result.ok = ok;
    if (peerIdent != null) result.peerIdent = peerIdent;
    if (keyChange != null) result.keyChange = keyChange;
    if (channelMessage != null) result.channelMessage = channelMessage;
    if (channel != null) result.channel = channel;
    if (channelsEnd != null) result.channelsEnd = channelsEnd;
    if (pinChallenge != null) result.pinChallenge = pinChallenge;
    return result;
  }

  FromRadio._();

  factory FromRadio.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FromRadio()..mergeFromBuffer(data, registry);
  factory FromRadio.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FromRadio()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FromRadio_Event> _FromRadio_EventByTag = {
    10: FromRadio_Event.nodeInfo,
    11: FromRadio_Event.text,
    12: FromRadio_Event.delivered,
    13: FromRadio_Event.sos,
    14: FromRadio_Event.sosAck,
    15: FromRadio_Event.neighbor,
    16: FromRadio_Event.status,
    17: FromRadio_Event.position,
    18: FromRadio_Event.error,
    19: FromRadio_Event.contact,
    20: FromRadio_Event.contactsEnd,
    21: FromRadio_Event.sendQueued,
    22: FromRadio_Event.ok,
    23: FromRadio_Event.peerIdent,
    24: FromRadio_Event.keyChange,
    25: FromRadio_Event.channelMessage,
    26: FromRadio_Event.channel,
    27: FromRadio_Event.channelsEnd,
    28: FromRadio_Event.pinChallenge,
    0: FromRadio_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FromRadio',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: FromRadio.$_createMessage)
    ..oo(0, [
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28
    ])
    ..aI(1, _omitFieldNames ? '' : 'reqId', fieldType: $pb.PbFieldType.OU3)
    ..aOB(2, _omitFieldNames ? '' : 'replayed')
    ..aOM<NodeInfo>(10, _omitFieldNames ? '' : 'nodeInfo',
        subBuilder: NodeInfo.$_createMessage)
    ..aOM<TextMessage>(11, _omitFieldNames ? '' : 'text',
        subBuilder: TextMessage.$_createMessage)
    ..aOM<Delivered>(12, _omitFieldNames ? '' : 'delivered',
        subBuilder: Delivered.$_createMessage)
    ..aOM<SosAlert>(13, _omitFieldNames ? '' : 'sos',
        subBuilder: SosAlert.$_createMessage)
    ..aOM<SosAckReceived>(14, _omitFieldNames ? '' : 'sosAck',
        subBuilder: SosAckReceived.$_createMessage)
    ..aOM<Neighbor>(15, _omitFieldNames ? '' : 'neighbor',
        subBuilder: Neighbor.$_createMessage)
    ..aOM<Status>(16, _omitFieldNames ? '' : 'status',
        subBuilder: Status.$_createMessage)
    ..aOM<OwnPosition>(17, _omitFieldNames ? '' : 'position',
        subBuilder: OwnPosition.$_createMessage)
    ..aOM<Error>(18, _omitFieldNames ? '' : 'error',
        subBuilder: Error.$_createMessage)
    ..aOM<Contact>(19, _omitFieldNames ? '' : 'contact',
        subBuilder: Contact.$_createMessage)
    ..aOM<ContactsEnd>(20, _omitFieldNames ? '' : 'contactsEnd',
        subBuilder: ContactsEnd.$_createMessage)
    ..aOM<SendQueued>(21, _omitFieldNames ? '' : 'sendQueued',
        subBuilder: SendQueued.$_createMessage)
    ..aOM<Ok>(22, _omitFieldNames ? '' : 'ok', subBuilder: Ok.$_createMessage)
    ..aOM<PeerIdent>(23, _omitFieldNames ? '' : 'peerIdent',
        subBuilder: PeerIdent.$_createMessage)
    ..aOM<KeyChange>(24, _omitFieldNames ? '' : 'keyChange',
        subBuilder: KeyChange.$_createMessage)
    ..aOM<ChannelMessage>(25, _omitFieldNames ? '' : 'channelMessage',
        subBuilder: ChannelMessage.$_createMessage)
    ..aOM<Channel>(26, _omitFieldNames ? '' : 'channel',
        subBuilder: Channel.$_createMessage)
    ..aOM<ChannelsEnd>(27, _omitFieldNames ? '' : 'channelsEnd',
        subBuilder: ChannelsEnd.$_createMessage)
    ..aOM<PinChallenge>(28, _omitFieldNames ? '' : 'pinChallenge',
        subBuilder: PinChallenge.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FromRadio clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FromRadio copyWith(void Function(FromRadio) updates) =>
      super.copyWith((message) => updates(message as FromRadio)) as FromRadio;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FromRadio() / FromRadio.new instead')
  static FromRadio create() => FromRadio._();
  static $pb.GeneratedMessage $_createMessage() => FromRadio._();
  @$core.override
  FromRadio createEmptyInstance() => FromRadio._();
  @$core.pragma('dart2js:noInline')
  static FromRadio getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FromRadio>(FromRadio.$_createMessage);
  static FromRadio? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  FromRadio_Event whichEvent() => _FromRadio_EventByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  void clearEvent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.int get reqId => $_getIZ(0);
  @$pb.TagNumber(1)
  set reqId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReqId() => $_has(0);
  @$pb.TagNumber(1)
  void clearReqId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get replayed => $_getBF(1);
  @$pb.TagNumber(2)
  set replayed($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReplayed() => $_has(1);
  @$pb.TagNumber(2)
  void clearReplayed() => $_clearField(2);

  @$pb.TagNumber(10)
  NodeInfo get nodeInfo => $_getN(2);
  @$pb.TagNumber(10)
  set nodeInfo(NodeInfo value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasNodeInfo() => $_has(2);
  @$pb.TagNumber(10)
  void clearNodeInfo() => $_clearField(10);
  @$pb.TagNumber(10)
  NodeInfo ensureNodeInfo() => $_ensure(2);

  @$pb.TagNumber(11)
  TextMessage get text => $_getN(3);
  @$pb.TagNumber(11)
  set text(TextMessage value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasText() => $_has(3);
  @$pb.TagNumber(11)
  void clearText() => $_clearField(11);
  @$pb.TagNumber(11)
  TextMessage ensureText() => $_ensure(3);

  @$pb.TagNumber(12)
  Delivered get delivered => $_getN(4);
  @$pb.TagNumber(12)
  set delivered(Delivered value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasDelivered() => $_has(4);
  @$pb.TagNumber(12)
  void clearDelivered() => $_clearField(12);
  @$pb.TagNumber(12)
  Delivered ensureDelivered() => $_ensure(4);

  @$pb.TagNumber(13)
  SosAlert get sos => $_getN(5);
  @$pb.TagNumber(13)
  set sos(SosAlert value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasSos() => $_has(5);
  @$pb.TagNumber(13)
  void clearSos() => $_clearField(13);
  @$pb.TagNumber(13)
  SosAlert ensureSos() => $_ensure(5);

  @$pb.TagNumber(14)
  SosAckReceived get sosAck => $_getN(6);
  @$pb.TagNumber(14)
  set sosAck(SosAckReceived value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasSosAck() => $_has(6);
  @$pb.TagNumber(14)
  void clearSosAck() => $_clearField(14);
  @$pb.TagNumber(14)
  SosAckReceived ensureSosAck() => $_ensure(6);

  @$pb.TagNumber(15)
  Neighbor get neighbor => $_getN(7);
  @$pb.TagNumber(15)
  set neighbor(Neighbor value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasNeighbor() => $_has(7);
  @$pb.TagNumber(15)
  void clearNeighbor() => $_clearField(15);
  @$pb.TagNumber(15)
  Neighbor ensureNeighbor() => $_ensure(7);

  @$pb.TagNumber(16)
  Status get status => $_getN(8);
  @$pb.TagNumber(16)
  set status(Status value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasStatus() => $_has(8);
  @$pb.TagNumber(16)
  void clearStatus() => $_clearField(16);
  @$pb.TagNumber(16)
  Status ensureStatus() => $_ensure(8);

  @$pb.TagNumber(17)
  OwnPosition get position => $_getN(9);
  @$pb.TagNumber(17)
  set position(OwnPosition value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasPosition() => $_has(9);
  @$pb.TagNumber(17)
  void clearPosition() => $_clearField(17);
  @$pb.TagNumber(17)
  OwnPosition ensurePosition() => $_ensure(9);

  @$pb.TagNumber(18)
  Error get error => $_getN(10);
  @$pb.TagNumber(18)
  set error(Error value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasError() => $_has(10);
  @$pb.TagNumber(18)
  void clearError() => $_clearField(18);
  @$pb.TagNumber(18)
  Error ensureError() => $_ensure(10);

  @$pb.TagNumber(19)
  Contact get contact => $_getN(11);
  @$pb.TagNumber(19)
  set contact(Contact value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasContact() => $_has(11);
  @$pb.TagNumber(19)
  void clearContact() => $_clearField(19);
  @$pb.TagNumber(19)
  Contact ensureContact() => $_ensure(11);

  @$pb.TagNumber(20)
  ContactsEnd get contactsEnd => $_getN(12);
  @$pb.TagNumber(20)
  set contactsEnd(ContactsEnd value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasContactsEnd() => $_has(12);
  @$pb.TagNumber(20)
  void clearContactsEnd() => $_clearField(20);
  @$pb.TagNumber(20)
  ContactsEnd ensureContactsEnd() => $_ensure(12);

  @$pb.TagNumber(21)
  SendQueued get sendQueued => $_getN(13);
  @$pb.TagNumber(21)
  set sendQueued(SendQueued value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasSendQueued() => $_has(13);
  @$pb.TagNumber(21)
  void clearSendQueued() => $_clearField(21);
  @$pb.TagNumber(21)
  SendQueued ensureSendQueued() => $_ensure(13);

  @$pb.TagNumber(22)
  Ok get ok => $_getN(14);
  @$pb.TagNumber(22)
  set ok(Ok value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasOk() => $_has(14);
  @$pb.TagNumber(22)
  void clearOk() => $_clearField(22);
  @$pb.TagNumber(22)
  Ok ensureOk() => $_ensure(14);

  @$pb.TagNumber(23)
  PeerIdent get peerIdent => $_getN(15);
  @$pb.TagNumber(23)
  set peerIdent(PeerIdent value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasPeerIdent() => $_has(15);
  @$pb.TagNumber(23)
  void clearPeerIdent() => $_clearField(23);
  @$pb.TagNumber(23)
  PeerIdent ensurePeerIdent() => $_ensure(15);

  @$pb.TagNumber(24)
  KeyChange get keyChange => $_getN(16);
  @$pb.TagNumber(24)
  set keyChange(KeyChange value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasKeyChange() => $_has(16);
  @$pb.TagNumber(24)
  void clearKeyChange() => $_clearField(24);
  @$pb.TagNumber(24)
  KeyChange ensureKeyChange() => $_ensure(16);

  /// protocol 1.1
  @$pb.TagNumber(25)
  ChannelMessage get channelMessage => $_getN(17);
  @$pb.TagNumber(25)
  set channelMessage(ChannelMessage value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasChannelMessage() => $_has(17);
  @$pb.TagNumber(25)
  void clearChannelMessage() => $_clearField(25);
  @$pb.TagNumber(25)
  ChannelMessage ensureChannelMessage() => $_ensure(17);

  @$pb.TagNumber(26)
  Channel get channel => $_getN(18);
  @$pb.TagNumber(26)
  set channel(Channel value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasChannel() => $_has(18);
  @$pb.TagNumber(26)
  void clearChannel() => $_clearField(26);
  @$pb.TagNumber(26)
  Channel ensureChannel() => $_ensure(18);

  @$pb.TagNumber(27)
  ChannelsEnd get channelsEnd => $_getN(19);
  @$pb.TagNumber(27)
  set channelsEnd(ChannelsEnd value) => $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasChannelsEnd() => $_has(19);
  @$pb.TagNumber(27)
  void clearChannelsEnd() => $_clearField(27);
  @$pb.TagNumber(27)
  ChannelsEnd ensureChannelsEnd() => $_ensure(19);

  /// protocol 1.2
  @$pb.TagNumber(28)
  PinChallenge get pinChallenge => $_getN(20);
  @$pb.TagNumber(28)
  set pinChallenge(PinChallenge value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasPinChallenge() => $_has(20);
  @$pb.TagNumber(28)
  void clearPinChallenge() => $_clearField(28);
  @$pb.TagNumber(28)
  PinChallenge ensurePinChallenge() => $_ensure(20);
}

class NodeInfo extends $pb.GeneratedMessage {
  factory NodeInfo({
    $core.int? protocolVersion,
    $core.int? nodeId,
    $core.List<$core.int>? name,
    $core.List<$core.int>? ed25519Pub,
    $core.List<$core.int>? x25519Pub,
    $core.bool? legacy,
    $core.String? firmware,
    $core.int? maxTextBytes,
    $core.int? protocolMinor,
    $core.int? maxChannelTextBytes,
  }) {
    final result = NodeInfo._();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (nodeId != null) result.nodeId = nodeId;
    if (name != null) result.name = name;
    if (ed25519Pub != null) result.ed25519Pub = ed25519Pub;
    if (x25519Pub != null) result.x25519Pub = x25519Pub;
    if (legacy != null) result.legacy = legacy;
    if (firmware != null) result.firmware = firmware;
    if (maxTextBytes != null) result.maxTextBytes = maxTextBytes;
    if (protocolMinor != null) result.protocolMinor = protocolMinor;
    if (maxChannelTextBytes != null)
      result.maxChannelTextBytes = maxChannelTextBytes;
    return result;
  }

  NodeInfo._();

  factory NodeInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeInfo()..mergeFromBuffer(data, registry);
  factory NodeInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodeInfo',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: NodeInfo.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'name', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'ed25519Pub', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'x25519Pub', $pb.PbFieldType.OY)
    ..aOB(6, _omitFieldNames ? '' : 'legacy')
    ..aOS(7, _omitFieldNames ? '' : 'firmware')
    ..aI(8, _omitFieldNames ? '' : 'maxTextBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(9, _omitFieldNames ? '' : 'protocolMinor',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(10, _omitFieldNames ? '' : 'maxChannelTextBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeInfo copyWith(void Function(NodeInfo) updates) =>
      super.copyWith((message) => updates(message as NodeInfo)) as NodeInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NodeInfo() / NodeInfo.new instead')
  static NodeInfo create() => NodeInfo._();
  static $pb.GeneratedMessage $_createMessage() => NodeInfo._();
  @$core.override
  NodeInfo createEmptyInstance() => NodeInfo._();
  @$core.pragma('dart2js:noInline')
  static NodeInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodeInfo>(NodeInfo.$_createMessage);
  static NodeInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get nodeId => $_getIZ(1);
  @$pb.TagNumber(2)
  set nodeId($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearNodeId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get name => $_getN(2);
  @$pb.TagNumber(3)
  set name($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ed25519Pub => $_getN(3);
  @$pb.TagNumber(4)
  set ed25519Pub($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEd25519Pub() => $_has(3);
  @$pb.TagNumber(4)
  void clearEd25519Pub() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get x25519Pub => $_getN(4);
  @$pb.TagNumber(5)
  set x25519Pub($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasX25519Pub() => $_has(4);
  @$pb.TagNumber(5)
  void clearX25519Pub() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get legacy => $_getBF(5);
  @$pb.TagNumber(6)
  set legacy($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLegacy() => $_has(5);
  @$pb.TagNumber(6)
  void clearLegacy() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get firmware => $_getSZ(6);
  @$pb.TagNumber(7)
  set firmware($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasFirmware() => $_has(6);
  @$pb.TagNumber(7)
  void clearFirmware() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get maxTextBytes => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxTextBytes($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxTextBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxTextBytes() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get protocolMinor => $_getIZ(8);
  @$pb.TagNumber(9)
  set protocolMinor($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasProtocolMinor() => $_has(8);
  @$pb.TagNumber(9)
  void clearProtocolMinor() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get maxChannelTextBytes => $_getIZ(9);
  @$pb.TagNumber(10)
  set maxChannelTextBytes($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasMaxChannelTextBytes() => $_has(9);
  @$pb.TagNumber(10)
  void clearMaxChannelTextBytes() => $_clearField(10);
}

class TextMessage extends $pb.GeneratedMessage {
  factory TextMessage({
    $core.int? src,
    $core.int? msgId,
    $core.List<$core.int>? text,
    Position? srcPos,
  }) {
    final result = TextMessage._();
    if (src != null) result.src = src;
    if (msgId != null) result.msgId = msgId;
    if (text != null) result.text = text;
    if (srcPos != null) result.srcPos = srcPos;
    return result;
  }

  TextMessage._();

  factory TextMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TextMessage()..mergeFromBuffer(data, registry);
  factory TextMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TextMessage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TextMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: TextMessage.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'src', fieldType: $pb.PbFieldType.OF3)
    ..aI(2, _omitFieldNames ? '' : 'msgId', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'text', $pb.PbFieldType.OY)
    ..aOM<Position>(4, _omitFieldNames ? '' : 'srcPos',
        subBuilder: Position.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMessage copyWith(void Function(TextMessage) updates) =>
      super.copyWith((message) => updates(message as TextMessage))
          as TextMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TextMessage() / TextMessage.new instead')
  static TextMessage create() => TextMessage._();
  static $pb.GeneratedMessage $_createMessage() => TextMessage._();
  @$core.override
  TextMessage createEmptyInstance() => TextMessage._();
  @$core.pragma('dart2js:noInline')
  static TextMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TextMessage>(
          TextMessage.$_createMessage);
  static TextMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get src => $_getIZ(0);
  @$pb.TagNumber(1)
  set src($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSrc() => $_has(0);
  @$pb.TagNumber(1)
  void clearSrc() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get msgId => $_getIZ(1);
  @$pb.TagNumber(2)
  set msgId($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMsgId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMsgId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get text => $_getN(2);
  @$pb.TagNumber(3)
  set text($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => $_clearField(3);

  @$pb.TagNumber(4)
  Position get srcPos => $_getN(3);
  @$pb.TagNumber(4)
  set srcPos(Position value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSrcPos() => $_has(3);
  @$pb.TagNumber(4)
  void clearSrcPos() => $_clearField(4);
  @$pb.TagNumber(4)
  Position ensureSrcPos() => $_ensure(3);
}

class Delivered extends $pb.GeneratedMessage {
  factory Delivered({
    $core.int? dest,
    $core.int? msgId,
    $core.int? clientMsgId,
  }) {
    final result = Delivered._();
    if (dest != null) result.dest = dest;
    if (msgId != null) result.msgId = msgId;
    if (clientMsgId != null) result.clientMsgId = clientMsgId;
    return result;
  }

  Delivered._();

  factory Delivered.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Delivered()..mergeFromBuffer(data, registry);
  factory Delivered.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Delivered()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Delivered',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Delivered.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'dest', fieldType: $pb.PbFieldType.OF3)
    ..aI(2, _omitFieldNames ? '' : 'msgId', fieldType: $pb.PbFieldType.OF3)
    ..aI(3, _omitFieldNames ? '' : 'clientMsgId',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Delivered clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Delivered copyWith(void Function(Delivered) updates) =>
      super.copyWith((message) => updates(message as Delivered)) as Delivered;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Delivered() / Delivered.new instead')
  static Delivered create() => Delivered._();
  static $pb.GeneratedMessage $_createMessage() => Delivered._();
  @$core.override
  Delivered createEmptyInstance() => Delivered._();
  @$core.pragma('dart2js:noInline')
  static Delivered getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Delivered>(Delivered.$_createMessage);
  static Delivered? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get dest => $_getIZ(0);
  @$pb.TagNumber(1)
  set dest($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDest() => $_has(0);
  @$pb.TagNumber(1)
  void clearDest() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get msgId => $_getIZ(1);
  @$pb.TagNumber(2)
  set msgId($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMsgId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMsgId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get clientMsgId => $_getIZ(2);
  @$pb.TagNumber(3)
  set clientMsgId($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientMsgId() => $_clearField(3);
}

class SendQueued extends $pb.GeneratedMessage {
  factory SendQueued({
    $core.int? dest,
    $core.int? msgId,
    $core.int? clientMsgId,
  }) {
    final result = SendQueued._();
    if (dest != null) result.dest = dest;
    if (msgId != null) result.msgId = msgId;
    if (clientMsgId != null) result.clientMsgId = clientMsgId;
    return result;
  }

  SendQueued._();

  factory SendQueued.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SendQueued()..mergeFromBuffer(data, registry);
  factory SendQueued.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SendQueued()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendQueued',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SendQueued.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'dest', fieldType: $pb.PbFieldType.OF3)
    ..aI(2, _omitFieldNames ? '' : 'msgId', fieldType: $pb.PbFieldType.OF3)
    ..aI(3, _omitFieldNames ? '' : 'clientMsgId',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendQueued clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendQueued copyWith(void Function(SendQueued) updates) =>
      super.copyWith((message) => updates(message as SendQueued)) as SendQueued;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SendQueued() / SendQueued.new instead')
  static SendQueued create() => SendQueued._();
  static $pb.GeneratedMessage $_createMessage() => SendQueued._();
  @$core.override
  SendQueued createEmptyInstance() => SendQueued._();
  @$core.pragma('dart2js:noInline')
  static SendQueued getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendQueued>(SendQueued.$_createMessage);
  static SendQueued? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get dest => $_getIZ(0);
  @$pb.TagNumber(1)
  set dest($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDest() => $_has(0);
  @$pb.TagNumber(1)
  void clearDest() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get msgId => $_getIZ(1);
  @$pb.TagNumber(2)
  set msgId($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMsgId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMsgId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get clientMsgId => $_getIZ(2);
  @$pb.TagNumber(3)
  set clientMsgId($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientMsgId() => $_clearField(3);
}

class SosAlert extends $pb.GeneratedMessage {
  factory SosAlert({
    $core.int? src,
    $core.int? seq,
    Position? pos,
    $core.int? accuracyM,
    $core.int? batteryPct,
    $core.List<$core.int>? text,
  }) {
    final result = SosAlert._();
    if (src != null) result.src = src;
    if (seq != null) result.seq = seq;
    if (pos != null) result.pos = pos;
    if (accuracyM != null) result.accuracyM = accuracyM;
    if (batteryPct != null) result.batteryPct = batteryPct;
    if (text != null) result.text = text;
    return result;
  }

  SosAlert._();

  factory SosAlert.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosAlert()..mergeFromBuffer(data, registry);
  factory SosAlert.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosAlert()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SosAlert',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SosAlert.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'src', fieldType: $pb.PbFieldType.OF3)
    ..aI(2, _omitFieldNames ? '' : 'seq', fieldType: $pb.PbFieldType.OU3)
    ..aOM<Position>(3, _omitFieldNames ? '' : 'pos',
        subBuilder: Position.$_createMessage)
    ..aI(4, _omitFieldNames ? '' : 'accuracyM', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'batteryPct', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'text', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosAlert clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosAlert copyWith(void Function(SosAlert) updates) =>
      super.copyWith((message) => updates(message as SosAlert)) as SosAlert;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SosAlert() / SosAlert.new instead')
  static SosAlert create() => SosAlert._();
  static $pb.GeneratedMessage $_createMessage() => SosAlert._();
  @$core.override
  SosAlert createEmptyInstance() => SosAlert._();
  @$core.pragma('dart2js:noInline')
  static SosAlert getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SosAlert>(SosAlert.$_createMessage);
  static SosAlert? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get src => $_getIZ(0);
  @$pb.TagNumber(1)
  set src($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSrc() => $_has(0);
  @$pb.TagNumber(1)
  void clearSrc() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get seq => $_getIZ(1);
  @$pb.TagNumber(2)
  set seq($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSeq() => $_has(1);
  @$pb.TagNumber(2)
  void clearSeq() => $_clearField(2);

  @$pb.TagNumber(3)
  Position get pos => $_getN(2);
  @$pb.TagNumber(3)
  set pos(Position value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPos() => $_has(2);
  @$pb.TagNumber(3)
  void clearPos() => $_clearField(3);
  @$pb.TagNumber(3)
  Position ensurePos() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.int get accuracyM => $_getIZ(3);
  @$pb.TagNumber(4)
  set accuracyM($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAccuracyM() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccuracyM() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get batteryPct => $_getIZ(4);
  @$pb.TagNumber(5)
  set batteryPct($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBatteryPct() => $_has(4);
  @$pb.TagNumber(5)
  void clearBatteryPct() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get text => $_getN(5);
  @$pb.TagNumber(6)
  set text($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasText() => $_has(5);
  @$pb.TagNumber(6)
  void clearText() => $_clearField(6);
}

class SosAckReceived extends $pb.GeneratedMessage {
  factory SosAckReceived({
    $core.int? responder,
    $core.int? seq,
  }) {
    final result = SosAckReceived._();
    if (responder != null) result.responder = responder;
    if (seq != null) result.seq = seq;
    return result;
  }

  SosAckReceived._();

  factory SosAckReceived.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosAckReceived()..mergeFromBuffer(data, registry);
  factory SosAckReceived.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SosAckReceived()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SosAckReceived',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: SosAckReceived.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'responder', fieldType: $pb.PbFieldType.OF3)
    ..aI(2, _omitFieldNames ? '' : 'seq', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosAckReceived clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SosAckReceived copyWith(void Function(SosAckReceived) updates) =>
      super.copyWith((message) => updates(message as SosAckReceived))
          as SosAckReceived;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SosAckReceived() / SosAckReceived.new instead')
  static SosAckReceived create() => SosAckReceived._();
  static $pb.GeneratedMessage $_createMessage() => SosAckReceived._();
  @$core.override
  SosAckReceived createEmptyInstance() => SosAckReceived._();
  @$core.pragma('dart2js:noInline')
  static SosAckReceived getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SosAckReceived>(
          SosAckReceived.$_createMessage);
  static SosAckReceived? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get responder => $_getIZ(0);
  @$pb.TagNumber(1)
  set responder($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResponder() => $_has(0);
  @$pb.TagNumber(1)
  void clearResponder() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get seq => $_getIZ(1);
  @$pb.TagNumber(2)
  set seq($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSeq() => $_has(1);
  @$pb.TagNumber(2)
  void clearSeq() => $_clearField(2);
}

/// A neighbor's beacon. is_new: first heard, or not heard for a while.
class Neighbor extends $pb.GeneratedMessage {
  factory Neighbor({
    $core.int? nodeId,
    Position? pos,
    $core.bool? isNew,
  }) {
    final result = Neighbor._();
    if (nodeId != null) result.nodeId = nodeId;
    if (pos != null) result.pos = pos;
    if (isNew != null) result.isNew = isNew;
    return result;
  }

  Neighbor._();

  factory Neighbor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Neighbor()..mergeFromBuffer(data, registry);
  factory Neighbor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Neighbor()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Neighbor',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Neighbor.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..aOM<Position>(2, _omitFieldNames ? '' : 'pos',
        subBuilder: Position.$_createMessage)
    ..aOB(3, _omitFieldNames ? '' : 'isNew')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Neighbor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Neighbor copyWith(void Function(Neighbor) updates) =>
      super.copyWith((message) => updates(message as Neighbor)) as Neighbor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Neighbor() / Neighbor.new instead')
  static Neighbor create() => Neighbor._();
  static $pb.GeneratedMessage $_createMessage() => Neighbor._();
  @$core.override
  Neighbor createEmptyInstance() => Neighbor._();
  @$core.pragma('dart2js:noInline')
  static Neighbor getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Neighbor>(Neighbor.$_createMessage);
  static Neighbor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nodeId => $_getIZ(0);
  @$pb.TagNumber(1)
  set nodeId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  Position get pos => $_getN(1);
  @$pb.TagNumber(2)
  set pos(Position value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPos() => $_has(1);
  @$pb.TagNumber(2)
  void clearPos() => $_clearField(2);
  @$pb.TagNumber(2)
  Position ensurePos() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get isNew => $_getBF(2);
  @$pb.TagNumber(3)
  set isNew($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIsNew() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsNew() => $_clearField(3);
}

class Status extends $pb.GeneratedMessage {
  factory Status({
    $core.int? tx,
    $core.int? rx,
    $core.int? rxBad,
    $core.int? rxAuthFail,
    $core.int? delivered,
    $core.int? forwarded,
    $core.int? stored,
    $fixnum.Int64? airMs,
    $core.int? storeSize,
    $core.int? neighbors,
    $core.int? sosHeld,
    $core.bool? sosActive,
    $core.int? uptimeS,
    $core.int? clients,
    $core.int? queued,
    $core.int? batteryPct,
  }) {
    final result = Status._();
    if (tx != null) result.tx = tx;
    if (rx != null) result.rx = rx;
    if (rxBad != null) result.rxBad = rxBad;
    if (rxAuthFail != null) result.rxAuthFail = rxAuthFail;
    if (delivered != null) result.delivered = delivered;
    if (forwarded != null) result.forwarded = forwarded;
    if (stored != null) result.stored = stored;
    if (airMs != null) result.airMs = airMs;
    if (storeSize != null) result.storeSize = storeSize;
    if (neighbors != null) result.neighbors = neighbors;
    if (sosHeld != null) result.sosHeld = sosHeld;
    if (sosActive != null) result.sosActive = sosActive;
    if (uptimeS != null) result.uptimeS = uptimeS;
    if (clients != null) result.clients = clients;
    if (queued != null) result.queued = queued;
    if (batteryPct != null) result.batteryPct = batteryPct;
    return result;
  }

  Status._();

  factory Status.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Status()..mergeFromBuffer(data, registry);
  factory Status.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Status()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Status',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Status.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'tx', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'rx', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'rxBad', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'rxAuthFail', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'delivered', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'forwarded', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'stored', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'airMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(9, _omitFieldNames ? '' : 'storeSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(10, _omitFieldNames ? '' : 'neighbors', fieldType: $pb.PbFieldType.OU3)
    ..aI(11, _omitFieldNames ? '' : 'sosHeld', fieldType: $pb.PbFieldType.OU3)
    ..aOB(12, _omitFieldNames ? '' : 'sosActive')
    ..aI(13, _omitFieldNames ? '' : 'uptimeS', fieldType: $pb.PbFieldType.OU3)
    ..aI(14, _omitFieldNames ? '' : 'clients', fieldType: $pb.PbFieldType.OU3)
    ..aI(15, _omitFieldNames ? '' : 'queued', fieldType: $pb.PbFieldType.OU3)
    ..aI(16, _omitFieldNames ? '' : 'batteryPct',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Status clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Status copyWith(void Function(Status) updates) =>
      super.copyWith((message) => updates(message as Status)) as Status;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Status() / Status.new instead')
  static Status create() => Status._();
  static $pb.GeneratedMessage $_createMessage() => Status._();
  @$core.override
  Status createEmptyInstance() => Status._();
  @$core.pragma('dart2js:noInline')
  static Status getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Status>(Status.$_createMessage);
  static Status? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get tx => $_getIZ(0);
  @$pb.TagNumber(1)
  set tx($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTx() => $_has(0);
  @$pb.TagNumber(1)
  void clearTx() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get rx => $_getIZ(1);
  @$pb.TagNumber(2)
  set rx($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRx() => $_has(1);
  @$pb.TagNumber(2)
  void clearRx() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get rxBad => $_getIZ(2);
  @$pb.TagNumber(3)
  set rxBad($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRxBad() => $_has(2);
  @$pb.TagNumber(3)
  void clearRxBad() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get rxAuthFail => $_getIZ(3);
  @$pb.TagNumber(4)
  set rxAuthFail($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRxAuthFail() => $_has(3);
  @$pb.TagNumber(4)
  void clearRxAuthFail() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get delivered => $_getIZ(4);
  @$pb.TagNumber(5)
  set delivered($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDelivered() => $_has(4);
  @$pb.TagNumber(5)
  void clearDelivered() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get forwarded => $_getIZ(5);
  @$pb.TagNumber(6)
  set forwarded($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasForwarded() => $_has(5);
  @$pb.TagNumber(6)
  void clearForwarded() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get stored => $_getIZ(6);
  @$pb.TagNumber(7)
  set stored($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStored() => $_has(6);
  @$pb.TagNumber(7)
  void clearStored() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get airMs => $_getI64(7);
  @$pb.TagNumber(8)
  set airMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAirMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearAirMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get storeSize => $_getIZ(8);
  @$pb.TagNumber(9)
  set storeSize($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasStoreSize() => $_has(8);
  @$pb.TagNumber(9)
  void clearStoreSize() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get neighbors => $_getIZ(9);
  @$pb.TagNumber(10)
  set neighbors($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNeighbors() => $_has(9);
  @$pb.TagNumber(10)
  void clearNeighbors() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get sosHeld => $_getIZ(10);
  @$pb.TagNumber(11)
  set sosHeld($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSosHeld() => $_has(10);
  @$pb.TagNumber(11)
  void clearSosHeld() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.bool get sosActive => $_getBF(11);
  @$pb.TagNumber(12)
  set sosActive($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasSosActive() => $_has(11);
  @$pb.TagNumber(12)
  void clearSosActive() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get uptimeS => $_getIZ(12);
  @$pb.TagNumber(13)
  set uptimeS($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasUptimeS() => $_has(12);
  @$pb.TagNumber(13)
  void clearUptimeS() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get clients => $_getIZ(13);
  @$pb.TagNumber(14)
  set clients($core.int value) => $_setUnsignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasClients() => $_has(13);
  @$pb.TagNumber(14)
  void clearClients() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get queued => $_getIZ(14);
  @$pb.TagNumber(15)
  set queued($core.int value) => $_setUnsignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasQueued() => $_has(14);
  @$pb.TagNumber(15)
  void clearQueued() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get batteryPct => $_getIZ(15);
  @$pb.TagNumber(16)
  set batteryPct($core.int value) => $_setUnsignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasBatteryPct() => $_has(15);
  @$pb.TagNumber(16)
  void clearBatteryPct() => $_clearField(16);
}

class OwnPosition extends $pb.GeneratedMessage {
  factory OwnPosition({
    Position? pos,
  }) {
    final result = OwnPosition._();
    if (pos != null) result.pos = pos;
    return result;
  }

  OwnPosition._();

  factory OwnPosition.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OwnPosition()..mergeFromBuffer(data, registry);
  factory OwnPosition.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OwnPosition()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OwnPosition',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: OwnPosition.$_createMessage)
    ..aOM<Position>(1, _omitFieldNames ? '' : 'pos',
        subBuilder: Position.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OwnPosition clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OwnPosition copyWith(void Function(OwnPosition) updates) =>
      super.copyWith((message) => updates(message as OwnPosition))
          as OwnPosition;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OwnPosition() / OwnPosition.new instead')
  static OwnPosition create() => OwnPosition._();
  static $pb.GeneratedMessage $_createMessage() => OwnPosition._();
  @$core.override
  OwnPosition createEmptyInstance() => OwnPosition._();
  @$core.pragma('dart2js:noInline')
  static OwnPosition getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OwnPosition>(
          OwnPosition.$_createMessage);
  static OwnPosition? _defaultInstance;

  @$pb.TagNumber(1)
  Position get pos => $_getN(0);
  @$pb.TagNumber(1)
  set pos(Position value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPos() => $_has(0);
  @$pb.TagNumber(1)
  void clearPos() => $_clearField(1);
  @$pb.TagNumber(1)
  Position ensurePos() => $_ensure(0);
}

class Error extends $pb.GeneratedMessage {
  factory Error({
    Error_Code? code,
    $core.String? detail,
  }) {
    final result = Error._();
    if (code != null) result.code = code;
    if (detail != null) result.detail = detail;
    return result;
  }

  Error._();

  factory Error.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Error()..mergeFromBuffer(data, registry);
  factory Error.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Error()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Error',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Error.$_createMessage)
    ..aE<Error_Code>(1, _omitFieldNames ? '' : 'code',
        enumValues: Error_Code.values)
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Error clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Error copyWith(void Function(Error) updates) =>
      super.copyWith((message) => updates(message as Error)) as Error;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Error() / Error.new instead')
  static Error create() => Error._();
  static $pb.GeneratedMessage $_createMessage() => Error._();
  @$core.override
  Error createEmptyInstance() => Error._();
  @$core.pragma('dart2js:noInline')
  static Error getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Error>(Error.$_createMessage);
  static Error? _defaultInstance;

  @$pb.TagNumber(1)
  Error_Code get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(Error_Code value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class Contact extends $pb.GeneratedMessage {
  factory Contact({
    $core.int? nodeId,
    $core.List<$core.int>? name,
    $core.List<$core.int>? x25519Pub,
    $core.List<$core.int>? ed25519Pub,
    $core.bool? pinned,
  }) {
    final result = Contact._();
    if (nodeId != null) result.nodeId = nodeId;
    if (name != null) result.name = name;
    if (x25519Pub != null) result.x25519Pub = x25519Pub;
    if (ed25519Pub != null) result.ed25519Pub = ed25519Pub;
    if (pinned != null) result.pinned = pinned;
    return result;
  }

  Contact._();

  factory Contact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Contact()..mergeFromBuffer(data, registry);
  factory Contact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Contact()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Contact',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Contact.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'name', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'x25519Pub', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'ed25519Pub', $pb.PbFieldType.OY)
    ..aOB(5, _omitFieldNames ? '' : 'pinned')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Contact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Contact copyWith(void Function(Contact) updates) =>
      super.copyWith((message) => updates(message as Contact)) as Contact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Contact() / Contact.new instead')
  static Contact create() => Contact._();
  static $pb.GeneratedMessage $_createMessage() => Contact._();
  @$core.override
  Contact createEmptyInstance() => Contact._();
  @$core.pragma('dart2js:noInline')
  static Contact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Contact>(Contact.$_createMessage);
  static Contact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nodeId => $_getIZ(0);
  @$pb.TagNumber(1)
  set nodeId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get name => $_getN(1);
  @$pb.TagNumber(2)
  set name($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get x25519Pub => $_getN(2);
  @$pb.TagNumber(3)
  set x25519Pub($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX25519Pub() => $_has(2);
  @$pb.TagNumber(3)
  void clearX25519Pub() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ed25519Pub => $_getN(3);
  @$pb.TagNumber(4)
  set ed25519Pub($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEd25519Pub() => $_has(3);
  @$pb.TagNumber(4)
  void clearEd25519Pub() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get pinned => $_getBF(4);
  @$pb.TagNumber(5)
  set pinned($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPinned() => $_has(4);
  @$pb.TagNumber(5)
  void clearPinned() => $_clearField(5);
}

class ContactsEnd extends $pb.GeneratedMessage {
  factory ContactsEnd({
    $core.int? count,
  }) {
    final result = ContactsEnd._();
    if (count != null) result.count = count;
    return result;
  }

  ContactsEnd._();

  factory ContactsEnd.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ContactsEnd()..mergeFromBuffer(data, registry);
  factory ContactsEnd.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ContactsEnd()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ContactsEnd',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: ContactsEnd.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'count', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContactsEnd clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContactsEnd copyWith(void Function(ContactsEnd) updates) =>
      super.copyWith((message) => updates(message as ContactsEnd))
          as ContactsEnd;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ContactsEnd() / ContactsEnd.new instead')
  static ContactsEnd create() => ContactsEnd._();
  static $pb.GeneratedMessage $_createMessage() => ContactsEnd._();
  @$core.override
  ContactsEnd createEmptyInstance() => ContactsEnd._();
  @$core.pragma('dart2js:noInline')
  static ContactsEnd getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactsEnd>(
          ContactsEnd.$_createMessage);
  static ContactsEnd? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get count => $_getIZ(0);
  @$pb.TagNumber(1)
  set count($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearCount() => $_clearField(1);
}

class Ok extends $pb.GeneratedMessage {
  factory Ok() => Ok._();

  Ok._();

  factory Ok.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Ok()..mergeFromBuffer(data, registry);
  factory Ok.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Ok()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ok',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Ok.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ok clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ok copyWith(void Function(Ok) updates) =>
      super.copyWith((message) => updates(message as Ok)) as Ok;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Ok() / Ok.new instead')
  static Ok create() => Ok._();
  static $pb.GeneratedMessage $_createMessage() => Ok._();
  @$core.override
  Ok createEmptyInstance() => Ok._();
  @$core.pragma('dart2js:noInline')
  static Ok getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Ok>(Ok.$_createMessage);
  static Ok? _defaultInstance;
}

/// A verified IDENT taught us a new peer key, or a known peer's new name.
class PeerIdent extends $pb.GeneratedMessage {
  factory PeerIdent({
    $core.int? nodeId,
    $core.List<$core.int>? name,
    $core.bool? isNew,
  }) {
    final result = PeerIdent._();
    if (nodeId != null) result.nodeId = nodeId;
    if (name != null) result.name = name;
    if (isNew != null) result.isNew = isNew;
    return result;
  }

  PeerIdent._();

  factory PeerIdent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PeerIdent()..mergeFromBuffer(data, registry);
  factory PeerIdent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PeerIdent()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PeerIdent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: PeerIdent.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'name', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'isNew')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeerIdent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeerIdent copyWith(void Function(PeerIdent) updates) =>
      super.copyWith((message) => updates(message as PeerIdent)) as PeerIdent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PeerIdent() / PeerIdent.new instead')
  static PeerIdent create() => PeerIdent._();
  static $pb.GeneratedMessage $_createMessage() => PeerIdent._();
  @$core.override
  PeerIdent createEmptyInstance() => PeerIdent._();
  @$core.pragma('dart2js:noInline')
  static PeerIdent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PeerIdent>(PeerIdent.$_createMessage);
  static PeerIdent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nodeId => $_getIZ(0);
  @$pb.TagNumber(1)
  set nodeId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get name => $_getN(1);
  @$pb.TagNumber(2)
  set name($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isNew => $_getBF(2);
  @$pb.TagNumber(3)
  set isNew($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIsNew() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsNew() => $_clearField(3);
}

/// A signed IDENT for node_id carries a different key from the one held.
/// The node keeps the old key. Show a warning; accept only via AddContact.
class KeyChange extends $pb.GeneratedMessage {
  factory KeyChange({
    $core.int? nodeId,
    $core.List<$core.int>? ed25519Pub,
    $core.List<$core.int>? name,
  }) {
    final result = KeyChange._();
    if (nodeId != null) result.nodeId = nodeId;
    if (ed25519Pub != null) result.ed25519Pub = ed25519Pub;
    if (name != null) result.name = name;
    return result;
  }

  KeyChange._();

  factory KeyChange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeyChange()..mergeFromBuffer(data, registry);
  factory KeyChange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeyChange()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KeyChange',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: KeyChange.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nodeId', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ed25519Pub', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'name', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyChange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyChange copyWith(void Function(KeyChange) updates) =>
      super.copyWith((message) => updates(message as KeyChange)) as KeyChange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use KeyChange() / KeyChange.new instead')
  static KeyChange create() => KeyChange._();
  static $pb.GeneratedMessage $_createMessage() => KeyChange._();
  @$core.override
  KeyChange createEmptyInstance() => KeyChange._();
  @$core.pragma('dart2js:noInline')
  static KeyChange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KeyChange>(KeyChange.$_createMessage);
  static KeyChange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nodeId => $_getIZ(0);
  @$pb.TagNumber(1)
  set nodeId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ed25519Pub => $_getN(1);
  @$pb.TagNumber(2)
  set ed25519Pub($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEd25519Pub() => $_has(1);
  @$pb.TagNumber(2)
  void clearEd25519Pub() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get name => $_getN(2);
  @$pb.TagNumber(3)
  set name($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);
}

/// A group channel message, on a channel this node joined (protocol 1.1).
class ChannelMessage extends $pb.GeneratedMessage {
  factory ChannelMessage({
    $core.String? channel,
    $core.int? src,
    $core.int? msgId,
    $core.List<$core.int>? text,
    Position? pos,
  }) {
    final result = ChannelMessage._();
    if (channel != null) result.channel = channel;
    if (src != null) result.src = src;
    if (msgId != null) result.msgId = msgId;
    if (text != null) result.text = text;
    if (pos != null) result.pos = pos;
    return result;
  }

  ChannelMessage._();

  factory ChannelMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChannelMessage()..mergeFromBuffer(data, registry);
  factory ChannelMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChannelMessage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: ChannelMessage.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'channel')
    ..aI(2, _omitFieldNames ? '' : 'src', fieldType: $pb.PbFieldType.OF3)
    ..aI(3, _omitFieldNames ? '' : 'msgId', fieldType: $pb.PbFieldType.OF3)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'text', $pb.PbFieldType.OY)
    ..aOM<Position>(5, _omitFieldNames ? '' : 'pos',
        subBuilder: Position.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMessage copyWith(void Function(ChannelMessage) updates) =>
      super.copyWith((message) => updates(message as ChannelMessage))
          as ChannelMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChannelMessage() / ChannelMessage.new instead')
  static ChannelMessage create() => ChannelMessage._();
  static $pb.GeneratedMessage $_createMessage() => ChannelMessage._();
  @$core.override
  ChannelMessage createEmptyInstance() => ChannelMessage._();
  @$core.pragma('dart2js:noInline')
  static ChannelMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelMessage>(
          ChannelMessage.$_createMessage);
  static ChannelMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get channel => $_getSZ(0);
  @$pb.TagNumber(1)
  set channel($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannel() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannel() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get src => $_getIZ(1);
  @$pb.TagNumber(2)
  set src($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSrc() => $_has(1);
  @$pb.TagNumber(2)
  void clearSrc() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get msgId => $_getIZ(2);
  @$pb.TagNumber(3)
  set msgId($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get text => $_getN(3);
  @$pb.TagNumber(4)
  set text($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasText() => $_has(3);
  @$pb.TagNumber(4)
  void clearText() => $_clearField(4);

  @$pb.TagNumber(5)
  Position get pos => $_getN(4);
  @$pb.TagNumber(5)
  set pos(Position value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPos() => $_has(4);
  @$pb.TagNumber(5)
  void clearPos() => $_clearField(5);
  @$pb.TagNumber(5)
  Position ensurePos() => $_ensure(4);
}

class Channel extends $pb.GeneratedMessage {
  factory Channel({
    $core.String? name,
    $core.List<$core.int>? psk,
  }) {
    final result = Channel._();
    if (name != null) result.name = name;
    if (psk != null) result.psk = psk;
    return result;
  }

  Channel._();

  factory Channel.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Channel()..mergeFromBuffer(data, registry);
  factory Channel.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Channel()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Channel',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: Channel.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'psk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Channel clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Channel copyWith(void Function(Channel) updates) =>
      super.copyWith((message) => updates(message as Channel)) as Channel;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Channel() / Channel.new instead')
  static Channel create() => Channel._();
  static $pb.GeneratedMessage $_createMessage() => Channel._();
  @$core.override
  Channel createEmptyInstance() => Channel._();
  @$core.pragma('dart2js:noInline')
  static Channel getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Channel>(Channel.$_createMessage);
  static Channel? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get psk => $_getN(1);
  @$pb.TagNumber(2)
  set psk($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPsk() => $_has(1);
  @$pb.TagNumber(2)
  void clearPsk() => $_clearField(2);
}

class ChannelsEnd extends $pb.GeneratedMessage {
  factory ChannelsEnd({
    $core.int? count,
  }) {
    final result = ChannelsEnd._();
    if (count != null) result.count = count;
    return result;
  }

  ChannelsEnd._();

  factory ChannelsEnd.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChannelsEnd()..mergeFromBuffer(data, registry);
  factory ChannelsEnd.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChannelsEnd()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelsEnd',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: ChannelsEnd.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'count', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelsEnd clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelsEnd copyWith(void Function(ChannelsEnd) updates) =>
      super.copyWith((message) => updates(message as ChannelsEnd))
          as ChannelsEnd;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChannelsEnd() / ChannelsEnd.new instead')
  static ChannelsEnd create() => ChannelsEnd._();
  static $pb.GeneratedMessage $_createMessage() => ChannelsEnd._();
  @$core.override
  ChannelsEnd createEmptyInstance() => ChannelsEnd._();
  @$core.pragma('dart2js:noInline')
  static ChannelsEnd getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelsEnd>(
          ChannelsEnd.$_createMessage);
  static ChannelsEnd? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get count => $_getIZ(0);
  @$pb.TagNumber(1)
  set count($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearCount() => $_clearField(1);
}

/// Reply to a Hello without a proof on a link that needs a PIN (protocol 1.3).
/// Send Hello again with client_share and pin_proof; every frame after that is
/// encrypted. Each nonce works once.
class PinChallenge extends $pb.GeneratedMessage {
  factory PinChallenge({
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? serverShare,
  }) {
    final result = PinChallenge._();
    if (nonce != null) result.nonce = nonce;
    if (serverShare != null) result.serverShare = serverShare;
    return result;
  }

  PinChallenge._();

  factory PinChallenge.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PinChallenge()..mergeFromBuffer(data, registry);
  factory PinChallenge.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PinChallenge()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PinChallenge',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'ghostwave.client.v1'),
      createEmptyInstance: PinChallenge.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'serverShare', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PinChallenge clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PinChallenge copyWith(void Function(PinChallenge) updates) =>
      super.copyWith((message) => updates(message as PinChallenge))
          as PinChallenge;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PinChallenge() / PinChallenge.new instead')
  static PinChallenge create() => PinChallenge._();
  static $pb.GeneratedMessage $_createMessage() => PinChallenge._();
  @$core.override
  PinChallenge createEmptyInstance() => PinChallenge._();
  @$core.pragma('dart2js:noInline')
  static PinChallenge getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PinChallenge>(
          PinChallenge.$_createMessage);
  static PinChallenge? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nonce => $_getN(0);
  @$pb.TagNumber(1)
  set nonce($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNonce() => $_has(0);
  @$pb.TagNumber(1)
  void clearNonce() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get serverShare => $_getN(1);
  @$pb.TagNumber(2)
  set serverShare($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerShare() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerShare() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
