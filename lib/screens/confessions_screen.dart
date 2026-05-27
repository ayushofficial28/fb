import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fb/screens/channel_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ConfessionsPage extends StatefulWidget {
  @override
  State<ConfessionsPage> createState() => _ConfessionsPageState();
}

class _ConfessionsPageState extends State<ConfessionsPage> {
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // FAB is the trigger for your modern bottom menu
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurple,
        onPressed: () => _showJoinOrCreateMenu(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                "Confessions",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('channels')
                    .where('members', arrayContains: uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  var channels = snapshot.data!.docs;

                  if (channels.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      var channel = channels[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text(channel['name'][0])),
                        title: Text(channel['name']),
                        subtitle: Text("Code: ${channel['code']}"),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChannelFeedPage(
                              channelId: channel.id,
                              channelName: channel['name'],
                            ),
                          ),
                        ),
                        onLongPress: () => showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Leave Channel'),
                            content: const Text(
                              'Are you sure you want to leave this channel?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await channel.reference.update({
                                      'members': FieldValue.arrayRemove([uid]),
                                    });
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Left channel successfully",
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text("Error: $e")),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Leave'),
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
          ],
        ),
      ),
    );
  }

  // --- THE MODERN BOTTOM MENU ---
  void _showJoinOrCreateMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Wrap(
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 40,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text("Join a Channel"),
            onTap: () {
              Navigator.pop(context);
              _showJoinDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_box_outlined),
            title: const Text("Create a Channel"),
            onTap: () {
              Navigator.pop(context);
              _showCreateDialog();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- JOIN LOGIC ---
  void _showJoinDialog() {
    TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Join Channel"),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(hintText: "Enter Channel Code"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              var query = await FirebaseFirestore.instance
                  .collection('channels')
                  .where('code', isEqualTo: codeController.text.trim())
                  .get();
              if (query.docs.isNotEmpty) {
                await query.docs.first.reference.update({
                  'members': FieldValue.arrayUnion([uid]),
                });
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Channel not found")),
                  );
                }
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text("Join"),
          ),
        ],
      ),
    );
  }

  // --- CREATE LOGIC ---
  void _showCreateDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create Channel"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: "Channel Name"),
            ),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(hintText: "Unique Code"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              String inputCode = codeController.text.trim();
              String channelName = nameController.text.trim();

              if (inputCode.isEmpty || channelName.isEmpty) return;

              // 1. FAST CHECK: See if anyone else is using this code
              var existing = await FirebaseFirestore.instance
                  .collection('channels')
                  .where('code', isEqualTo: inputCode)
                  .get();

              if (existing.docs.isNotEmpty) {
                if(ctx.mounted){
                Navigator.pop(ctx);
                }
                // Code is taken! Show a quick alert or snackbar
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("That code is already taken! Try another."),
                    ),
                  );
                }
                return; // Stop here
              }

              // 2. CREATE: If we got here, the code is unique
              await FirebaseFirestore.instance.collection('channels').add({
                'name': channelName,
                'code': inputCode,
                'members': [uid],
                'createdBy': uid,
                'timestamp': FieldValue.serverTimestamp(),
              });

              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 80, color: Colors.grey[300]),
          const Text(
            "No channels yet. Tap + to start!",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
