import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Auth{
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<User> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return result.user!;
    } on FirebaseAuthException catch (e) {
      throw Exception('Failed to sign in: ${e.message}');
    }
  }
  Future<void> signUpWithEmailPassword(String email, String password, String name) async {
    try {

      
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser != null) {
        try {
          await currentUser.updateDisplayName(name);
          // 3. Try to create their profile document in Firestore
          await _firestore.collection('users').doc(currentUser.uid).set({
            'uid': currentUser.uid,
            'email': email,
            'name': name,
            'profilePic': '', // Default empty profile picture
            'createdAt': FieldValue.serverTimestamp(),
          });

        } catch (firestoreError) {
          // 5. THE ROLLBACK: Firestore failed (e.g., network drop). Delete the Auth account!
          await currentUser.delete();
          
          // Throw a custom error so the catch block below shows a helpful message
          throw Exception("Database connection failed. Account creation cancelled. Please try again.");
        }
      }

    } on FirebaseAuthException catch (e) {
      throw Exception(e.code);
    }
  }

  Future<void> updateDisplayName(String newName) async {
  User? user = _auth.currentUser;
  if (user != null) {
    // 1. Update Firebase Auth record
    await user.updateDisplayName(newName);
    
    // 2. Update Firestore document
    await _firestore.collection('users').doc(user.uid).update({
      'name': newName,
    });
    
    // Optional: Refresh the user to ensure the app sees the change immediately
    await user.reload();
  } else {
    throw Exception("No user logged in.");
  }
}
}