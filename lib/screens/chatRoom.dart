import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_api/src/request/model/uploader_params.dart';
import 'package:cloudinary_api/uploader/cloudinary_uploader.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
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
    final ImagePicker picker = ImagePicker();

    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;
    setState(() {
      _isUploading = true;
    });

    try {
  // 1. Set up the raw API endpoint
  String cloudName = 'dpalozx6i'; 
  Uri uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  // 2. Create a "Multipart" request (the standard way to send files over the web)
  var request = http.MultipartRequest('POST', uri);

  // 3. Add your unsigned preset
  request.fields['upload_preset'] = 'alter_chats';

  // 4. Add the file directly using the file path! 
  request.files.add(await http.MultipartFile.fromPath('file', image.path));

  // 5. Send it to Cloudinary
  var response = await request.send();

  // 6. Read the response
  if (response.statusCode == 200) {
    // Success! Decode the JSON response
    var responseData = await response.stream.toBytes();
    var result = String.fromCharCodes(responseData);
    var jsonMap = jsonDecode(result);
    
    String imageUrl = jsonMap['secure_url'];
    print("SUCCESS: Native HTTP upload to $imageUrl");

    // Save URL to Firestore
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
      'senderId': currentUserId,
      'text': '', 
      'imageUrl': imageUrl,
      'type': 'image', 
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update the recent message preview
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .update({
      'lastMessage': '📷 Photo',
      'lastTimestamp': FieldValue.serverTimestamp(),
    });

  } else {
    // If it fails, print the exact server response
    var responseData = await response.stream.toBytes();
    var errorResult = String.fromCharCodes(responseData);
    print('--- HTTP UPLOAD FAILED ---');
    print('Status Code: ${response.statusCode}');
    print('Server Error: $errorResult');
  }

} catch (e) {
  print("--- APP CRASHED DURING HTTP UPLOAD ---");
  print(e.toString());
}
    // } catch (e) {
    //   if (mounted) {
    //     showDialog(
    //       context: context,
    //       builder: (BuildContext context) {
    //         return AlertDialog(
    //           shape: RoundedRectangleBorder(
    //             borderRadius: BorderRadius.circular(
    //               15,
    //             ), // Matches your chat bubble style
    //           ),
    //           title: const Row(
    //             children: [
    //               Icon(Icons.error_outline, color: Colors.red),
    //               SizedBox(width: 8),
    //               Text("Upload Failed"),
    //             ],
    //           ),
    //           content: const Text(
    //             "There was an issue sending your image. Please check your connection and try again.",
    //           ),
    //           actions: [
    //             TextButton(
    //               onPressed: () {
    //                 Navigator.of(context).pop(); // This line closes the popup
    //               },
    //               child: const Text(
    //                 "OK",
    //                 style: TextStyle(color: Color(0xff2196f3), fontSize: 16),
    //               ),
    //             ),
    //           ],
    //         );
    //       },
    //     );
    //   }
    // } 
    finally {
      setState(() {
        _isUploading = false;
      });
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
                      bool isMe = msgData['senderId'] == currentUserId;
                      String messageType = msgData['type'] ?? 'text';
                      String timeString = "";
                      if (msgData['timestamp'] != null) {
                        Timestamp t = msgData['timestamp'] as Timestamp;
                        timeString = DateFormat('h:mm a').format(t.toDate());
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
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  FullScreenImage(
                                                    imageUrl:
                                                          msgData['imageUrl']
                                                        ??
                                                        '',
                                                  ),
                                            ),
                                          );
                                        },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ), // Keeps the image inside your curved box
                                          child: Image.network(
                                            // Let's temporarily remove getThumbnailUrl to make sure that isn't breaking the link
                                            msgData['imageUrl'] ??
                                                'https://via.placeholder.com/150',
                                            width: 220,
                                            fit: BoxFit.cover,
                                            // 1. THIS CATCHES BROKEN LINKS
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  print(
                                                    "IMAGE ERROR: $error",
                                                  ); // This will print the exact reason it failed
                                                  return const SizedBox(
                                                    width: 220,
                                                    height: 220,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.broken_image,
                                                        color: Colors.white,
                                                        size: 50,
                                                      ),
                                                    ),
                                                  );
                                                },
                                            // 2. YOUR EXISTING LOADING SPINNER
                                            loadingBuilder:
                                                (
                                                  context,
                                                  child,
                                                  loadingProgress,
                                                ) {
                                                  if (loadingProgress == null)
                                                    return child;
                                                  return const SizedBox(
                                                    width: 220,
                                                    height: 220,
                                                    child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                            color: Colors.white,
                                                          ),
                                                    ),
                                                  );
                                                },
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
