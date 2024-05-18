import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class CustomRTCVideoRenderer extends RTCVideoRenderer {
  @override
  Function? onFirstFrameRendered;

  CustomRTCVideoRenderer() : super();

  @override
  Future<void> initialize() async {
    await super.initialize();
  }

  @override
  Future<void> dispose() async {
    onFirstFrameRendered = null;
    await super.dispose();
  }

  void firstFrameRenderedCallback() {
    if (onFirstFrameRendered != null) {
      onFirstFrameRendered!();
    }
  }
}

class WebRTCManager {
  RTCPeerConnection? peerConnection;
  CustomRTCVideoRenderer localRenderer = CustomRTCVideoRenderer();
  CustomRTCVideoRenderer remoteRenderer = CustomRTCVideoRenderer();
  IO.Socket socket;
  MediaStream? localStream;

  WebRTCManager(this.socket) {
    initializeRenderers();
  }

  Future<void> initializeRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> initializePeerConnection() async {
    final Map<String, dynamic> configuration = {
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
    };
    peerConnection = await createPeerConnection(configuration);

    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });

    localRenderer.srcObject = localStream;
    peerConnection!.addStream(localStream!);

    peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate != null) {
        socket.emit('webrtc_ice_candidate', {'candidate': candidate.toMap()});
      }
    };

    peerConnection!.onAddStream = (MediaStream stream) {
      remoteRenderer.srcObject = stream;
    };
  }

  Future<void> handleOffer(RTCSessionDescription offer) async {
    await initializePeerConnection();
    await peerConnection!.setRemoteDescription(offer);
    RTCSessionDescription answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);
    socket.emit('webrtc_answer', {'sdp': answer.toMap()});
  }

  Future<void> handleAnswer(RTCSessionDescription answer) async {
    await peerConnection!.setRemoteDescription(answer);
  }

  Future<void> handleIceCandidate(RTCIceCandidate candidate) async {
    await peerConnection!.addCandidate(candidate);
  }

  void dispose() async {
    await peerConnection?.close();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
    await localStream?.dispose();
    peerConnection = null;
  }
}
