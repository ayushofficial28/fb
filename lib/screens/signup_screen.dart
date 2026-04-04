import 'dart:convert';
import 'dart:math';
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
  TextEditingController otpController = TextEditingController(); // New controller for OTP

  bool _isloading = false;
  final _formKey = GlobalKey<FormState>();

  String? _generatedOtp; // Variable to hold the generated OTP

  // --- EMAILJS CREDENTIALS ---
  final String serviceId = 'YOUR_SERVICE_ID';
  final String templateId = 'YOUR_TEMPLATE_ID';
  final String publicKey = 'YOUR_PUBLIC_KEY'; // Also known as User ID

  // 1. Function to send the email via EmailJS
  Future<bool> sendOtpEmail(String email, String name, String otp) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'service_id': serviceId,
          'template_id': templateId,
          'user_id': publicKey,
          'template_params': {
            'to_name': name,
            'to_email': email,
            'otp': otp,
          }
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
      setState(() { _isloading = true; });

      // Generate a 6-digit OTP
      _generatedOtp = (Random().nextInt(900000) + 100000).toString();

      // Send the email
      bool emailSent = await sendOtpEmail(
        emailController.text, 
        nameController.text, 
        _generatedOtp!
      );

      setState(() { _isloading = false; });

      if (emailSent) {
        if (mounted) showOtpDialog();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to send OTP email. Try again.")),
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
  void finalizeFirebaseSignUp() async {
    setState(() { _isloading = true; });
    try {
      await Auth().signUpWithEmailPassword(
          emailController.text, passwordController.text, nameController.text);
      
      if (mounted) {
        Navigator.pop(context); // Close the signup screen entirely
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isloading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff2196f3),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView( // Added to prevent keyboard overflow
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          hintText: 'Name',
                          hintStyle: TextStyle(color: Colors.white),
                        ),
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Please enter your name' : null),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        hintStyle: TextStyle(color: Colors.white),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        bool emailValid = RegExp(
                                r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
                            .hasMatch(value);
                        if (!emailValid) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'Password',
                          hintStyle: TextStyle(color: Colors.white),
                        ),
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Please enter a password' : null),
                    const SizedBox(height: 20),
                    TextFormField(
                        controller: confirmpasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'Confirm Password',
                          hintStyle: TextStyle(color: Colors.white),
                        ),
                        validator: (value) => value != passwordController.text
                            ? 'Passwords do not match'
                            : null),
                    const SizedBox(height: 30),
                    ElevatedButton(
                        onPressed: _isloading ? null : initiateSignUp, // Changed function here
                        child: _isloading
                            ? const CircularProgressIndicator()
                            : const Text('Sign Up'))
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}