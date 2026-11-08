// This is a generated file - do not edit.
//
// Generated from ghostwave.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use positionDescriptor instead')
const Position$json = {
  '1': 'Position',
  '2': [
    {'1': 'lat_e7', '3': 1, '4': 1, '5': 17, '10': 'latE7'},
    {'1': 'lon_e7', '3': 2, '4': 1, '5': 17, '10': 'lonE7'},
  ],
};

/// Descriptor for `Position`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List positionDescriptor = $convert.base64Decode(
    'CghQb3NpdGlvbhIVCgZsYXRfZTcYASABKBFSBWxhdEU3EhUKBmxvbl9lNxgCIAEoEVIFbG9uRT'
    'c=');

@$core.Deprecated('Use toRadioDescriptor instead')
const ToRadio$json = {
  '1': 'ToRadio',
  '2': [
    {'1': 'req_id', '3': 1, '4': 1, '5': 13, '10': 'reqId'},
    {
      '1': 'hello',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Hello',
      '9': 0,
      '10': 'hello'
    },
    {
      '1': 'send_text',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SendText',
      '9': 0,
      '10': 'sendText'
    },
    {
      '1': 'add_contact',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.AddContact',
      '9': 0,
      '10': 'addContact'
    },
    {
      '1': 'list_contacts',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.ListContacts',
      '9': 0,
      '10': 'listContacts'
    },
    {
      '1': 'set_known_position',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SetKnownPosition',
      '9': 0,
      '10': 'setKnownPosition'
    },
    {
      '1': 'sos_start',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SosStart',
      '9': 0,
      '10': 'sosStart'
    },
    {
      '1': 'sos_stop',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SosStop',
      '9': 0,
      '10': 'sosStop'
    },
    {
      '1': 'sos_ack',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SosAck',
      '9': 0,
      '10': 'sosAck'
    },
    {
      '1': 'get_status',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.GetStatus',
      '9': 0,
      '10': 'getStatus'
    },
    {
      '1': 'get_position',
      '3': 19,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.GetPosition',
      '9': 0,
      '10': 'getPosition'
    },
    {
      '1': 'set_own_position',
      '3': 20,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SetOwnPosition',
      '9': 0,
      '10': 'setOwnPosition'
    },
    {
      '1': 'send_channel_text',
      '3': 21,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SendChannelText',
      '9': 0,
      '10': 'sendChannelText'
    },
    {
      '1': 'add_channel',
      '3': 22,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.AddChannel',
      '9': 0,
      '10': 'addChannel'
    },
    {
      '1': 'remove_channel',
      '3': 23,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.RemoveChannel',
      '9': 0,
      '10': 'removeChannel'
    },
    {
      '1': 'list_channels',
      '3': 24,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.ListChannels',
      '9': 0,
      '10': 'listChannels'
    },
    {
      '1': 'set_name',
      '3': 25,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SetName',
      '9': 0,
      '10': 'setName'
    },
  ],
  '8': [
    {'1': 'request'},
  ],
};

/// Descriptor for `ToRadio`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toRadioDescriptor = $convert.base64Decode(
    'CgdUb1JhZGlvEhUKBnJlcV9pZBgBIAEoDVIFcmVxSWQSMgoFaGVsbG8YCiABKAsyGi5naG9zdH'
    'dhdmUuY2xpZW50LnYxLkhlbGxvSABSBWhlbGxvEjwKCXNlbmRfdGV4dBgLIAEoCzIdLmdob3N0'
    'd2F2ZS5jbGllbnQudjEuU2VuZFRleHRIAFIIc2VuZFRleHQSQgoLYWRkX2NvbnRhY3QYDCABKA'
    'syHy5naG9zdHdhdmUuY2xpZW50LnYxLkFkZENvbnRhY3RIAFIKYWRkQ29udGFjdBJICg1saXN0'
    'X2NvbnRhY3RzGA0gASgLMiEuZ2hvc3R3YXZlLmNsaWVudC52MS5MaXN0Q29udGFjdHNIAFIMbG'
    'lzdENvbnRhY3RzElUKEnNldF9rbm93bl9wb3NpdGlvbhgOIAEoCzIlLmdob3N0d2F2ZS5jbGll'
    'bnQudjEuU2V0S25vd25Qb3NpdGlvbkgAUhBzZXRLbm93blBvc2l0aW9uEjwKCXNvc19zdGFydB'
    'gPIAEoCzIdLmdob3N0d2F2ZS5jbGllbnQudjEuU29zU3RhcnRIAFIIc29zU3RhcnQSOQoIc29z'
    'X3N0b3AYECABKAsyHC5naG9zdHdhdmUuY2xpZW50LnYxLlNvc1N0b3BIAFIHc29zU3RvcBI2Cg'
    'dzb3NfYWNrGBEgASgLMhsuZ2hvc3R3YXZlLmNsaWVudC52MS5Tb3NBY2tIAFIGc29zQWNrEj8K'
    'CmdldF9zdGF0dXMYEiABKAsyHi5naG9zdHdhdmUuY2xpZW50LnYxLkdldFN0YXR1c0gAUglnZX'
    'RTdGF0dXMSRQoMZ2V0X3Bvc2l0aW9uGBMgASgLMiAuZ2hvc3R3YXZlLmNsaWVudC52MS5HZXRQ'
    'b3NpdGlvbkgAUgtnZXRQb3NpdGlvbhJPChBzZXRfb3duX3Bvc2l0aW9uGBQgASgLMiMuZ2hvc3'
    'R3YXZlLmNsaWVudC52MS5TZXRPd25Qb3NpdGlvbkgAUg5zZXRPd25Qb3NpdGlvbhJSChFzZW5k'
    'X2NoYW5uZWxfdGV4dBgVIAEoCzIkLmdob3N0d2F2ZS5jbGllbnQudjEuU2VuZENoYW5uZWxUZX'
    'h0SABSD3NlbmRDaGFubmVsVGV4dBJCCgthZGRfY2hhbm5lbBgWIAEoCzIfLmdob3N0d2F2ZS5j'
    'bGllbnQudjEuQWRkQ2hhbm5lbEgAUgphZGRDaGFubmVsEksKDnJlbW92ZV9jaGFubmVsGBcgAS'
    'gLMiIuZ2hvc3R3YXZlLmNsaWVudC52MS5SZW1vdmVDaGFubmVsSABSDXJlbW92ZUNoYW5uZWwS'
    'SAoNbGlzdF9jaGFubmVscxgYIAEoCzIhLmdob3N0d2F2ZS5jbGllbnQudjEuTGlzdENoYW5uZW'
    'xzSABSDGxpc3RDaGFubmVscxI5CghzZXRfbmFtZRgZIAEoCzIcLmdob3N0d2F2ZS5jbGllbnQu'
    'djEuU2V0TmFtZUgAUgdzZXROYW1lQgkKB3JlcXVlc3Q=');

