import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/call.dart';
import '../models/chat.dart';
import '../models/employee.dart';
import '../models/group_call.dart';
import 'db.dart';

/// A four-person WebRTC mesh.
///
/// Every pair of joined phones owns one peer connection. Firestore carries
/// only SDP and ICE signalling; media remains DTLS-SRTP encrypted directly
/// between phones.
class GroupCallService {
  GroupCallService._();

  static final GroupCallService instance = GroupCallService._();

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

  String? _myUid;
  String? _callerUid;
  MediaStream? _local;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  final Map<String, _MeshPeer> _peers = {};
  final Set<String> _connecting = {};
  bool _speakerOn = false;

  final ValueNotifier<MediaStream?> localStream = ValueNotifier(null);
  final ValueNotifier<Map<String, MediaStream>> remoteStreams = ValueNotifier(
    const {},
  );

  Stream<GroupCall?> watch(String orgId, String callId) => Db.groupCalls(orgId)
      .doc(callId)
      .snapshots()
      .map((doc) => doc.exists ? GroupCall.fromDoc(doc) : null);

  Stream<List<GroupCall>> incoming(String orgId, String uid) =>
      Db.groupCalls(
        orgId,
      ).where('invitedUids', arrayContains: uid).snapshots().map((snapshot) {
        final calls = snapshot.docs
            .map(GroupCall.fromDoc)
            .where(
              (call) =>
                  call.isRingingFor(uid) &&
                  call.age <= const Duration(minutes: 2),
            )
            .toList();
        calls.sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
        return calls;
      });

