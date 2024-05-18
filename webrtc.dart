import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WebRTCManager {
  late RTCPeerConnection peerConnection;
  late IO.Socket socket;
  late MediaStream localStream;

  WebRTCManager(this.socket) {
    initialize();
  }

  Future<void> initialize() async {
    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'}
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true
      },
      'optional': []
    };

    peerConnection = await createPeerConnection(configuration, offerSdpConstraints);

    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': true
    });

    peerConnection.addStream(localStream);

    peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      socket.emit('webrtc_ice_candidate', {
        'candidate': candidate.toMap(),
        'roomId': /* Your room ID */
      });
    };

    peerConnection.onAddStream = (MediaStream stream) {
      // Handle remote stream
    };

    socket.on('webrtc_offer', (data) {
      _handleRemoteOffer(data['sdp'], data['sender']);
    });

    socket.on('webrtc_ice_candidate', (data) {
      _addIceCandidate(data['candidate']);
    });
  }

  void _handleRemoteOffer(String sdp, String sender) async {
    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final RTCSessionDescription description = await peerConnection.createAnswer({});
    await peerConnection.setLocalDescription(description);
    socket.emit('webrtc_answer', {
      'sdp': description.toMap(),
      'sender': sender
    });
  }

  void _addIceCandidate(Map<String, dynamic> candidateMap) async {
    if (candidateMap != null) {
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMlineIndex']
      );
      await peerConnection.addCandidate(candidate);
    }
  }

  void createOffer() async {
    RTCSessionDescription description = await peerConnection.createOffer({});
    await peerConnection.setLocalDescription(description);
    socket.emit('webrtc_offer', {
      'sdp': description.toMap(),
      'roomId': /* Your room ID */
    });
  }

  void dispose() {
    localStream.dispose();
    peerConnection.close();
  }
}