@$core.Deprecated('Use helloDescriptor instead')
const Hello$json = {
  '1': 'Hello',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {'1': 'client_name', '3': 2, '4': 1, '5': 9, '10': 'clientName'},
  ],
};

/// Descriptor for `Hello`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List helloDescriptor = $convert.base64Decode(
    'CgVIZWxsbxIpChBwcm90b2NvbF92ZXJzaW9uGAEgASgNUg9wcm90b2NvbFZlcnNpb24SHwoLY2'
    'xpZW50X25hbWUYAiABKAlSCmNsaWVudE5hbWU=');

@$core.Deprecated('Use sendTextDescriptor instead')
const SendText$json = {
  '1': 'SendText',
  '2': [
    {'1': 'dest', '3': 1, '4': 1, '5': 7, '10': 'dest'},
    {'1': 'text', '3': 2, '4': 1, '5': 12, '10': 'text'},
    {'1': 'client_msg_id', '3': 3, '4': 1, '5': 13, '10': 'clientMsgId'},
  ],
};

/// Descriptor for `SendText`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendTextDescriptor = $convert.base64Decode(
    'CghTZW5kVGV4dBISCgRkZXN0GAEgASgHUgRkZXN0EhIKBHRleHQYAiABKAxSBHRleHQSIgoNY2'
    'xpZW50X21zZ19pZBgDIAEoDVILY2xpZW50TXNnSWQ=');

@$core.Deprecated('Use addContactDescriptor instead')
const AddContact$json = {
  '1': 'AddContact',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 7, '10': 'nodeId'},
    {'1': 'ed25519_pub', '3': 2, '4': 1, '5': 12, '10': 'ed25519Pub'},
    {'1': 'x25519_pub', '3': 3, '4': 1, '5': 12, '10': 'x25519Pub'},
    {'1': 'name', '3': 4, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `AddContact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addContactDescriptor = $convert.base64Decode(
    'CgpBZGRDb250YWN0EhcKB25vZGVfaWQYASABKAdSBm5vZGVJZBIfCgtlZDI1NTE5X3B1YhgCIA'
    'EoDFIKZWQyNTUxOVB1YhIdCgp4MjU1MTlfcHViGAMgASgMUgl4MjU1MTlQdWISEgoEbmFtZRgE'
    'IAEoCVIEbmFtZQ==');

@$core.Deprecated('Use listContactsDescriptor instead')
const ListContacts$json = {
  '1': 'ListContacts',
};

/// Descriptor for `ListContacts`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listContactsDescriptor =
    $convert.base64Decode('CgxMaXN0Q29udGFjdHM=');

@$core.Deprecated('Use setKnownPositionDescriptor instead')
const SetKnownPosition$json = {
  '1': 'SetKnownPosition',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 7, '10': 'nodeId'},
    {
      '1': 'pos',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Position',
      '10': 'pos'
    },
  ],
};

/// Descriptor for `SetKnownPosition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setKnownPositionDescriptor = $convert.base64Decode(
    'ChBTZXRLbm93blBvc2l0aW9uEhcKB25vZGVfaWQYASABKAdSBm5vZGVJZBIvCgNwb3MYAiABKA'
    'syHS5naG9zdHdhdmUuY2xpZW50LnYxLlBvc2l0aW9uUgNwb3M=');

@$core.Deprecated('Use sosStartDescriptor instead')
const SosStart$json = {
  '1': 'SosStart',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 12, '10': 'text'},
    {
      '1': 'battery_pct',
      '3': 2,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'batteryPct',
      '17': true
    },
    {
      '1': 'accuracy_m',
      '3': 3,
      '4': 1,
      '5': 13,
      '9': 1,
      '10': 'accuracyM',
      '17': true
    },
  ],
  '8': [
    {'1': '_battery_pct'},
    {'1': '_accuracy_m'},
  ],
};

