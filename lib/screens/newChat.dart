import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fb/screens/chatRoom/chat_room_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  FirebaseFirestore instance = FirebaseFirestore.instance;
  late Future<QuerySnapshot> future;
  bool _isSearching = false;
  String query = '';
  final TextEditingController searchController = TextEditingController();
  void initState() {
    super.initState();
    future = instance
        .collection('users')
        .where('uid', isNotEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !_isSearching,
        title: _isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search users...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 18),
                onChanged: (value) {
                  setState(() {
                    query = value.toLowerCase();
                  });
                },
              )
            : Text('Alter'),
        backgroundColor: Color(0xff2196f3),
        actions: [IconButton(onPressed: () {
          setState(() {
            _isSearching=!_isSearching;
            if(!_isSearching){
              query='';
              searchController.clear();
            }
          });
        }, icon:_isSearching?Icon(Icons.close):Icon(Icons.search))],
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting){
              return Center(child: CircularProgressIndicator());}
            if (snapshot.hasError){
              return Center(child: Text('Error: ${snapshot.error}'));}
            
            var allUsers = snapshot.data!.docs;

            var users=allUsers.where((doc){
              var user=doc.data() as Map<String, dynamic>;
              String name=user['name'].toString().toLowerCase();
              String mail=user['email'].toString().toLowerCase();
              return name.contains(query) || mail.contains(query);
            }).toList();
            if (users.isEmpty) {
              return const Center(child: Text('No users found'));
            }
            return ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                var user = users[index].data() as Map<String, dynamic>;
                return ListTile(
                  leading: CircleAvatar(child: Text(user['name'][0])),
                  title: Text(user['name']),
                  subtitle: Text(user['email']),
                  onTap: () {
                    String uid = FirebaseAuth.instance.currentUser!.uid;
                    String friendId = user['uid'];

                    List<String> participants = [uid, friendId];
                    participants.sort();
                    String chatId = participants.join('_');
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(
                          chatId: chatId,
                          friendId: friendId,
                          friendName: user['name'],
                          photoUrl: user['photoUrl'] ?? '',
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
