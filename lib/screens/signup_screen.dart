import 'dart:convert';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:fb/auth.dart';
import 'package:flutter/material.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController nameController = TextEditingController();
  TextEditingController confirmpasswordController = TextEditingController();
  TextEditingController otpController =
      TextEditingController(); // New controller for OTP

  bool _isloading = false;
  final _formKey = GlobalKey<FormState>();

  String? _generatedOtp; // Variable to hold the generated OTP

  // --- EMAILJS CREDENTIALS ---
  final String serviceId = dotenv.env['EMAILJS_SERVICE_ID'] ?? '';
  final String templateId = dotenv.env['EMAILJS_TEMPLATE_ID'] ?? '';
  final String publicKey = dotenv.env['EMAILJS_PUBLIC_KEY'] ?? ''; // Also known as User ID

  // 1. Function to send the email via EmailJS
  Future<bool> sendOtpEmail(String email, String name, String otp) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    //print('object');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'service_id': serviceId,
          'template_id': templateId,
          'user_id': publicKey,
          'template_params': {'to_name': name, 'to_email': email, 'otp': otp},
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("EmailJS Error: $e");
      return false;
    }
  }

  // 2. Initial Sign Up step (Validates, Generates OTP, Sends Email)
  void initiateSignUp() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isloading = true;
      });

      // Generate a 6-digit OTP
      _generatedOtp = (Random().nextInt(900000) + 100000).toString();

      // Send the email
      bool emailSent = await sendOtpEmail(
        emailController.text,
        nameController.text,
        _generatedOtp!,
      );

      setState(() {
        _isloading = false;
      });

      if (emailSent) {
        if (mounted) showOtpDialog();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to send OTP email. Try again."),
            ),
          );
        }
      }
    }
  }

  // 3. The Dialog where the user enters the OTP
  void showOtpDialog() {
    otpController.clear(); // Clear it in case they are trying again

    showDialog(
      context: context,
      barrierDismissible: false, // Force them to type the code or cancel
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Enter OTP"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("We sent a 6-digit code to ${emailController.text}"),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: "123456",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext), // Close dialog
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (otpController.text == _generatedOtp) {
                  Navigator.pop(dialogContext); // Close dialog
                  finalizeFirebaseSignUp(); // Proceed to Firebase
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Invalid OTP. Try again.")),
                  );
                }
              },
              child: const Text("Verify"),
            ),
          ],
        );
      },
    );
  }

  // 4. The final step: Creating the account in Firebase
  // 4. The final step: Creating the account in Firebase Auth AND Firestore
  void finalizeFirebaseSignUp() async {
    setState(() {
      _isloading = true;
    });

    try {
      // 1. Create the Authentication account
      await Auth().signUpWithEmailPassword(
        emailController.text.trim(),
        passwordController
            .text, // Don't trim passwords, spaces are valid characters!
        nameController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      // 6. Catch ANY error (Auth failure, or our custom Rollback exception)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          // Using replaceAll cleans up the default "Exception: " text from the popup
          SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""))),
        );
      }
    } finally {
      // 7. Turn off the loading spinner no matter what happens
      if (mounted) {
        setState(() {
          _isloading = false;
        });
      }
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff2196f3),
      // Adding an AppBar with a transparent background makes the back button look native and clean
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        // Removed the extra Center so the content aligns nicely with the top when scrolling
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch, // Makes buttons full width
              children: [
                // --- MODERN HEADER ---
                const Icon(
                  Icons.person_add_outlined,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Create Account",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Join Alter to connect with your campus",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 40),

                // --- TEXT FIELDS ---
                TextFormField(
                  style: const TextStyle(color: Colors.white),
                  controller: nameController,
                  keyboardType: TextInputType.name,
                  decoration: InputDecoration(
                    hintText: 'Name',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter your name'
                      : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  style: const TextStyle(color: Colors.white),
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Email',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    bool emailValid = RegExp(
                      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                    ).hasMatch(value);
                    if (!emailValid) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  style: const TextStyle(color: Colors.white),
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter a password'
                      : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  style: const TextStyle(color: Colors.white),
                  controller: confirmpasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Confirm Password',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(
                      Icons.lock_reset_outlined,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) => value != passwordController.text
                      ? 'Passwords do not match'
                      : null,
                ),
                const SizedBox(height: 30),

                // --- WIDE MODERN BUTTON ---
                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xff2196f3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isloading ? null : initiateSignUp,
                    child: _isloading
                        ? const SizedBox(
                            height: 25,
                            width: 25,
                            child: CircularProgressIndicator(
                              color: Color(0xff2196f3),
                              strokeWidth: 3,
                            ),
                          )
                        : const Text(
                            'Sign Up',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // --- LOGIN LINK ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Already have an account?",
                      style: TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: () {
                        // Using pop() is better here because they likely came from the Login screen
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Login",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 20,
                ), // Extra padding at the bottom for scroll clearance
              ],
            ),
          ),
        ),
      ),
    );
  }
}