/// Descriptor for `SosStart`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sosStartDescriptor = $convert.base64Decode(
    'CghTb3NTdGFydBISCgR0ZXh0GAEgASgMUgR0ZXh0EiQKC2JhdHRlcnlfcGN0GAIgASgNSABSCm'
    'JhdHRlcnlQY3SIAQESIgoKYWNjdXJhY3lfbRgDIAEoDUgBUglhY2N1cmFjeU2IAQFCDgoMX2Jh'
    'dHRlcnlfcGN0Qg0KC19hY2N1cmFjeV9t');

@$core.Deprecated('Use sosStopDescriptor instead')
const SosStop$json = {
  '1': 'SosStop',
};

/// Descriptor for `SosStop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sosStopDescriptor =
    $convert.base64Decode('CgdTb3NTdG9w');

@$core.Deprecated('Use sosAckDescriptor instead')
const SosAck$json = {
  '1': 'SosAck',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 7, '10': 'nodeId'},
  ],
};

/// Descriptor for `SosAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sosAckDescriptor =
    $convert.base64Decode('CgZTb3NBY2sSFwoHbm9kZV9pZBgBIAEoB1IGbm9kZUlk');

@$core.Deprecated('Use getStatusDescriptor instead')
const GetStatus$json = {
  '1': 'GetStatus',
};

/// Descriptor for `GetStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getStatusDescriptor =
    $convert.base64Decode('CglHZXRTdGF0dXM=');

@$core.Deprecated('Use getPositionDescriptor instead')
const GetPosition$json = {
  '1': 'GetPosition',
};

/// Descriptor for `GetPosition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPositionDescriptor =
    $convert.base64Decode('CgtHZXRQb3NpdGlvbg==');

@$core.Deprecated('Use setOwnPositionDescriptor instead')
const SetOwnPosition$json = {
  '1': 'SetOwnPosition',
  '2': [
    {
      '1': 'pos',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Position',
      '10': 'pos'
    },
  ],
};

/// Descriptor for `SetOwnPosition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setOwnPositionDescriptor = $convert.base64Decode(
    'Cg5TZXRPd25Qb3NpdGlvbhIvCgNwb3MYASABKAsyHS5naG9zdHdhdmUuY2xpZW50LnYxLlBvc2'
    'l0aW9uUgNwb3M=');

@$core.Deprecated('Use sendChannelTextDescriptor instead')
const SendChannelText$json = {
  '1': 'SendChannelText',
  '2': [
    {'1': 'channel', '3': 1, '4': 1, '5': 9, '10': 'channel'},
    {'1': 'text', '3': 2, '4': 1, '5': 12, '10': 'text'},
    {'1': 'client_msg_id', '3': 3, '4': 1, '5': 13, '10': 'clientMsgId'},
  ],
};

/// Descriptor for `SendChannelText`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendChannelTextDescriptor = $convert.base64Decode(
    'Cg9TZW5kQ2hhbm5lbFRleHQSGAoHY2hhbm5lbBgBIAEoCVIHY2hhbm5lbBISCgR0ZXh0GAIgAS'
    'gMUgR0ZXh0EiIKDWNsaWVudF9tc2dfaWQYAyABKA1SC2NsaWVudE1zZ0lk');

@$core.Deprecated('Use addChannelDescriptor instead')
const AddChannel$json = {
  '1': 'AddChannel',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'psk', '3': 2, '4': 1, '5': 12, '10': 'psk'},
  ],
};

/// Descriptor for `AddChannel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addChannelDescriptor = $convert.base64Decode(
    'CgpBZGRDaGFubmVsEhIKBG5hbWUYASABKAlSBG5hbWUSEAoDcHNrGAIgASgMUgNwc2s=');

