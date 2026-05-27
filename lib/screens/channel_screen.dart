import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fb/screens/fullScreenImage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ChannelFeedPage extends StatefulWidget {
  final String channelId;
  final String channelName;

  const ChannelFeedPage({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  State<ChannelFeedPage> createState() => _ChannelFeedPageState();
}

class _ChannelFeedPageState extends State<ChannelFeedPage> {
  final TextEditingController _messageController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final ImagePicker _picker = ImagePicker();
  late Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('channels') // Pointing to channels instead of private chats
        .doc(widget.channelId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // --- LOGIC: SEND TEXT ---
  void sendMessage() async {
    String text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    await FirebaseFirestore.instance
        .collection('channels')
        .doc(widget.channelId)
        .collection('messages')
        .add({
      'text': text,
      'senderId': currentUserId, // Stored for admin but hidden in UI
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // --- LOGIC: SEND IMAGE (REUSED YOUR CLOUDINARY LOGIC) ---
  Future<void> sendImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;

    DocumentReference docRef = await FirebaseFirestore.instance
        .collection('channels')
        .doc(widget.channelId)
        .collection('messages')
        .add({
      'senderId': currentUserId,
      'text': '',
      'imageUrl': '',
      'localPath': image.path,
      'type': 'image',
      'timestamp': FieldValue.serverTimestamp(),
      'isUploading': true,
      'hasError': false,
    });

    try {
      String cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? ''; // Keep your existing cloud name
      Uri uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

      var request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = 'alter_chats';
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channelName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            

            // --- FEED LIST ---
            Expanded(
              child: StreamBuilder(
                stream: _stream,
                builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("No confessions yet. Be the first? 🤫"));
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      var msgData = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                      String messageType = msgData['type'] ?? 'text';
                      
                      // Uniform Card for all users (Anonymity)
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: messageType == 'image' 
                                  ? _buildImageContent(msgData, index, snapshot)
                                  : Text(
                                      msgData['text'] ?? '',
                                      style: const TextStyle(fontSize: 16, height: 1.4),
                                    ),
                            ),
                            // Tiny timestamp at the bottom of the card
                            Padding(
                              padding: const EdgeInsets.only(left: 12, bottom: 8),
                              child: Text(
                                _formatTime(msgData['timestamp']),
                                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // --- INPUT BAR ---
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // --- UI HELPER: IMAGE POSTS ---
  Widget _buildImageContent(Map<String, dynamic> msgData, int index, AsyncSnapshot<QuerySnapshot> snapshot) {
    bool isUploading = msgData['isUploading'] ?? false;
    bool hasError = msgData['hasError'] ?? false;
    String imageUrl = msgData['imageUrl'] ?? '';
    String localPath = msgData['localPath'] ?? '';

    return GestureDetector(
      onTap: () {
        if (imageUrl.isNotEmpty && !isUploading) {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => FullScreenImage(imageUrl: imageUrl),
          ));
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: isUploading || hasError
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Image.file(File(localPath), height: 200, width: double.infinity, fit: BoxFit.cover, color: Colors.black26, colorBlendMode: BlendMode.darken),
                  if (isUploading) const CircularProgressIndicator(color: Colors.white),
                  if (hasError) const Icon(Icons.error, color: Colors.red, size: 40),
                ],
              )
            : Image.network(imageUrl, height: 200, width: double.infinity, fit: BoxFit.cover),
      ),
    );
  }

  // --- UI HELPER: INPUT BAR ---
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey[200]!))),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_a_photo_outlined, color: Colors.deepPurple),
            onPressed: sendImage,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Confess something...',
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 5),
          CircleAvatar(
            backgroundColor: Colors.deepPurple,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return "";
    DateTime date = (timestamp as Timestamp).toDate();
    return DateFormat('h:mm a').format(date);
  }
}