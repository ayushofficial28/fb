import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fb/screens/fullScreenImage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String friendId;
  final String friendName;
  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.friendId,
    required this.friendName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  TextEditingController _messageController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  bool _isUploading = false;
  late Stream<QuerySnapshot> _stream;
  final ImagePicker _picker = ImagePicker();
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true) // Newest at bottom
        .snapshots();
  }

  void sendMessage() async {
    String text = _messageController.text.trim();
    _messageController.clear();
    if (text.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
          'text': text,
          'senderId': currentUserId,
          'timestamp': FieldValue.serverTimestamp(),
        });

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set(
      {
        'participants': [currentUserId, widget.friendId],
        'lastMessage': text,
        'lastTimestamp': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> sendImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;

    // 1. INSTANT PLACEHOLDER: Create the document reference first
    DocumentReference docRef = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
          'senderId': currentUserId,
          'text': '',
          'imageUrl': '', // Empty for now
          'localPath': image.path, // Save the physical phone path
          'type': 'image',
          'timestamp': FieldValue.serverTimestamp(),
          'isUploading': true, // <-- NEW: UI knows to show a spinner
          'hasError': false, // <-- NEW: UI knows it hasn't failed yet
        });
        await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set(
      {
        'participants': [currentUserId, widget.friendId],
        'lastMessage': '📷 Photo',
        'lastTimestamp': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    // 2. BACKGROUND UPLOAD: Now we talk to Cloudinary
    try {
      String cloudName = 'dpalozx6i';
      Uri uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      var request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = 'alter_chats';
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        // SUCCESS!
        var responseData = await response.stream.toBytes();
        var jsonMap = jsonDecode(String.fromCharCodes(responseData));
        String imageUrl = jsonMap['secure_url'];

        // 3. SILENT SWAP: Update the exact same document
        await docRef.update({
          'imageUrl': imageUrl,
          'isUploading': false, // Turn off the spinner
          // We can leave localPath there, it won't hurt anything
        });

        // Update the recent message preview for the chat list
        
      } else {
        // HTTP FAILED (Bad status code)
        print('--- HTTP UPLOAD FAILED ---');
        await docRef.update({
          'isUploading': false, // Stop spinner
          'hasError': true, // Trigger the red retry icon
        });
      }
    } catch (e) {
      // APP CRASHED OR NO INTERNET
      print("--- NETWORK ERROR DURING UPLOAD ---");
      await docRef.update({'isUploading': false, 'hasError': true});
    }
  }

  Future<void> retryImageUpload(String messageId, String localPath) async {
    DocumentReference docRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(messageId);

    // Reset the UI back to loading state instantly
    await docRef.update({'isUploading': true, 'hasError': false});

    // Run the exact same HTTP upload logic as above...
    try {
      String cloudName = 'dpalozx6i';
      Uri uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      var request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = 'alter_chats';
      request.files.add(await http.MultipartFile.fromPath('file', localPath));

      var response = await request.send();

      if (response.statusCode == 200) {
        var responseData = await response.stream.toBytes();
        var jsonMap = jsonDecode(String.fromCharCodes(responseData));

        await docRef.update({
          'imageUrl': jsonMap['secure_url'],
          'isUploading': false,
        });
      } else {
        await docRef.update({'isUploading': false, 'hasError': true});
      }
    } catch (e) {
      await docRef.update({'isUploading': false, 'hasError': true});
    }
  }

  // Injects Cloudinary parameters to grab a tiny, low-bandwidth thumbnail
  String getThumbnailUrl(String originalUrl) {
    if (!originalUrl.contains('/upload/')) return originalUrl;
    // w_250: width 250px | c_fill: crop to fit | q_auto: automatic quality compression
    return originalUrl.replaceFirst('/upload/', '/upload/w_250,c_fill,q_auto/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff2196f3),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: const CircleAvatar(
            backgroundColor: Colors.grey,
            child: Icon(Icons.person, color: Colors.white),
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
                  return ListView.builder(
                    reverse: true, // IMPORTANT: Sticks list to bottom
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      var msgData =
                          snapshot.data!.docs[index].data()
                              as Map<String, dynamic>;
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
                                  color: isMe ? Colors.blue : Colors.grey[300],
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
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          if (hasError)
                                                            IconButton(
                                                              icon: const Icon(
                                                                Icons.refresh,
                                                                color:
                                                                    Colors.red,
                                                                size: 40,
                                                              ),
                                                              onPressed: () {
                                                                // snapshot.data!.docs[index].id gives us the exact Firestore document ID
                                                                retryImageUpload(
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
                                                          color: Colors.white54,
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
                    onPressed: _isUploading ? null : sendImage,
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
                          sendMessage();
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