@$core.Deprecated('Use removeChannelDescriptor instead')
const RemoveChannel$json = {
  '1': 'RemoveChannel',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `RemoveChannel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List removeChannelDescriptor =
    $convert.base64Decode('Cg1SZW1vdmVDaGFubmVsEhIKBG5hbWUYASABKAlSBG5hbWU=');

@$core.Deprecated('Use listChannelsDescriptor instead')
const ListChannels$json = {
  '1': 'ListChannels',
};

/// Descriptor for `ListChannels`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listChannelsDescriptor =
    $convert.base64Decode('CgxMaXN0Q2hhbm5lbHM=');

@$core.Deprecated('Use setNameDescriptor instead')
const SetName$json = {
  '1': 'SetName',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `SetName`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setNameDescriptor =
    $convert.base64Decode('CgdTZXROYW1lEhIKBG5hbWUYASABKAlSBG5hbWU=');

@$core.Deprecated('Use fromRadioDescriptor instead')
const FromRadio$json = {
  '1': 'FromRadio',
  '2': [
    {'1': 'req_id', '3': 1, '4': 1, '5': 13, '10': 'reqId'},
    {'1': 'replayed', '3': 2, '4': 1, '5': 8, '10': 'replayed'},
    {
      '1': 'node_info',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.NodeInfo',
      '9': 0,
      '10': 'nodeInfo'
    },
    {
      '1': 'text',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.TextMessage',
      '9': 0,
      '10': 'text'
    },
    {
      '1': 'delivered',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Delivered',
      '9': 0,
      '10': 'delivered'
    },
    {
      '1': 'sos',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SosAlert',
      '9': 0,
      '10': 'sos'
    },
    {
      '1': 'sos_ack',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SosAckReceived',
      '9': 0,
      '10': 'sosAck'
    },
    {
      '1': 'neighbor',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Neighbor',
      '9': 0,
      '10': 'neighbor'
    },
    {
      '1': 'status',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Status',
      '9': 0,
      '10': 'status'
    },
    {
      '1': 'position',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.OwnPosition',
      '9': 0,
      '10': 'position'
    },
    {
      '1': 'error',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Error',
      '9': 0,
      '10': 'error'
    },
    {
      '1': 'contact',
      '3': 19,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Contact',
      '9': 0,
      '10': 'contact'
    },
    {
      '1': 'contacts_end',
      '3': 20,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.ContactsEnd',
      '9': 0,
      '10': 'contactsEnd'
    },
    {
      '1': 'send_queued',
      '3': 21,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.SendQueued',
      '9': 0,
      '10': 'sendQueued'
    },
    {
      '1': 'ok',
      '3': 22,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Ok',
      '9': 0,
      '10': 'ok'
    },
    {
      '1': 'peer_ident',
      '3': 23,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.PeerIdent',
      '9': 0,
      '10': 'peerIdent'
    },
    {
      '1': 'key_change',
      '3': 24,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.KeyChange',
      '9': 0,
      '10': 'keyChange'
    },
    {
      '1': 'channel_message',
      '3': 25,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.ChannelMessage',
      '9': 0,
      '10': 'channelMessage'
    },
    {
      '1': 'channel',
      '3': 26,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Channel',
      '9': 0,
      '10': 'channel'
    },
    {
      '1': 'channels_end',
      '3': 27,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.ChannelsEnd',
      '9': 0,
      '10': 'channelsEnd'
    },
  ],
  '8': [
    {'1': 'event'},
  ],
};

/// Descriptor for `FromRadio`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fromRadioDescriptor = $convert.base64Decode(
    'CglGcm9tUmFkaW8SFQoGcmVxX2lkGAEgASgNUgVyZXFJZBIaCghyZXBsYXllZBgCIAEoCFIIcm'
    'VwbGF5ZWQSPAoJbm9kZV9pbmZvGAogASgLMh0uZ2hvc3R3YXZlLmNsaWVudC52MS5Ob2RlSW5m'
    'b0gAUghub2RlSW5mbxI2CgR0ZXh0GAsgASgLMiAuZ2hvc3R3YXZlLmNsaWVudC52MS5UZXh0TW'
    'Vzc2FnZUgAUgR0ZXh0Ej4KCWRlbGl2ZXJlZBgMIAEoCzIeLmdob3N0d2F2ZS5jbGllbnQudjEu'
    'RGVsaXZlcmVkSABSCWRlbGl2ZXJlZBIxCgNzb3MYDSABKAsyHS5naG9zdHdhdmUuY2xpZW50Ln'
    'YxLlNvc0FsZXJ0SABSA3NvcxI+Cgdzb3NfYWNrGA4gASgLMiMuZ2hvc3R3YXZlLmNsaWVudC52'
    'MS5Tb3NBY2tSZWNlaXZlZEgAUgZzb3NBY2sSOwoIbmVpZ2hib3IYDyABKAsyHS5naG9zdHdhdm'
    'UuY2xpZW50LnYxLk5laWdoYm9ySABSCG5laWdoYm9yEjUKBnN0YXR1cxgQIAEoCzIbLmdob3N0'
    'd2F2ZS5jbGllbnQudjEuU3RhdHVzSABSBnN0YXR1cxI+Cghwb3NpdGlvbhgRIAEoCzIgLmdob3'
    'N0d2F2ZS5jbGllbnQudjEuT3duUG9zaXRpb25IAFIIcG9zaXRpb24SMgoFZXJyb3IYEiABKAsy'
    'Gi5naG9zdHdhdmUuY2xpZW50LnYxLkVycm9ySABSBWVycm9yEjgKB2NvbnRhY3QYEyABKAsyHC'
    '5naG9zdHdhdmUuY2xpZW50LnYxLkNvbnRhY3RIAFIHY29udGFjdBJFCgxjb250YWN0c19lbmQY'
    'FCABKAsyIC5naG9zdHdhdmUuY2xpZW50LnYxLkNvbnRhY3RzRW5kSABSC2NvbnRhY3RzRW5kEk'
    'IKC3NlbmRfcXVldWVkGBUgASgLMh8uZ2hvc3R3YXZlLmNsaWVudC52MS5TZW5kUXVldWVkSABS'
    'CnNlbmRRdWV1ZWQSKQoCb2sYFiABKAsyFy5naG9zdHdhdmUuY2xpZW50LnYxLk9rSABSAm9rEj'
    '8KCnBlZXJfaWRlbnQYFyABKAsyHi5naG9zdHdhdmUuY2xpZW50LnYxLlBlZXJJZGVudEgAUglw'
    'ZWVySWRlbnQSPwoKa2V5X2NoYW5nZRgYIAEoCzIeLmdob3N0d2F2ZS5jbGllbnQudjEuS2V5Q2'
    'hhbmdlSABSCWtleUNoYW5nZRJOCg9jaGFubmVsX21lc3NhZ2UYGSABKAsyIy5naG9zdHdhdmUu'
    'Y2xpZW50LnYxLkNoYW5uZWxNZXNzYWdlSABSDmNoYW5uZWxNZXNzYWdlEjgKB2NoYW5uZWwYGi'
    'ABKAsyHC5naG9zdHdhdmUuY2xpZW50LnYxLkNoYW5uZWxIAFIHY2hhbm5lbBJFCgxjaGFubmVs'
    'c19lbmQYGyABKAsyIC5naG9zdHdhdmUuY2xpZW50LnYxLkNoYW5uZWxzRW5kSABSC2NoYW5uZW'
    'xzRW5kQgcKBWV2ZW50');

@$core.Deprecated('Use nodeInfoDescriptor instead')
const NodeInfo$json = {
  '1': 'NodeInfo',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {'1': 'node_id', '3': 2, '4': 1, '5': 7, '10': 'nodeId'},
    {'1': 'name', '3': 3, '4': 1, '5': 12, '10': 'name'},
    {'1': 'ed25519_pub', '3': 4, '4': 1, '5': 12, '10': 'ed25519Pub'},
    {'1': 'x25519_pub', '3': 5, '4': 1, '5': 12, '10': 'x25519Pub'},
    {'1': 'legacy', '3': 6, '4': 1, '5': 8, '10': 'legacy'},
    {'1': 'firmware', '3': 7, '4': 1, '5': 9, '10': 'firmware'},
    {'1': 'max_text_bytes', '3': 8, '4': 1, '5': 13, '10': 'maxTextBytes'},
    {'1': 'protocol_minor', '3': 9, '4': 1, '5': 13, '10': 'protocolMinor'},
    {
      '1': 'max_channel_text_bytes',
      '3': 10,
      '4': 1,
      '5': 13,
      '10': 'maxChannelTextBytes'
    },
  ],
};

/// Descriptor for `NodeInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nodeInfoDescriptor = $convert.base64Decode(
    'CghOb2RlSW5mbxIpChBwcm90b2NvbF92ZXJzaW9uGAEgASgNUg9wcm90b2NvbFZlcnNpb24SFw'
    'oHbm9kZV9pZBgCIAEoB1IGbm9kZUlkEhIKBG5hbWUYAyABKAxSBG5hbWUSHwoLZWQyNTUxOV9w'
    'dWIYBCABKAxSCmVkMjU1MTlQdWISHQoKeDI1NTE5X3B1YhgFIAEoDFIJeDI1NTE5UHViEhYKBm'
    'xlZ2FjeRgGIAEoCFIGbGVnYWN5EhoKCGZpcm13YXJlGAcgASgJUghmaXJtd2FyZRIkCg5tYXhf'
    'dGV4dF9ieXRlcxgIIAEoDVIMbWF4VGV4dEJ5dGVzEiUKDnByb3RvY29sX21pbm9yGAkgASgNUg'
    '1wcm90b2NvbE1pbm9yEjMKFm1heF9jaGFubmVsX3RleHRfYnl0ZXMYCiABKA1SE21heENoYW5u'
    'ZWxUZXh0Qnl0ZXM=');

@$core.Deprecated('Use textMessageDescriptor instead')
const TextMessage$json = {
  '1': 'TextMessage',
  '2': [
    {'1': 'src', '3': 1, '4': 1, '5': 7, '10': 'src'},
    {'1': 'msg_id', '3': 2, '4': 1, '5': 7, '10': 'msgId'},
    {'1': 'text', '3': 3, '4': 1, '5': 12, '10': 'text'},
    {
      '1': 'src_pos',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Position',
      '10': 'srcPos'
    },
  ],
};

/// Descriptor for `TextMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textMessageDescriptor = $convert.base64Decode(
    'CgtUZXh0TWVzc2FnZRIQCgNzcmMYASABKAdSA3NyYxIVCgZtc2dfaWQYAiABKAdSBW1zZ0lkEh'
    'IKBHRleHQYAyABKAxSBHRleHQSNgoHc3JjX3BvcxgEIAEoCzIdLmdob3N0d2F2ZS5jbGllbnQu'
    'djEuUG9zaXRpb25SBnNyY1Bvcw==');

