import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fb/screens/fullScreenImage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'chat_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String friendId;
  final String friendName;
  final String photoUrl;
  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.friendId,
    required this.friendName,
    required this.photoUrl,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  TextEditingController _messageController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  bool _isUploading = false;
  late Stream<QuerySnapshot> _stream;
  late ChatService _chatService;

  @override
  void initState() {
    super.initState();
    _chatService = ChatService(
      chatId: widget.chatId,
      friendId: widget.friendId,
      currentUserId: currentUserId,
    );
    _stream = _chatService.getMessagesStream();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    String text = _messageController.text.trim();
    _messageController.clear();
    if (text.isEmpty) return;

    await _chatService.sendMessage(text);
  }

  void _sendImage() async {
    final image = await _chatService.pickImage();
    if (image == null) return;

    setState(() {
      _isUploading = true;
    });

    await _chatService.sendImage(image);

    setState(() {
      _isUploading = false;
    });
  }

  void _retryImageUpload(String messageId, String localPath) {
    _chatService.retryImageUpload(messageId, localPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff2196f3),
        leading: Padding(
          padding: const EdgeInsets.all(0.0),
          child: IconButton(
            icon: CircleAvatar(
              // If the URL exists, load it as the background
              backgroundImage: (widget.photoUrl.isNotEmpty)
                  ? NetworkImage(widget.photoUrl)
                  : null,
              // If the URL is empty, draw a default icon inside
              child: (widget.photoUrl.isEmpty)
                  ? Text(widget.friendName[0])
                  : null,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,

                    // FIX: Use the ternary operator (? :) instead of if/else
                    child: widget.photoUrl.isNotEmpty
                        ? Image.network(widget.photoUrl, fit: BoxFit.contain)
                        : const Padding(
                            padding: EdgeInsets.all(50.0),
                            child: Icon(
                              Icons.person,
                              size: 100,
                              color: Colors.grey,
                            ),
                          ),
                  );
                },
              );
            },
          ),
        ),
        title: Text(widget.friendName),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder(
                stream: _stream,
                builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                  // 1. Loading State
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // 2. Empty State
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("Say Hi! 👋"));
                  }

                  var filteredDocs = snapshot.data!.docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    var deletedFor = data['deletedFor'] ?? [];

                    return !deletedFor.contains(currentUserId);
                  }).toList();
                  return ListView.builder(
                    reverse: true, // IMPORTANT: Sticks list to bottom
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      var msgData =
                          filteredDocs[index].data() as Map<String, dynamic>;
                      bool isUploading = msgData['isUploading'] ?? false;
                      bool hasError = msgData['hasError'] ?? false;
                      String localPath = msgData['localPath'] ?? '';
                      String imageUrl = msgData['imageUrl'] ?? '';
                      bool isMe = msgData['senderId'] == currentUserId;
                      String messageType = msgData['type'] ?? 'text';
                      String timeString = "";
                      if (msgData['timestamp'] != null) {
                        Timestamp t = msgData['timestamp'] as Timestamp;
                        timeString = DateFormat(
                          'yyyy-MM-dd h:mm a',
                        ).format(t.toDate());
                      }
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () {
                            showModalBottomSheet(
                              context: context,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              builder: (bottomSheetContext) {
                                return SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(
                                          Icons.delete,
                                          color: Colors.grey,
                                        ),
                                        title: const Text('Delete for me'),
                                        onTap: () => _chatService.deleteForMe(
                                          bottomSheetContext,
                                          filteredDocs[index].id,
                                          2,
                                        ),
                                      ),
                                      if (isMe)
                                        ListTile(
                                          leading: const Icon(
                                            Icons.delete_forever,
                                            color: Colors.red,
                                          ),
                                          title: const Text(
                                            'Unsend',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                          onTap: () =>
                                              _chatService.deleteForEveryone(
                                                filteredDocs[index].id,
                                                bottomSheetContext,
                                              ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  // Images look better with smaller padding than text
                                  padding: messageType == 'image'
                                      ? const EdgeInsets.all(4)
                                      : const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Colors.blue
                                        : Colors.grey[300],
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(12),
                                      topRight: const Radius.circular(12),
                                      bottomLeft: isMe
                                          ? const Radius.circular(12)
                                          : Radius.zero,
                                      bottomRight: isMe
                                          ? Radius.zero
                                          : const Radius.circular(12),
                                    ),
                                  ),
                                  child: messageType == 'image'
                                      ? GestureDetector(
                                          onTap: () {
                                            if (imageUrl.isNotEmpty &&
                                                !isUploading) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      FullScreenImage(
                                                        imageUrl:
                                                            msgData['imageUrl'] ??
                                                            '',
                                                      ),
                                                ),
                                              );
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ), // Keeps the image inside your curved box
                                            child: isMe
                                                // --- 1. SENDER VIEW ---
                                                ? (isUploading || hasError)
                                                      ? Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            Image.file(
                                                              File(localPath),
                                                              width: 220,
                                                              height: 220,
                                                              fit: BoxFit.cover,
                                                              color: hasError
                                                                  ? Colors.black
                                                                        .withOpacity(
                                                                          0.4,
                                                                        )
                                                                  : null,
                                                              colorBlendMode:
                                                                  hasError
                                                                  ? BlendMode
                                                                        .darken
                                                                  : null,
                                                            ),
                                                            if (isUploading)
                                                              const CircularProgressIndicator(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            if (hasError)
                                                              IconButton(
                                                                icon: const Icon(
                                                                  Icons.refresh,
                                                                  color: Colors
                                                                      .red,
                                                                  size: 40,
                                                                ),
                                                                onPressed: () {
                                                                  // snapshot.data!.docs[index].id gives us the exact Firestore document ID
                                                                  _retryImageUpload(
                                                                    snapshot
                                                                        .data!
                                                                        .docs[index]
                                                                        .id,
                                                                    localPath,
                                                                  );
                                                                },
                                                              ),
                                                          ],
                                                        )
                                                      : Image.network(
                                                          imageUrl,
                                                          width: 220,
                                                          fit: BoxFit.cover,
                                                        )
                                                // --- 2. RECEIVER VIEW ---
                                                : (imageUrl.isEmpty ||
                                                      isUploading)
                                                ? Container(
                                                    width: 220,
                                                    height: 220,
                                                    color: Colors.grey[900],
                                                    child: const Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        CircularProgressIndicator(
                                                          color: Colors.white54,
                                                        ),
                                                        SizedBox(height: 12),
                                                        Text(
                                                          "Incoming photo...",
                                                          style: TextStyle(
                                                            color:
                                                                Colors.white54,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  )
                                                : Image.network(
                                                    imageUrl,
                                                    width: 220,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        )
                                      : Text(
                                          msgData['text'] ?? '',
                                          style: TextStyle(
                                            color: isMe
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                ),
                                // --- THE TIMESTAMP ---
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4.0,
                                    left: 4.0,
                                    right: 4.0,
                                  ),
                                  child: Text(
                                    timeString,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.photo_library,
                      color: Color(0xff2196f3),
                    ),
                    onPressed: _isUploading ? null : _sendImage,
                  ),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 5,
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xff2196f3),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () {
                        if (_messageController.text.isNotEmpty) {
                          _sendMessage();
                          _messageController.clear();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