  Future<String> start({
    required String orgId,
    required ChatGroup chat,
    required Employee me,
    required CallKind kind,
    List<String>? invitedUids,
  }) async {
    final others = <String>{...?invitedUids};
    if (others.isEmpty) others.addAll(chat.memberUids);
    others.remove(me.uid);
    final participants = [me.uid, ...others];
    if (participants.any((uid) => !chat.memberUids.contains(uid))) {
      throw Exception('Only group members can join this call.');
    }
    if (participants.length < 2) {
      throw Exception('A group call needs two people.');
    }
    if (participants.length > GroupCall.maxParticipants) {
      throw Exception('Secure group calls currently support up to 4 people.');
    }

    await _teardown();
    final ref = Db.groupCalls(orgId).doc();
    _myUid = me.uid;
    _callerUid = me.uid;
    await _openMedia(video: kind == CallKind.video);

    try {
      await ref
          .set({
            'chatId': chat.id,
            'groupName': chat.name,
            'callerUid': me.uid,
            'callerName': me.name,
            'kind': kind.name,
            'invitedUids': participants,
            'joinedUids': [me.uid],
            'declinedUids': <String>[],
            'leftUids': <String>[],
            'status': 'ringing',
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await _teardown();
      throw Exception('Could not start the call. Check your connection.');
    } catch (_) {
      await _teardown();
      rethrow;
    }
    _listen(ref);
    return ref.id;
  }

  Future<void> answer({
    required String orgId,
    required GroupCall call,
    required Employee me,
  }) async {
    await _teardown();
    _myUid = me.uid;
    _callerUid = call.callerUid;
    await _openMedia(video: call.isVideo);

    final ref = Db.groupCalls(orgId).doc(call.id);
    try {
      await ref
          .update({
            'joinedUids': FieldValue.arrayUnion([me.uid]),
            'status': 'active',
          })
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await _teardown();
      throw Exception('Could not join the call. Check your connection.');
    } catch (_) {
      await _teardown();
      rethrow;
    }
    _listen(ref);
  }

  Future<void> decline({
    required String orgId,
    required GroupCall call,
    required String uid,
  }) => Db.groupCalls(orgId).doc(call.id).update({
    'declinedUids': FieldValue.arrayUnion([uid]),
  });

  Future<void> leave({
    required String orgId,
    required String callId,
    required String uid,
  }) async {
    try {
      final ref = Db.groupCalls(orgId).doc(callId);
      if (uid == _callerUid) {
        await ref
            .update({
              'status': 'ended',
              'endedAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 3));
      } else {
        await ref
            .update({
              'joinedUids': FieldValue.arrayRemove([uid]),
              'leftUids': FieldValue.arrayUnion([uid]),
            })
            .timeout(const Duration(seconds: 3));
      }
    } catch (error) {
      debugPrint('offixia/group-call: could not leave: $error');
    } finally {
      await _teardown();
    }
  }

  void toggleMute(bool muted) {
    for (final track in _local?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
  }

  void toggleCamera(bool on) {
    for (final track in _local?.getVideoTracks() ?? const []) {
      track.enabled = on;
    }
  }

  Future<void> setSpeaker(bool on) async {
    _speakerOn = on;
    await Helper.setSpeakerphoneOn(on);
  }

  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? const [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> _openMedia({required bool video}) async {
    await Helper.setAndroidAudioConfiguration(
      AndroidAudioConfiguration.communication,
    );
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'googEchoCancellation': true,
        'googNoiseSuppression': true,
      },
      'video': video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    _speakerOn = video;
    await Helper.setSpeakerphoneOn(_speakerOn);
    localStream.value = _local;
  }

  void _listen(DocumentReference<Map<String, dynamic>> ref) {
    _callSub = ref.snapshots().listen(
      (doc) {
        if (!doc.exists) {
          unawaited(_teardown());
          return;
        }
        final call = GroupCall.fromDoc(doc);
        if (call.isEnded) {
          unawaited(_teardown());
          return;
        }
        final me = _myUid;
        if (me == null) return;

        for (final uid in call.joinedUids) {
          if (uid != me) unawaited(_ensurePeer(ref, uid));
        }
        final departed = _peers.keys
            .where((uid) => !call.joinedUids.contains(uid))
            .toList();
        for (final uid in departed) {
          unawaited(_disposePeer(uid));
        }
      },
      onError: (Object error) {
        debugPrint('offixia/group-call: call watch failed: $error');
      },
    );
  }

  Future<void> _ensurePeer(
    DocumentReference<Map<String, dynamic>> callRef,
    String otherUid,
  ) async {
    if (_peers.containsKey(otherUid) || !_connecting.add(otherUid)) return;
    final me = _myUid;
    final local = _local;
    if (me == null || local == null) {
      _connecting.remove(otherUid);
      return;
    }

    try {
      final ids = [me, otherUid]..sort();
      final offererUid = ids.first;
      final answererUid = ids.last;
      final amOfferer = me == offererUid;
      final peerRef = callRef
          .collection('peers')
          .doc('${ids.first}_${ids.last}');
      final pc = await createPeerConnection(_iceServers);
      final state = _MeshPeer(pc);
      _peers[otherUid] = state;

      for (final track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
      pc.onTrack = (event) {
        if (event.streams.isEmpty) return;
        remoteStreams.value = {
          ...remoteStreams.value,
          otherUid: event.streams.first,
        };
        unawaited(Helper.setSpeakerphoneOn(_speakerOn));
      };
      pc.onIceCandidate = (candidate) {
        final path = amOfferer ? 'offerCandidates' : 'answerCandidates';
        peerRef.collection(path).add(candidate.toMap()).catchError((Object e) {
          debugPrint('offixia/group-call: candidate write failed: $e');
          return peerRef.collection(path).doc();
        });
      };

      final remotePath = amOfferer ? 'answerCandidates' : 'offerCandidates';
      state.candidateSub = peerRef.collection(remotePath).snapshots().listen((
        s,
      ) {
        for (final change in s.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final data = change.doc.data();
          if (data == null) continue;
          unawaited(
            pc.addCandidate(
              RTCIceCandidate(
                data['candidate'] as String?,
                data['sdpMid'] as String?,
                (data['sdpMLineIndex'] as num?)?.toInt(),
              ),
            ),
          );
        }
      });

      state.peerSub = peerRef.snapshots().listen((doc) async {
        final data = doc.data();
        if (data == null) return;
        if (amOfferer) {
          final answer = data['answer'] as Map<String, dynamic>?;
          if (answer != null && !state.remoteDescriptionSet) {
            state.remoteDescriptionSet = true;
            await pc.setRemoteDescription(
              RTCSessionDescription(
                answer['sdp'] as String?,
                answer['type'] as String?,
              ),
            );
          }
        } else {
          final offer = data['offer'] as Map<String, dynamic>?;
          if (offer != null && !state.answered) {
            state.answered = true;
            await pc.setRemoteDescription(
              RTCSessionDescription(
                offer['sdp'] as String?,
                offer['type'] as String?,
              ),
            );
            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            await peerRef.update({
              'answer': {'sdp': answer.sdp, 'type': answer.type},
            });
          }
        }
      });

      if (amOfferer) {
        await peerRef.set({
          'offererUid': offererUid,
          'answererUid': answererUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await peerRef.update({
          'offer': {'sdp': offer.sdp, 'type': offer.type},
        });
      }
    } catch (error) {
      debugPrint('offixia/group-call: peer setup failed: $error');
      await _disposePeer(otherUid);
    } finally {
      _connecting.remove(otherUid);
    }
  }

  Future<void> _disposePeer(String uid) async {
    final state = _peers.remove(uid);
    if (state == null) return;
    await state.peerSub?.cancel();
    await state.candidateSub?.cancel();
    await state.connection.close();
    final streams = {...remoteStreams.value}..remove(uid);
    remoteStreams.value = streams;
  }

  Future<void> _teardown() async {
    await _callSub?.cancel();
    _callSub = null;
    for (final uid in _peers.keys.toList()) {
      await _disposePeer(uid);
    }
    for (final track in _local?.getTracks() ?? const []) {
      await track.stop();
    }
    await _local?.dispose();
    _local = null;
    localStream.value = null;
    remoteStreams.value = const {};
    await Helper.clearAndroidCommunicationDevice();
    _connecting.clear();
    _myUid = null;
    _callerUid = null;
  }
}

class _MeshPeer {
  _MeshPeer(this.connection);

  final RTCPeerConnection connection;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? peerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? candidateSub;
  bool answered = false;
  bool remoteDescriptionSet = false;
}