@$core.Deprecated('Use deliveredDescriptor instead')
const Delivered$json = {
  '1': 'Delivered',
  '2': [
    {'1': 'dest', '3': 1, '4': 1, '5': 7, '10': 'dest'},
    {'1': 'msg_id', '3': 2, '4': 1, '5': 7, '10': 'msgId'},
    {'1': 'client_msg_id', '3': 3, '4': 1, '5': 13, '10': 'clientMsgId'},
  ],
};

/// Descriptor for `Delivered`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deliveredDescriptor = $convert.base64Decode(
    'CglEZWxpdmVyZWQSEgoEZGVzdBgBIAEoB1IEZGVzdBIVCgZtc2dfaWQYAiABKAdSBW1zZ0lkEi'
    'IKDWNsaWVudF9tc2dfaWQYAyABKA1SC2NsaWVudE1zZ0lk');

@$core.Deprecated('Use sendQueuedDescriptor instead')
const SendQueued$json = {
  '1': 'SendQueued',
  '2': [
    {'1': 'dest', '3': 1, '4': 1, '5': 7, '10': 'dest'},
    {'1': 'msg_id', '3': 2, '4': 1, '5': 7, '10': 'msgId'},
    {'1': 'client_msg_id', '3': 3, '4': 1, '5': 13, '10': 'clientMsgId'},
  ],
};

