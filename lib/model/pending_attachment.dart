import 'dart:typed_data';

enum AttachmentUploadStatus { uploading, done, failed }

class PendingAttachment {
  final String id;
  final String name;
  final String mime;

  final Uint8List bytes;

  AttachmentUploadStatus status;

  String? ref;

  PendingAttachment({
    required this.name,
    required this.mime,
    required this.bytes,
    this.status = AttachmentUploadStatus.uploading,
    this.ref,
  }) : id =
           DateTime.now().microsecondsSinceEpoch.toString() +
           name.hashCode.toRadixString(16);

  bool get isImage => mime.startsWith('image/');
  bool get isUploading => status == AttachmentUploadStatus.uploading;
  bool get isDone => status == AttachmentUploadStatus.done && ref != null;
  bool get isFailed => status == AttachmentUploadStatus.failed;
}
