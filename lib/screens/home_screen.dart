import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fb/auth.dart';
import 'package:fb/screens/chatScreen.dart';
import 'package:fb/screens/confessions_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _page = 0;
  late PageController pageController;
  String? myPhotoUrl = FirebaseAuth.instance.currentUser?.photoURL;
  String currentUserName =
      FirebaseAuth.instance.currentUser?.displayName ?? "No display name set";
  @override
  void initState() {
    super.initState();
    pageController = PageController();
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  File? _imageFile;
  bool _isUploading = false;

  Future<void> _updateProfilePhoto() async {
    final ImagePicker picker = ImagePicker();

    // 1. Pick the image
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
      _isUploading = true;
    });

    try {
      // --- CLOUDINARY UPLOAD SECTION ---
      String cloudName = 'dpalozx6i'; // TODO: Add your cloud name
      String uploadPreset = 'alter_chats'; // TODO: Add your upload preset

      Uri uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      var request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(
        await http.MultipartFile.fromPath('file', _imageFile!.path),
      );

      // Send and wait for response
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // Parse the JSON to get the URL
        final responseData = jsonDecode(response.body);
        String newImageUrl = responseData['secure_url'];

        // --- FIREBASE UPDATE SECTION ---
        User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // 1. Update Firebase Auth (for local app use)
          await user.updatePhotoURL(newImageUrl);

          // 2. Update Firestore (so other users see it in chats)
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'profilePic': newImageUrl});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Profile picture updated!")),
            );
          }
          setState(() {
            // 1. Update the local variable your UI is actually using
            myPhotoUrl = newImageUrl;

            // 2. Clear the local file since the network version is now the source of truth
            _imageFile = null;
          });

          // 3. Force Firebase Auth to refresh its local cache
          await user.reload();
        }
      } else {
        throw Exception(
          "Cloudinary upload failed with status: ${response.statusCode}",
        );
      }
    } catch (e) {
      print("Upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error updating profile photo.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    // 1. Turn on the loading spinner so the user knows something is happening
    setState(() => _isUploading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // 2. Delete the photo URL from Firebase Authentication
        await user.updatePhotoURL("");

        // 3. Delete the photo URL from your Firestore database
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'profilePic': ""});

        // 4. Force the local Firebase user to refresh
        await user.reload();

        // 5. Update the UI instantly (The "Optimistic UI" approach)
        if (mounted) {
          setState(() {
            myPhotoUrl = ""; // Clears the network image
            _imageFile = null; // Clears any local gallery image
          });

          // 6. Show a quick confirmation popup at the bottom of the screen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile photo removed")),
          );
        }
      }
    } catch (e) {
      print("Error removing photo: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to remove photo. Please try again."),
          ),
        );
      }
    } finally {
      // 7. Turn off the loading spinner whether it succeeded or failed
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showEditNameDialog() {
    // Initialize the controller with the current name
    bool isChanging = false;
    TextEditingController nameEditController = TextEditingController(
      text: currentUserName,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Name"),
        content: TextField(
          controller: nameEditController,
          decoration: const InputDecoration(
            hintText: "Enter new name",
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: !isChanging
                ? () async {
                    String newName = nameEditController.text.trim();
                    if (newName.isNotEmpty && newName != currentUserName) {
                      try {
                        setState(() {
                          isChanging = true;
                        });
                        // Call the backend logic we just wrote
                        await Auth().updateDisplayName(newName);

                        setState(() {
                          currentUserName = newName; // Update UI locally
                        });

                        if (context.mounted) {
                          Navigator.pop(context); // Close dialog
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Name updated successfully!"),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Error: ${e.toString()}")),
                          );
                        }
                      }
                    } else {
                      Navigator.pop(context); // No change made, just close
                    }
                  }
                : null,
            child: Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      // Modern rounded corners
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          // Ensures it doesn't overlap with system nav bars
          child: Wrap(
            // Wrap makes the height fit the content (2 buttons)
            children: [
              // The "Grab Handle" at the top
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  height: 4,
                  width: 35,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // 1. Change Password Button
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text("Change Password"),
                onTap: () {
                  Navigator.pop(context); // Close the sheet first
                  _sendPasswordReset(); // Your email logic
                },
              ),

              // 2. Logout Button
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  "Logout",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context); // Close the sheet first
                  _showLogoutDialog(); // Your confirmation dialog
                },
              ),

              const SizedBox(height: 20), // Bottom padding
            ],
          ),
        );
      },
    );
  }

  void _sendPasswordReset() async {
    try {
      // Replace with your actual user email variable
      print(
        "Attempting to send password reset to: ${FirebaseAuth.instance.currentUser!.email!}",
      );
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: FirebaseAuth.instance.currentUser!.email!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reset link sent! Check your email.")),
        );
      }
    } catch (e) {
      debugPrint("Password reset error: $e");
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to log out of Alter?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              // 1. Pop the dialog off the screen IMMEDIATELY
              Navigator.pop(context);

              // 2. NOW trigger the Firebase sign out
              await FirebaseAuth.instance.signOut();

            },
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(0.0),
          child: IconButton(
            icon: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey[300],
                  // If the URL exists, load it as the background
                  backgroundImage:
                      (myPhotoUrl != null && myPhotoUrl!.isNotEmpty)
                      ? NetworkImage(myPhotoUrl!)
                      : null,
                  // If the URL is empty, draw a default icon inside
                  child: (myPhotoUrl == null || myPhotoUrl!.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                if (_isUploading)
                  Container(
                    width:
                        100, // Matches the diameter of the CircleAvatar (radius * 2)
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5), // Dims the photo
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              if (_isUploading) return;
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return Dialog(
                    // Gives the dialog a standard rectangular shape with slightly softened corners
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip
                        .antiAlias, // Ensures the image respects the border radius
                    child: Column(
                      mainAxisSize: MainAxisSize
                          .min, // Prevents the dialog from stretching full-screen
                      children: [
                        // 1. THE COMPLETE RECTANGULAR IMAGE
                        if (myPhotoUrl != null && myPhotoUrl!.isNotEmpty)
                          Image.network(
                            myPhotoUrl!,
                            fit: BoxFit
                                .contain, // Ensures the entire image is visible without cropping
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.all(50.0),
                            child: Icon(
                              Icons.person,
                              size: 100,
                              color: Colors.grey,
                            ),
                          ),

                        // 2. THE EDIT OPTION
                        Container(
                          width: double.infinity,
                          color: Colors.white,
                          // Added some padding so it doesn't hug the absolute bottom of the screen
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              // 1. EDIT BUTTON (Takes up left half)
                              Expanded(
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    _updateProfilePhoto();
                                  },
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Change Photo'),
                                ),
                              ),

                              // A subtle vertical line to separate them
                              Container(
                                height: 40,
                                width: 1,
                                color: Colors.black12,
                              ),

                              // 2. REMOVE BUTTON (Takes up right half)
                              Expanded(
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    foregroundColor: Colors.red,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    _removeProfilePhoto();
                                  },
                                  icon: const Icon(Icons.delete),
                                  label: const Text('Remove Photo'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),

                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text("Display Name"),
                          subtitle: Text(
                            currentUserName,
                          ), // Whatever variable holds their name
                          trailing: IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () {
                              Navigator.pop(context);
                              _showEditNameDialog();
                            },
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
        backgroundColor: _page == 0 ? Color(0xff2196f3) : Colors.deepPurple,
        title: Text('Alter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsMenu(context),
          ),
        ],
      ),
      body: SafeArea(
        child: PageView(
          controller: pageController,
          onPageChanged: (index) {
            setState(() {
              _page = index;
            });
          },
          children: [
            Center(child: ChatScreen()),
            Center(child: ConfessionsPage()),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _page,
        backgroundColor: _page == 0
            ? const Color(0xff2196f3)
            : Colors.deepPurple,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.black38,
        onTap: (int index) {
          pageController.jumpToPage(index);
        },

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.theater_comedy),
            label: 'Confessions',
          ),
        ],
      ),
    );
  }
}