/// Descriptor for `SendQueued`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendQueuedDescriptor = $convert.base64Decode(
    'CgpTZW5kUXVldWVkEhIKBGRlc3QYASABKAdSBGRlc3QSFQoGbXNnX2lkGAIgASgHUgVtc2dJZB'
    'IiCg1jbGllbnRfbXNnX2lkGAMgASgNUgtjbGllbnRNc2dJZA==');

@$core.Deprecated('Use sosAlertDescriptor instead')
const SosAlert$json = {
  '1': 'SosAlert',
  '2': [
    {'1': 'src', '3': 1, '4': 1, '5': 7, '10': 'src'},
    {'1': 'seq', '3': 2, '4': 1, '5': 13, '10': 'seq'},
    {
      '1': 'pos',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Position',
      '10': 'pos'
    },
    {
      '1': 'accuracy_m',
      '3': 4,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'accuracyM',
      '17': true
    },
    {
      '1': 'battery_pct',
      '3': 5,
      '4': 1,
      '5': 13,
      '9': 1,
      '10': 'batteryPct',
      '17': true
    },
    {'1': 'text', '3': 6, '4': 1, '5': 12, '10': 'text'},
  ],
  '8': [
    {'1': '_accuracy_m'},
    {'1': '_battery_pct'},
  ],
};

/// Descriptor for `SosAlert`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sosAlertDescriptor = $convert.base64Decode(
    'CghTb3NBbGVydBIQCgNzcmMYASABKAdSA3NyYxIQCgNzZXEYAiABKA1SA3NlcRIvCgNwb3MYAy'
    'ABKAsyHS5naG9zdHdhdmUuY2xpZW50LnYxLlBvc2l0aW9uUgNwb3MSIgoKYWNjdXJhY3lfbRgE'
    'IAEoDUgAUglhY2N1cmFjeU2IAQESJAoLYmF0dGVyeV9wY3QYBSABKA1IAVIKYmF0dGVyeVBjdI'
    'gBARISCgR0ZXh0GAYgASgMUgR0ZXh0Qg0KC19hY2N1cmFjeV9tQg4KDF9iYXR0ZXJ5X3BjdA==');

@$core.Deprecated('Use sosAckReceivedDescriptor instead')
const SosAckReceived$json = {
  '1': 'SosAckReceived',
  '2': [
    {'1': 'responder', '3': 1, '4': 1, '5': 7, '10': 'responder'},
    {'1': 'seq', '3': 2, '4': 1, '5': 13, '10': 'seq'},
  ],
};

/// Descriptor for `SosAckReceived`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sosAckReceivedDescriptor = $convert.base64Decode(
    'Cg5Tb3NBY2tSZWNlaXZlZBIcCglyZXNwb25kZXIYASABKAdSCXJlc3BvbmRlchIQCgNzZXEYAi'
    'ABKA1SA3NlcQ==');

@$core.Deprecated('Use neighborDescriptor instead')
const Neighbor$json = {
  '1': 'Neighbor',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 7, '10': 'nodeId'},
    {
      '1': 'pos',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Position',
      '10': 'pos'
    },
    {'1': 'is_new', '3': 3, '4': 1, '5': 8, '10': 'isNew'},
  ],
};

/// Descriptor for `Neighbor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List neighborDescriptor = $convert.base64Decode(
    'CghOZWlnaGJvchIXCgdub2RlX2lkGAEgASgHUgZub2RlSWQSLwoDcG9zGAIgASgLMh0uZ2hvc3'
    'R3YXZlLmNsaWVudC52MS5Qb3NpdGlvblIDcG9zEhUKBmlzX25ldxgDIAEoCFIFaXNOZXc=');

@$core.Deprecated('Use statusDescriptor instead')
const Status$json = {
  '1': 'Status',
  '2': [
    {'1': 'tx', '3': 1, '4': 1, '5': 13, '10': 'tx'},
    {'1': 'rx', '3': 2, '4': 1, '5': 13, '10': 'rx'},
    {'1': 'rx_bad', '3': 3, '4': 1, '5': 13, '10': 'rxBad'},
    {'1': 'rx_auth_fail', '3': 4, '4': 1, '5': 13, '10': 'rxAuthFail'},
    {'1': 'delivered', '3': 5, '4': 1, '5': 13, '10': 'delivered'},
    {'1': 'forwarded', '3': 6, '4': 1, '5': 13, '10': 'forwarded'},
    {'1': 'stored', '3': 7, '4': 1, '5': 13, '10': 'stored'},
    {'1': 'air_ms', '3': 8, '4': 1, '5': 4, '10': 'airMs'},
    {'1': 'store_size', '3': 9, '4': 1, '5': 13, '10': 'storeSize'},
    {'1': 'neighbors', '3': 10, '4': 1, '5': 13, '10': 'neighbors'},
    {'1': 'sos_held', '3': 11, '4': 1, '5': 13, '10': 'sosHeld'},
    {'1': 'sos_active', '3': 12, '4': 1, '5': 8, '10': 'sosActive'},
    {'1': 'uptime_s', '3': 13, '4': 1, '5': 13, '10': 'uptimeS'},
    {'1': 'clients', '3': 14, '4': 1, '5': 13, '10': 'clients'},
    {'1': 'queued', '3': 15, '4': 1, '5': 13, '10': 'queued'},
  ],
};

