import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ChatService {
  final String chatId;
  final String friendId;
  final String currentUserId;
  final ImagePicker _picker = ImagePicker();

  ChatService({
    required this.chatId,
    required this.friendId,
    required this.currentUserId,
  });

  // Get the stream of messages for this chat
  Stream<QuerySnapshot> getMessagesStream() {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true) // Newest at bottom
        .snapshots();
  }

  // Send a text message
  Future<void> sendMessage(String text) async {
    String trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'text': trimmedText,
      'senderId': currentUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
      {
        'participants': [currentUserId, friendId],
        'lastMessage': trimmedText,
        'lastTimestamp': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // Pick an image from gallery
  Future<XFile?> pickImage() async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
  }

  // Send image to Cloudinary and store in Firestore
  Future<DocumentReference> sendImage(XFile image) async {
    // 1. INSTANT PLACEHOLDER: Create the document reference first
    DocumentReference docRef = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'senderId': currentUserId,
      'text': '',
      'imageUrl': '', // Empty for now
      'localPath': image.path, // Save the physical phone path
      'type': 'image',
      'timestamp': FieldValue.serverTimestamp(),
      'isUploading': true, // <-- UI knows to show a spinner
      'hasError': false, // <-- UI knows it hasn't failed yet
    });

    await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
      {
        'participants': [currentUserId, friendId],
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

    return docRef;
  }

  // Retry uploading a failed image
  Future<void> retryImageUpload(String messageId, String localPath) async {
    DocumentReference docRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
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

  // Get thumbnail URL for Cloudinary image optimization
  String getThumbnailUrl(String originalUrl) {
    if (!originalUrl.contains('/upload/')) return originalUrl;
    // w_250: width 250px | c_fill: crop to fit | q_auto: automatic quality compression
    return originalUrl.replaceFirst('/upload/', '/upload/w_250,c_fill,q_auto/');
  }

  // Hides the message only for the person who taps it
  Future<void> deleteForMe(BuildContext context, String messageId,int totalParticipants) async {
    // 1. Close the UI instantly for the user
    Navigator.pop(context); 

    DocumentReference msgRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    DocumentSnapshot snapshot = await msgRef.get();
    
    if (!snapshot.exists) return; // Safety check
    
    var data = snapshot.data() as Map<String, dynamic>;
    List<dynamic> deletedFor = data['deletedFor'] ?? [];

    if (deletedFor.length >= totalParticipants - 1 && !deletedFor.contains(currentUserId)) {
      await msgRef.delete();
    } else {
      // There are still other people who need to see it. Just hide it for me.
      await msgRef.update({
        'deletedFor': FieldValue.arrayUnion([currentUserId])
      });
    }
  }

  // Completely removes the document for everyone (Unsend)
  Future<void> deleteForEveryone(String messageId, BuildContext context) async {
    Navigator.pop(context);
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }
}