import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/call.dart';
import '../models/employee.dart';
import 'db.dart';

/// Peer-to-peer audio and video calling.
///
/// Firestore is used only to introduce the two phones to each other: the SDP
/// offer and answer, and the ICE candidates each side discovers. Once they are
/// connected the media flows directly between the handsets and never reaches
/// any server of ours.
///
/// That is what makes the calls end-to-end encrypted, and it is not a feature
/// this app implements or could turn off: WebRTC media is always DTLS-SRTP,
/// there is no unencrypted mode, and with no media server in the path there is
/// nowhere for a third party to listen. The keys are negotiated directly
/// between the two devices; the signalling documents carry no key material.
///
/// The honest limitation is reachability, not privacy. Two phones on mobile
/// networks sometimes cannot reach each other directly, and the usual fix is a
/// TURN relay -- which costs money and, unlike this, does put a third machine
/// in the media path. Only STUN is configured here, so a small proportion of
/// calls will fail to connect rather than quietly falling back to a relay.
class CallService {
  CallService._();

  static final CallService instance = CallService._();

  /// Google's public STUN servers. STUN only discovers each phone's public
  /// address; it never carries media, so using someone else's is harmless.
  static const _iceServers = <String, dynamic>{
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
  };

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  String? _orgId;
  String? _callId;
  bool _speakerOn = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidateSub;

  /// The far end's audio and video, once it arrives.
  final ValueNotifier<MediaStream?> remoteStream = ValueNotifier<MediaStream?>(
    null,
  );

  /// This phone's own camera, for the preview window.
  final ValueNotifier<MediaStream?> localStream = ValueNotifier<MediaStream?>(
    null,
  );

  final ValueNotifier<Call?> current = ValueNotifier<Call?>(null);

  /// Calls ringing for this person right now, so the app can show the
  /// incoming-call screen wherever they happen to be.
  Stream<List<Call>> incoming(String orgId, String uid) {
    return Db.calls(orgId).where('calleeUid', isEqualTo: uid).snapshots().map((
      snap,
    ) {
      final calls = snap.docs.map(Call.fromDoc).toList();
      return calls.where((call) => call.status == CallStatus.ringing).toList();
    });
  }

  Stream<Call?> watch(String orgId, String callId) {
    return Db.calls(orgId)
        .doc(callId)
        .snapshots()
        .map((doc) => doc.exists ? Call.fromDoc(doc) : null);
  }

  /// Places a call and returns its id.
  Future<String> place({
    required String orgId,
    required Employee me,
    required Employee other,
    required CallKind kind,
  }) async {
    await _teardown();

    _orgId = orgId;

    final callRef = Db.calls(orgId).doc();
    _callId = callRef.id;

    await _openPeer(video: kind == CallKind.video);

    // Candidates are written as they are discovered rather than gathered
    // first: trickle ICE lets the connection start forming while the rest are
    // still being found, which is the difference between a call connecting in
    // a second and in five.
    _peer!.onIceCandidate = (candidate) {
      callRef.collection('callerCandidates').add(candidate.toMap());
    };

    final offer = await _peer!.createOffer();
    await _peer!.setLocalDescription(offer);

    await callRef.set({
      'callerUid': me.uid,
      'callerName': me.name,
      'callerPhotoUrl': me.photoUrl,
      'calleeUid': other.uid,
      'calleeName': other.name,
      'kind': kind.name,
      'status': CallStatus.ringing.name,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'createdAt': FieldValue.serverTimestamp(),
    });

    _listen(callRef, remoteCandidates: 'calleeCandidates');
    return callRef.id;
  }

  /// Answers a ringing call.
  Future<void> answer({required String orgId, required Call call}) async {
    await _teardown();

    _orgId = orgId;
    _callId = call.id;

    final callRef = Db.calls(orgId).doc(call.id);
    await _openPeer(video: call.isVideo);

    _peer!.onIceCandidate = (candidate) {
      callRef.collection('calleeCandidates').add(candidate.toMap());
    };

    final offer = call.offer;
    if (offer == null) throw Exception('That call is no longer available.');

    await _peer!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );

    final answer = await _peer!.createAnswer();
    await _peer!.setLocalDescription(answer);