/// Descriptor for `Status`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statusDescriptor = $convert.base64Decode(
    'CgZTdGF0dXMSDgoCdHgYASABKA1SAnR4Eg4KAnJ4GAIgASgNUgJyeBIVCgZyeF9iYWQYAyABKA'
    '1SBXJ4QmFkEiAKDHJ4X2F1dGhfZmFpbBgEIAEoDVIKcnhBdXRoRmFpbBIcCglkZWxpdmVyZWQY'
    'BSABKA1SCWRlbGl2ZXJlZBIcCglmb3J3YXJkZWQYBiABKA1SCWZvcndhcmRlZBIWCgZzdG9yZW'
    'QYByABKA1SBnN0b3JlZBIVCgZhaXJfbXMYCCABKARSBWFpck1zEh0KCnN0b3JlX3NpemUYCSAB'
    'KA1SCXN0b3JlU2l6ZRIcCgluZWlnaGJvcnMYCiABKA1SCW5laWdoYm9ycxIZCghzb3NfaGVsZB'
    'gLIAEoDVIHc29zSGVsZBIdCgpzb3NfYWN0aXZlGAwgASgIUglzb3NBY3RpdmUSGQoIdXB0aW1l'
    'X3MYDSABKA1SB3VwdGltZVMSGAoHY2xpZW50cxgOIAEoDVIHY2xpZW50cxIWCgZxdWV1ZWQYDy'
    'ABKA1SBnF1ZXVlZA==');

@$core.Deprecated('Use ownPositionDescriptor instead')
const OwnPosition$json = {
  '1': 'OwnPosition',
  '2': [
    {
      '1': 'pos',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Position',
      '10': 'pos'
    },
  ],
};

/// Descriptor for `OwnPosition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ownPositionDescriptor = $convert.base64Decode(
    'CgtPd25Qb3NpdGlvbhIvCgNwb3MYASABKAsyHS5naG9zdHdhdmUuY2xpZW50LnYxLlBvc2l0aW'
    '9uUgNwb3M=');

@$core.Deprecated('Use errorDescriptor instead')
const Error$json = {
  '1': 'Error',
  '2': [
    {
      '1': 'code',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.ghostwave.client.v1.Error.Code',
      '10': 'code'
    },
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
  '4': [Error_Code$json],
};

@$core.Deprecated('Use errorDescriptor instead')
const Error_Code$json = {
  '1': 'Code',
  '2': [
    {'1': 'NONE', '2': 0},
    {'1': 'BAD_FRAME', '2': 1},
    {'1': 'BAD_VERSION', '2': 2},
    {'1': 'UNKNOWN_REQUEST', '2': 3},
    {'1': 'NEED_HELLO', '2': 4},
    {'1': 'BAD_ARGUMENT', '2': 5},
    {'1': 'TOO_LONG', '2': 6},
    {'1': 'RATE_LIMITED', '2': 7},
    {'1': 'NOT_FOUND', '2': 8},
    {'1': 'KEY_REJECTED', '2': 9},
    {'1': 'SEND_FAILED', '2': 10},
    {'1': 'TOO_MANY_CLIENTS', '2': 11},
    {'1': 'NO_IDENTITY', '2': 12},
    {'1': 'CHANNEL_LIMIT', '2': 13},
  ],
};

/// Descriptor for `Error`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorDescriptor = $convert.base64Decode(
    'CgVFcnJvchIzCgRjb2RlGAEgASgOMh8uZ2hvc3R3YXZlLmNsaWVudC52MS5FcnJvci5Db2RlUg'
    'Rjb2RlEhYKBmRldGFpbBgCIAEoCVIGZGV0YWlsIvMBCgRDb2RlEggKBE5PTkUQABINCglCQURf'
    'RlJBTUUQARIPCgtCQURfVkVSU0lPThACEhMKD1VOS05PV05fUkVRVUVTVBADEg4KCk5FRURfSE'
    'VMTE8QBBIQCgxCQURfQVJHVU1FTlQQBRIMCghUT09fTE9ORxAGEhAKDFJBVEVfTElNSVRFRBAH'
    'Eg0KCU5PVF9GT1VORBAIEhAKDEtFWV9SRUpFQ1RFRBAJEg8KC1NFTkRfRkFJTEVEEAoSFAoQVE'
    '9PX01BTllfQ0xJRU5UUxALEg8KC05PX0lERU5USVRZEAwSEQoNQ0hBTk5FTF9MSU1JVBAN');

