/// Sharing through the platform's share sheet, behind an interface so tests
/// and platforms without a sheet can stand in.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands text or an image to another app. Nothing is sent by GhostWave itself:
/// the user picks where it goes.
abstract interface class ShareGateway {
  /// Offers [text] to the share sheet. [origin] anchors the sheet on tablets
  /// and desktops.
  Future<void> shareText(String text, {String? subject, Rect? origin});

  /// Offers a PNG image ([png], saved as [fileName]) with [text] as caption.
  Future<void> shareImage(Uint8List png, String fileName, {String? text, String? subject, Rect? origin});

  /// Offers a file ([data], saved as [fileName], of [mimeType]).
  Future<void> shareFile(Uint8List data, String fileName, String mimeType, {String? subject, Rect? origin});
}

/// The platform share sheet (share_plus).
class PlatformShare implements ShareGateway {
  /// Creates the gateway.
  const PlatformShare();

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject, sharePositionOrigin: origin));
  }

  @override
  Future<void> shareImage(Uint8List png, String fileName, {String? text, String? subject, Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
        fileNameOverrides: [fileName],
        text: text,
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<void> shareFile(Uint8List data, String fileName, String mimeType, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(data, mimeType: mimeType, name: fileName)],
        fileNameOverrides: [fileName],
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
  }
}

/// The share sheet in use; tests override it.
final shareGatewayProvider = Provider<ShareGateway>((ref) => const PlatformShare());