    await callRef.update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'status': CallStatus.active.name,
      'answeredAt': FieldValue.serverTimestamp(),
    });

    _listen(callRef, remoteCandidates: 'callerCandidates');
  }

  Future<void> decline({required String orgId, required Call call}) async {
    await Db.calls(orgId).doc(call.id).update({
      'status': CallStatus.declined.name,
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Hangs up. Writing the status is what tells the other phone to stop, so it
  /// happens even if tearing down the local side throws.
  Future<void> hangUp({String? orgId, String? callId}) async {
    // The call screen passes its immutable route identifiers. Falling back to
    // service state remains useful during a partially failed call setup, but
    // must not be the normal signalling path: asynchronous teardown can clear
    // that mutable state before the user taps End.
    final targetOrgId = orgId ?? _orgId;
    final targetCallId = callId ?? _callId;

    try {
      if (targetOrgId != null && targetCallId != null) {
        await Db.calls(targetOrgId)
            .doc(targetCallId)
            .update({
              'status': CallStatus.ended.name,
              'endedAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      // Local media must stop even when the network cannot acknowledge the
      // end marker. The other side will still time out a stranded ring.
      debugPrint('offixia: could not mark the call ended: $e');
    } finally {
      await _teardown();
    }
  }

  void toggleMute(bool muted) {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
  }

  void toggleCamera(bool on) {
    for (final track in _localStream?.getVideoTracks() ?? const []) {
      track.enabled = on;
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> setSpeaker(bool on) async {
    // Keep the user's selection as call state. Some Android audio managers
    // choose a route again when the remote track becomes live, so merely
    // applying this once when the button is tapped is not reliable.
    _speakerOn = on;
    await Helper.setSpeakerphoneOn(on);
  }

  Future<void> _openPeer({required bool video}) async {
    _peer = await createPeerConnection(_iceServers);

    // Android's communication mode enables the handset's hardware acoustic
    // echo canceller when available. Without it, speaker output can be fed
    // straight back into the microphone, especially when two phones are in
    // the same room.
    await Helper.setAndroidAudioConfiguration(
      AndroidAudioConfiguration.communication,
    );

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        // Older Android WebRTC builds recognize the goog-prefixed forms.
        'googEchoCancellation': true,
        'googEchoCancellation2': true,
        'googNoiseSuppression': true,
        'googAutoGainControl': true,
      },
      'video': video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    // Establish a sensible initial selection. CallScreen can change it while
    // ringing, and the selected route is reapplied when remote audio arrives.
    _speakerOn = video;
    await Helper.setSpeakerphoneOn(_speakerOn);
    localStream.value = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _peer!.addTrack(track, _localStream!);
    }

    _peer!.onTrack = (event) {
      if (event.streams.isNotEmpty) remoteStream.value = event.streams.first;
      // Android may switch to loudspeaker as it attaches the remote audio
      // track. Restore exactly what the user selected on the call screen.
      unawaited(Helper.setSpeakerphoneOn(_speakerOn));
    };

    _peer!.onConnectionState = (state) {
      debugPrint('offixia/call: connection $state');
      // A dropped connection is not a hang-up: the far end may reconnect, and
      // only an explicit status write ends the call for both sides.
    };
  }

  void _listen(
    DocumentReference<Map<String, dynamic>> callRef, {
    required String remoteCandidates,
  }) {
    _callSub = callRef.snapshots().listen((doc) async {
      if (!doc.exists) {
        await _teardown();
        return;
      }

      final call = Call.fromDoc(doc);
      current.value = call;

      // The caller learns it was answered by seeing the answer appear.
      final answer = call.answer;
      if (answer != null &&
          _peer != null &&
          (await _peer!.getRemoteDescription()) == null) {
        await _peer!.setRemoteDescription(
          RTCSessionDescription(
            answer['sdp'] as String?,
            answer['type'] as String?,
          ),
        );
      }

      if (call.status.isOver) await _teardown();
    });

    _candidateSub = callRef.collection(remoteCandidates).snapshots().listen((
      snap,
    ) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        _peer?.addCandidate(
          RTCIceCandidate(
            data['candidate'] as String?,
            data['sdpMid'] as String?,
            (data['sdpMLineIndex'] as num?)?.toInt(),
          ),
        );
      }
    });
  }

  Future<void> _teardown() async {
    await _callSub?.cancel();
    await _candidateSub?.cancel();
    _callSub = null;
    _candidateSub = null;

    for (final track in _localStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;

    await _peer?.close();
    _peer = null;

    // Release Android's call-specific audio focus and routing after the call.
    await Helper.clearAndroidCommunicationDevice();

    localStream.value = null;
    remoteStream.value = null;
    current.value = null;
    _orgId = null;
    _callId = null;
  }
}
