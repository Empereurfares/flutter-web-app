import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:fe/webrtc.dart'; // Ensure this path matches the actual location of your WebRTCManager class

class Chat extends StatefulWidget {
  final String roomName;
  final String username;

  Chat({required this.roomName, required this.username});

  @override
  _ChatState createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final TextEditingController _controller = TextEditingController();
  late IO.Socket socket;
  List<Map<String, dynamic>> messages = [];
  List<String> users = [];
  String? selectedUser = 'Todos'; // Initialize directly
  bool isPublic = false;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  WebRTCManager? webrtcManager;
  bool inCall = false;
  bool calling = false;
  String? callingUser;
  String? receivingUser;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  int publicImageCount = 0;

  @override
  void initState() {
    super.initState();
    socket = IO.io(
        'https://papolivre.onrender.com', // Replace with your Render.com URL
        <String, dynamic>{
          'transports': ['websocket'],
        });

    socket.on('connect', (_) {
      print('connected to server');
      socket.emit(
          'join', {'roomName': widget.roomName, 'username': widget.username});
    });

    socket.on('roomUsers', (data) {
      setState(() {
        users = List<String>.from(data);
      });
    });

    socket.on('webrtc_offer', (data) async {
      RTCSessionDescription offer =
          RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']);
      setState(() {
        receivingUser = data['sender'];
      });
      bool accepted = await _showCallInvitationDialog(receivingUser!);
      if (accepted) {
        await handleOffer(offer);
        await sendAnswer();
      } else {
        socket.emit('call_rejected', {'target': receivingUser});
        setState(() {
          receivingUser = null;
        });
      }
    });

    socket.on('webrtc_answer', (data) async {
      RTCSessionDescription answer =
          RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']);
      await handleAnswer(answer);
      setState(() {
        inCall = true;
        calling = false;
      });
    });

    socket.on('webrtc_ice_candidate', (data) async {
      RTCIceCandidate candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex']);
      await handleIceCandidate(candidate);
    });

    socket.on('call_rejected', (_) {
      setState(() {
        calling = false;
        callingUser = null;
      });
    });

    initRenderers();
  }

  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    webrtcManager = WebRTCManager(socket);
  }

  Future<void> startCall() async {
    try {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user'},
      });
      localRenderer.srcObject = localStream;

      if (webrtcManager != null) {
        await webrtcManager!.initializePeerConnection();
        webrtcManager!.peerConnection!.onTrack = (event) {
          if (event.track.kind == 'video') {
            remoteRenderer.srcObject = event.streams[0];
          }
        };

        localStream!.getTracks().forEach((track) {
          webrtcManager!.peerConnection!.addTrack(track, localStream!);
        });

        RTCSessionDescription description =
            await webrtcManager!.peerConnection!.createOffer();
        await webrtcManager!.peerConnection!.setLocalDescription(description);
        socket.emit('webrtc_offer', {
          'sdp': description.toMap(),
          'target': selectedUser,
          'sender': widget.username,
        });
        setState(() {
          calling = true;
          callingUser = selectedUser;
        });
      }
    } catch (e) {
      print("Error in startCall: $e");
    }
  }

  Future<void> handleOffer(RTCSessionDescription offer) async {
    await webrtcManager!.initializePeerConnection();
    webrtcManager!.peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    await webrtcManager!.peerConnection!.setRemoteDescription(offer);

    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });
    localRenderer.srcObject = localStream;

    localStream!.getTracks().forEach((track) {
      webrtcManager!.peerConnection!.addTrack(track, localStream!);
    });

    setState(() {
      inCall = true;
    });
  }

  Future<void> sendAnswer() async {
    RTCSessionDescription answer =
        await webrtcManager!.peerConnection!.createAnswer();
    await webrtcManager!.peerConnection!.setLocalDescription(answer);
    socket.emit(
        'webrtc_answer', {'sdp': answer.toMap(), 'target': receivingUser});
  }

  Future<void> handleAnswer(RTCSessionDescription answer) async {
    await webrtcManager!.peerConnection!.setRemoteDescription(answer);
    setState(() {
      inCall = true;
    });
  }

  Future<void> handleIceCandidate(RTCIceCandidate candidate) async {
    await webrtcManager!.peerConnection!.addCandidate(candidate);
  }

  Future<bool> _showCallInvitationDialog(String fromUser) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Incoming Call'),
              content: Text('$fromUser is calling you.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Decline'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Accept'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void endCall() async {
    if (webrtcManager?.peerConnection != null) {
      await webrtcManager!.peerConnection!.close();
      await localStream?.dispose();
      await remoteRenderer.srcObject?.dispose();
      webrtcManager!.peerConnection = null;
      localStream = null;
    }
    setState(() {
      inCall = false;
      calling = false;
      callingUser = null;
      receivingUser = null;
    });
  }

  void sendMessage() {
    if (_controller.text.isNotEmpty) {
      socket.emit('message', {
        'room': widget.roomName,
        'text': _controller.text,
        'sender': widget.username,
        'target': selectedUser ?? 'for all',
        'isPublic': isPublic,
      });
      _controller.clear();
    }
  }

  void sendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      socket.emit('message', {
        'room': widget.roomName,
        'text': base64Image,
        'sender': widget.username,
        'target': selectedUser ?? 'for all',
        'isPublic': isPublic,
        'type': 'image',
      });
      if (isPublic || selectedUser == 'Todos') {
        setState(() {
          publicImageCount++;
        });
      }
    }
  }

  void inviteUserToCall(String targetUsername) {
    if (targetUsername.isNotEmpty && targetUsername != 'Todos') {
      socket.emit('invite-to-call', {
        'from': widget.username,
        'to': targetUsername,
      });
      startCall();
    }
  }

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    localStream?.dispose();
    webrtcManager?.dispose();
    socket.disconnect();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Papo Livre - Room: ${widget.roomName}, Username: ${widget.username}'),
      ),
      drawer: Drawer(
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              child: Text('Users in Room'),
              decoration: BoxDecoration(color: Colors.blue),
            ),
            ListTile(
              leading: Icon(Icons.exit_to_app),
              title: Text('Sign Out'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.room),
              title: Text('Room: ${widget.roomName}'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.account_circle),
              title: Text('Username: ${widget.username}'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            Divider(),
            SwitchListTile(
              title: Text('Send Public Message'),
              value: isPublic,
              onChanged: (bool value) {
                setState(() {
                  isPublic = value;
                  if (!isPublic) {
                    publicImageCount = 0;
                  }
                });
              },
            ),
            ListTile(
              title: Text('Todos'),
              onTap: () {
                setState(() {
                  selectedUser = 'Todos';
                  if (!isPublic) {
                    publicImageCount = 0;
                  }
                });
                Navigator.of(context).pop();
              },
            ),
            for (var user in users)
              if (user != 'Todos')
                ListTile(
                  title: Text(user),
                  onTap: () {
                    setState(() {
                      selectedUser = user;
                      publicImageCount = 0;
                    });
                    Navigator.of(context).pop();
                  },
                ),
          ],
        ),
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: inCall ? RTCVideoView(remoteRenderer) : Container(),
          ),
          if (calling)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Calling $callingUser...',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (receivingUser != null)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '$receivingUser is calling you...',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    height: 200,
                    child: ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        if (messages[index] != null) {
                          final message = messages[index];
                          if (message['isImage'] != null &&
                              message['isImage'] == true) {
                            if (message['image'] != null) {
                              final image = base64Decode(message['image']);
                              return ListTile(
                                leading: CircleAvatar(
                                    child: Text(message['sender'] != null
                                        ? message['sender'][0].toUpperCase()
                                        : '?')),
                                title: Text(message['sender'] ?? 'Unknown'),
                                subtitle:
                                    Image.memory(image, fit: BoxFit.cover),
                              );
                            } else {
                              return ListTile(
                                leading: CircleAvatar(child: Text('?')),
                                title: Text('Unknown'),
                                subtitle: Text('No image provided.'),
                              );
                            }
                          } else if (message['text'] != null) {
                            return ListTile(
                              leading: CircleAvatar(
                                  child: Text(message['sender'] != null
                                      ? message['sender'][0].toUpperCase()
                                      : '?')),
                              title: Text(message['sender'] ?? 'Unknown'),
                              subtitle: Text(message['text']),
                            );
                          } else {
                            return ListTile(
                              leading: CircleAvatar(child: Text('?')),
                              title: Text('Unknown'),
                              subtitle: Text('No message provided.'),
                            );
                          }
                        } else {
                          return Container();
                        }
                      },
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _controller,
                          decoration:
                              InputDecoration(labelText: 'Send a message'),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send),
                        onPressed: sendMessage,
                      ),
                      IconButton(
                        icon: Icon(Icons.image),
                        onPressed: sendImage,
                      ),
                      if (!inCall && !calling)
                        ElevatedButton(
                          onPressed: () {
                            if (selectedUser != null &&
                                selectedUser != 'Todos') {
                              inviteUserToCall(selectedUser!);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Please select a user to call.'),
                                ),
                              );
                            }
                          },
                          child: Text('Start Video Call'),
                        ),
                      if (inCall || calling)
                        ElevatedButton(
                          onPressed: endCall,
                          child: Text('End Video Call'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (inCall)
            Positioned(
              right: 20,
              top: 20,
              child: Draggable(
                feedback: Container(
                  width: 100,
                  height: 150,
                  child: RTCVideoView(localRenderer, mirror: true),
                ),
                child: Container(
                  width: 100,
                  height: 150,
                  child: RTCVideoView(localRenderer, mirror: true),
                ),
                childWhenDragging: Container(),
              ),
            ),
        ],
      ),
    );
  }
}
