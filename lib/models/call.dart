import 'package:cloud_firestore/cloud_firestore.dart';

enum CallKind {
  audio('Audio call'),
  video('Video call');

  const CallKind(this.label);
  final String label;

  static CallKind fromName(String? name) => CallKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => CallKind.audio,
  );
}

/// Where a call has got to.
///
/// The whole lifecycle is one document field, which is what lets both handsets
/// agree without either of them being in charge: each watches the document and
/// reacts to what the other wrote.
enum CallStatus {
  /// Offer written, waiting for the callee to pick up.
  ringing,

  /// Answered. Media should be flowing.
  active,

  /// Callee refused.
  declined,

  /// Either side hung up, or it was never answered.
  ended;

  static CallStatus fromName(String? name) => CallStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => CallStatus.ended,
  );

  bool get isOver => this == CallStatus.declined || this == CallStatus.ended;
}

/// One call between two people.
///
/// Media never touches the server. The document carries only the WebRTC
/// handshake -- the SDP offer and answer, and the ICE candidates each side
/// discovers -- and once the peers are connected the audio and video flow
/// directly between the two phones, encrypted by DTLS-SRTP. That encryption is
/// not something this app adds or could switch off: WebRTC has no unencrypted
/// mode, and with no media server in the path there is nowhere for a third
/// party, including us, to listen.
class Call {
  const Call({
    required this.id,
    required this.callerUid,
    required this.callerName,
    required this.calleeUid,
    required this.calleeName,
    required this.kind,
    required this.status,
    this.callerPhotoUrl = '',
    this.offer,
    this.answer,
    this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.isGroup = false,
    this.chatId,
    this.groupName = '',
  });

  final String id;
  final String callerUid;
  final String callerName;
  final String callerPhotoUrl;
  final String calleeUid;
  final String calleeName;
  final CallKind kind;
  final CallStatus status;

  /// Session descriptions, stored as `{sdp, type}`.
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;

  final DateTime? createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// A mesh call with more than two people.
  ///
  /// Every phone holds a direct connection to every other, which is what keeps
  /// the media end-to-end encrypted -- there is no server in the path to
  /// decrypt it. The cost is that each phone uploads its own stream once per
  /// participant, so this is deliberately capped at [maxParticipants]. Going
  /// beyond that needs a relaying media server. An SFU can still preserve E2E
  /// encryption with insertable streams/SFrame, but it adds server cost and a
  /// substantially more involved key-management layer.
  final bool isGroup;

  /// The group conversation this call belongs to, when it is a group call.
  final String? chatId;
  final String groupName;

  /// Four is where a mesh stops being kind to a phone: at five, each handset
  /// is encoding and uploading four copies of its own camera.
  static const maxParticipants = 4;

  bool get isVideo => kind == CallKind.video;

  String otherUid(String me) => me == callerUid ? calleeUid : callerUid;
  String otherName(String me) => me == callerUid ? calleeName : callerName;

  /// How long a ringing call has been waiting, used to give up on one whose
  /// caller vanished without writing an end.
  Duration get ringingFor {
    final started = createdAt;
    if (started == null) return Duration.zero;
    return DateTime.now().difference(started);
  }

  factory Call.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Call(
      id: doc.id,
      callerUid: data['callerUid'] as String? ?? '',
      callerName: data['callerName'] as String? ?? '',
      callerPhotoUrl: data['callerPhotoUrl'] as String? ?? '',
      calleeUid: data['calleeUid'] as String? ?? '',
      calleeName: data['calleeName'] as String? ?? '',
      kind: CallKind.fromName(data['kind'] as String?),
      status: CallStatus.fromName(data['status'] as String?),
      offer: (data['offer'] as Map?)?.cast<String, dynamic>(),
      answer: (data['answer'] as Map?)?.cast<String, dynamic>(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      answeredAt: (data['answeredAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      isGroup: data['isGroup'] as bool? ?? false,
      chatId: data['chatId'] as String?,
      groupName: data['groupName'] as String? ?? '',
    );
  }
}