@$core.Deprecated('Use contactDescriptor instead')
const Contact$json = {
  '1': 'Contact',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 7, '10': 'nodeId'},
    {'1': 'name', '3': 2, '4': 1, '5': 12, '10': 'name'},
    {'1': 'x25519_pub', '3': 3, '4': 1, '5': 12, '10': 'x25519Pub'},
    {'1': 'ed25519_pub', '3': 4, '4': 1, '5': 12, '10': 'ed25519Pub'},
    {'1': 'pinned', '3': 5, '4': 1, '5': 8, '10': 'pinned'},
  ],
};

/// Descriptor for `Contact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactDescriptor = $convert.base64Decode(
    'CgdDb250YWN0EhcKB25vZGVfaWQYASABKAdSBm5vZGVJZBISCgRuYW1lGAIgASgMUgRuYW1lEh'
    '0KCngyNTUxOV9wdWIYAyABKAxSCXgyNTUxOVB1YhIfCgtlZDI1NTE5X3B1YhgEIAEoDFIKZWQy'
    'NTUxOVB1YhIWCgZwaW5uZWQYBSABKAhSBnBpbm5lZA==');

@$core.Deprecated('Use contactsEndDescriptor instead')
const ContactsEnd$json = {
  '1': 'ContactsEnd',
  '2': [
    {'1': 'count', '3': 1, '4': 1, '5': 13, '10': 'count'},
  ],
};

/// Descriptor for `ContactsEnd`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactsEndDescriptor =
    $convert.base64Decode('CgtDb250YWN0c0VuZBIUCgVjb3VudBgBIAEoDVIFY291bnQ=');

@$core.Deprecated('Use okDescriptor instead')
const Ok$json = {
  '1': 'Ok',
};

/// Descriptor for `Ok`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List okDescriptor = $convert.base64Decode('CgJPaw==');

@$core.Deprecated('Use peerIdentDescriptor instead')
const PeerIdent$json = {
  '1': 'PeerIdent',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 7, '10': 'nodeId'},
    {'1': 'name', '3': 2, '4': 1, '5': 12, '10': 'name'},
    {'1': 'is_new', '3': 3, '4': 1, '5': 8, '10': 'isNew'},
  ],
};

/// Descriptor for `PeerIdent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerIdentDescriptor = $convert.base64Decode(
    'CglQZWVySWRlbnQSFwoHbm9kZV9pZBgBIAEoB1IGbm9kZUlkEhIKBG5hbWUYAiABKAxSBG5hbW'
    'USFQoGaXNfbmV3GAMgASgIUgVpc05ldw==');

@$core.Deprecated('Use keyChangeDescriptor instead')
const KeyChange$json = {
  '1': 'KeyChange',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 7, '10': 'nodeId'},
    {'1': 'ed25519_pub', '3': 2, '4': 1, '5': 12, '10': 'ed25519Pub'},
    {'1': 'name', '3': 3, '4': 1, '5': 12, '10': 'name'},
  ],
};

/// Descriptor for `KeyChange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyChangeDescriptor = $convert.base64Decode(
    'CglLZXlDaGFuZ2USFwoHbm9kZV9pZBgBIAEoB1IGbm9kZUlkEh8KC2VkMjU1MTlfcHViGAIgAS'
    'gMUgplZDI1NTE5UHViEhIKBG5hbWUYAyABKAxSBG5hbWU=');

@$core.Deprecated('Use channelMessageDescriptor instead')
const ChannelMessage$json = {
  '1': 'ChannelMessage',
  '2': [
    {'1': 'channel', '3': 1, '4': 1, '5': 9, '10': 'channel'},
    {'1': 'src', '3': 2, '4': 1, '5': 7, '10': 'src'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 7, '10': 'msgId'},
    {'1': 'text', '3': 4, '4': 1, '5': 12, '10': 'text'},
    {
      '1': 'pos',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.ghostwave.client.v1.Position',
      '10': 'pos'
    },
  ],
};

/// Descriptor for `ChannelMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelMessageDescriptor = $convert.base64Decode(
    'Cg5DaGFubmVsTWVzc2FnZRIYCgdjaGFubmVsGAEgASgJUgdjaGFubmVsEhAKA3NyYxgCIAEoB1'
    'IDc3JjEhUKBm1zZ19pZBgDIAEoB1IFbXNnSWQSEgoEdGV4dBgEIAEoDFIEdGV4dBIvCgNwb3MY'
    'BSABKAsyHS5naG9zdHdhdmUuY2xpZW50LnYxLlBvc2l0aW9uUgNwb3M=');

@$core.Deprecated('Use channelDescriptor instead')
const Channel$json = {
  '1': 'Channel',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'psk', '3': 2, '4': 1, '5': 12, '10': 'psk'},
  ],
};

/// Descriptor for `Channel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelDescriptor = $convert.base64Decode(
    'CgdDaGFubmVsEhIKBG5hbWUYASABKAlSBG5hbWUSEAoDcHNrGAIgASgMUgNwc2s=');

@$core.Deprecated('Use channelsEndDescriptor instead')
const ChannelsEnd$json = {
  '1': 'ChannelsEnd',
  '2': [
    {'1': 'count', '3': 1, '4': 1, '5': 13, '10': 'count'},
  ],
};

/// Descriptor for `ChannelsEnd`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelsEndDescriptor =
    $convert.base64Decode('CgtDaGFubmVsc0VuZBIUCgVjb3VudBgBIAEoDVIFY291bnQ=');
