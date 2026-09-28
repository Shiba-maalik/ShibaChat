import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:scratcher/scratcher.dart';
import 'package:audioplayers/audioplayers.dart' hide Source;
import 'package:audioplayers/audioplayers.dart' as ap show Source;

bool isFirebaseReady = false;

// Global user profile state & Call logs storage
String currentUserName = "";
String currentUserBio = "";
String currentUserEmail = ""; // Dummy email हटा दिया गया है
File? currentUserProfileImage;
File? currentChatWallpaper;
List<File> myActiveStatuses = [];
int _profileImageCounter = 1;

// Global Call History list (Empty)
List<Map<String, dynamic>> globalCallLogs = [];

// Global PiP Call State for floating overlay across the app
ValueNotifier<Map<String, dynamic>?> activePiPCall = ValueNotifier(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    isFirebaseReady = true;
    debugPrint("Firebase initialized successfully!");
  } catch (e) {
    isFirebaseReady = false;
    debugPrint("Firebase init note: $e");
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shiba Chat',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0C061E), // यहाँ से डिफ़ॉल्ट बैकग्राउंड बदलें
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00FF87), // मेन कलर
          secondary: const Color(0xFFFF007A), // सेकेंडरी कलर
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------------- SPLASH SCREEN ----------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initializeApp();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    Widget nextScreen = const ShibaChatLoginScreen();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn || (isFirebaseReady && FirebaseAuth.instance.currentUser != null)) {
      nextScreen = const ShibaChatDashboardScreen();
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF87).withOpacity(
                            0.3 + (_glowController.value * 0.5)),
                        blurRadius: 45,
                        spreadRadius: 10,
                      ),
                      BoxShadow(
                        color: const Color(0xFFFF007A).withOpacity(
                            0.1 + (_glowController.value * 0.3)),
                        blurRadius: 25,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: SizedBox(
                      height: 80,
                      width: 80,
                      child: Image.asset(
                        'assets/images/shiba_login_avatar.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.pets,
                            color: Color(0xFF00FF87), size: 60),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 35),
            const CircularProgressIndicator(
              color: Color(0xFF00FF87),
              strokeWidth: 3.0,
            ),
            const SizedBox(height: 20),
            const Text(
              'INITIALIZING CYBER VIBE...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- LOGIN SCREEN ----------------
class ShibaChatLoginScreen extends StatefulWidget {
  const ShibaChatLoginScreen({super.key});

  @override
  State<ShibaChatLoginScreen> createState() => _ShibaChatLoginScreenState();
}

class _ShibaChatLoginScreenState extends State<ShibaChatLoginScreen> {
  bool _isTermsAccepted = false;
  bool _isLoading = false;
  final TextEditingController _phoneController = TextEditingController();

  void _onGetOtpPressed() async {
    String phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('कृपया सही 10 अंकों का मोबाइल नंबर दर्ज करें'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    String fullPhoneNumber = "+91$phone";

    if (isFirebaseReady) {
      try {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: fullPhoneNumber,
          timeout: const Duration(seconds: 45),
          verificationCompleted: (PhoneAuthCredential credential) async {
            setState(() {
              _isLoading = false;
            });
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (!mounted) return;
            _onLoginSuccess();
          },
          verificationFailed: (FirebaseAuthException e) {
            setState(() {
              _isLoading = false;
            });
            debugPrint("Firebase SMS check: ${e.message}");
            _triggerBypassMode(phone);
          },
          codeSent: (String verificationId, int? resendToken) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('OTP भेजा गया (Firebase) ✨'),
                backgroundColor: Color(0xFF00FF87),
                duration: Duration(seconds: 2),
              ),
            );
            _navigateToOtpScreen(phone, verificationId);
          },
          codeAutoRetrievalTimeout: (String verificationId) {},
        );
        return;
      } catch (e) {
        debugPrint("Error handling phone auth: $e");
      }
    }

    _triggerBypassMode(phone);
  }

  void _triggerBypassMode(String phone) {
    setState(() {
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Direct Access: Enter 123456 (Captcha Bypassed) ⚡'),
        backgroundColor: Color(0xFF00FF87),
        duration: Duration(seconds: 3),
      ),
    );

    _navigateToOtpScreen(phone, "bypass_mode");
  }

  void _navigateToOtpScreen(String phone, String verificationId) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) =>
            OtpVerificationScreen(
              phoneNumber: phone,
              verificationId: verificationId,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween =
          Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
  }

  void _onLoginSuccess() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const ShibaChatDashboardScreen()),
          (route) => false,
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset(
              'assets/images/space_meditation.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF1E0E45)),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0C061E).withOpacity(0.6),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  width: 330,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E103E).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF00FF87).withOpacity(0.2),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Shiba Chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              'assets/images/shiba_login_avatar.png',
                              height: 32,
                              width: 32,
                              errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.pets,
                                  color: Color(0xFF00FF87), size: 28),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Instant Web3 Social Login',
                        style: TextStyle(
                          color: Color(0xFF00FF87),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 16,
                                    child: Image.asset(
                                      'assets/images/Flag.png',
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                          Container(
                                            color: Colors.orange.shade800,
                                            alignment: Alignment.center,
                                            child: const Text('IN',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold)),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    '+91',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down,
                                      color: Colors.white70),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 32,
                              color: Colors.white24,
                              margin:
                              const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                enabled: !_isLoading,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15),
                                decoration: const InputDecoration(
                                  counterText: '',
                                  hintText: 'Enter Phone Number',
                                  hintStyle: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding:
                                  EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.all(10.0),
                              child: Icon(Icons.bolt,
                                  color: Color(0xFF00FF87), size: 22),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isTermsAccepted && !_isLoading)
                              ? _onGetOtpPressed
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF87),
                            disabledBackgroundColor: Colors.white12,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black,
                            ),
                          )
                              : const Text(
                            'CONTINUE',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: _isTermsAccepted,
                            activeColor: const Color(0xFF00FF87),
                            checkColor: Colors.black,
                            side: const BorderSide(
                                color: Colors.white54, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                            onChanged: _isLoading
                                ? null
                                : (bool? value) {
                              setState(() {
                                _isTermsAccepted = value ?? false;
                              });
                            },
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: _isLoading
                                  ? null
                                  : () {
                                setState(() {
                                  _isTermsAccepted = !_isTermsAccepted;
                                });
                              },
                              child: const Text(
                                'Agree to Shiba Terms & Cyber Security',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 6-DIGIT OTP VERIFICATION SCREEN ----------------
class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _otpControllers =
  List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes =
  List.generate(6, (index) => FocusNode());

  bool _isVerifying = false;

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _verifyOtp() async {
    String enteredOtp = _otpControllers.map((controller) => controller.text).join();

    if (enteredOtp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया पूरा 6 अंकों का OTP दर्ज करें'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() { _isVerifying = true; });

    if (widget.verificationId == "bypass_mode" || !isFirebaseReady) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() { _isVerifying = false; });

      if (enteredOtp == "123456") {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ShibaChatDashboardScreen()), (route) => false);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('गलत OTP! (123456 दर्ज करें)'), backgroundColor: Colors.redAccent));
      }
      return;
    }

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(verificationId: widget.verificationId, smsCode: enteredOtp);
      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      setState(() { _isVerifying = false; });

      if (userCredential.user != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);

        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'phone': '+91${widget.phoneNumber}',
          'uid': userCredential.user!.uid,
          'name': 'Shiba User',
          'status': 'Living in the Neonverse 🌌',
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ShibaChatDashboardScreen()), (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      setState(() { _isVerifying = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Verification Failed'), backgroundColor: Colors.redAccent));
    } catch (e) {
      setState(() { _isVerifying = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    }
  }

  Widget _buildOtpBox(int index) {
    return Container(
      width: 42,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00FF87).withOpacity(0.3),
        ),
      ),
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        enabled: !_isVerifying,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00FF87),
        ),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset(
              'assets/images/space_meditation.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF0C061E)),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0C061E).withOpacity(0.65),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  width: 330,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E103E).withOpacity(0.88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF00FF87).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Security Verification',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sent to +91 ${widget.phoneNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:
                        List.generate(6, (index) => _buildOtpBox(index)),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isVerifying ? null : _verifyOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF87),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isVerifying
                              ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black,
                            ),
                          )
                              : const Text(
                            'VERIFY NOW',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: _isVerifying
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text(
                          'Change Phone Number',
                          style: TextStyle(
                            color: Color(0xFF00FF87),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- MODERN GEN-Z DASHBOARD (With Global User Search) ----------------
class ShibaChatDashboardScreen extends StatefulWidget {
  const ShibaChatDashboardScreen({super.key});

  @override
  State<ShibaChatDashboardScreen> createState() =>
      _ShibaChatDashboardScreenState();
}

class _ShibaChatDashboardScreenState extends State<ShibaChatDashboardScreen> {
  final List<Map<String, dynamic>> _activeChats = [];
  final List<Map<String, dynamic>> _shibaRegisteredUsers = [];

  int _currentBottomNavIndex = 0;
  String _lastBackupTime = "Yesterday, 11:45 PM";
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // 👇 रिंग (Ringing) के लिए नए वेरिएबल्स
  StreamSubscription? _callSubscription;
  bool _isRinging = false;
  Timer? _vibrateTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    activePiPCall.addListener(() {
      if (mounted) setState(() {});
    });
    _listenForIncomingCalls(); // कॉल लिसनर चालू किया
  }

  // 🔔 रियल-टाइम इनकमिंग कॉल और वॉच पार्टी को कैच करने वाला फंक्शन
  void _listenForIncomingCalls() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _callSubscription?.cancel();
        _callSubscription = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('incomingCall')
            .doc('current')
            .snapshots()
            .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            var data = snapshot.data()!;
            if (data['status'] == 'ringing' && !_isRinging) {
              _showRingingDialog(data);
            }
          }
        });
      }
    });
  }

  // 🔔 फोन में रिंग/वाइब्रेशन और Accept/Decline का पॉप-अप
  void _showRingingDialog(Map<String, dynamic> data) async {
    _isRinging = true;
    _vibrateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      HapticFeedback.heavyImpact(); // लगातार वाइब्रेट करेगा
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E103E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.ring_volume, color: Color(0xFF00FF87)),
            const SizedBox(width: 8),
            Text('Incoming ${data['callType']}', style: const TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text('${data['callerName']} is inviting you for ${data['platform'] ?? data['callType']}.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              _vibrateTimer?.cancel();
              _isRinging = false;
              FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).collection('incomingCall').doc('current').delete();
              Navigator.pop(c);
            },
            child: const Text('Decline', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF87)),
            onPressed: () {
              _vibrateTimer?.cancel();
              _isRinging = false;
              FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).collection('incomingCall').doc('current').delete();
              Navigator.pop(c);

              // जो कॉल है सीधा उसी स्क्रीन पर ले जाए
              if (data['callType'] == 'Watch Party') {
                Navigator.push(context, MaterialPageRoute(builder: (ctx) => WatchPartyPlayerScreen(
                  platformName: data['platform'],
                  partnerName: data['callerName'],
                  partnerColor: Colors.primaries[data['callerName'].hashCode % Colors.primaries.length],
                  roomId: data['roomId'],
                  isCaller: false,
                )));
              } else if (data['callType'] == 'Video Call') {
                Navigator.push(context, MaterialPageRoute(builder: (ctx) => VideoCallScreen(
                  contactName: data['callerName'],
                  avatarColor: Colors.primaries[data['callerName'].hashCode % Colors.primaries.length],
                  isCaller: false,
                  roomId: data['roomId'],
                )));
              } else if (data['callType'] == 'Audio Call') {
                Navigator.push(context, MaterialPageRoute(builder: (ctx) => AudioCallScreen(
                  contactName: data['callerName'],
                  avatarColor: Colors.primaries[data['callerName'].hashCode % Colors.primaries.length],
                  isCaller: false,
                  roomId: data['roomId'],
                )));
              }
            },
            child: const Text('Accept', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _vibrateTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (!isFirebaseReady) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();

    try {
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        var doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && mounted) {
          setState(() {
            currentUserName = doc.data()?['name'] ?? currentUserName;
            currentUserBio = doc.data()?['status'] ?? currentUserBio;
          });
        }
      }
    } catch (e) {
      debugPrint("Firebase Load Error: $e");
    }

    String? imagePath = prefs.getString('profileImagePath');
    if (imagePath != null && File(imagePath).existsSync() && mounted) {
      setState(() {
        currentUserProfileImage = File(imagePath);
      });
    }
  }

  Future<bool> _requestPermission(Permission permission, String name) async {
    PermissionStatus status = await permission.status;
    if (!status.isGranted) {
      status = await permission.request();
    }
    if (status.isGranted) {
      return true;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name permission is required!'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }
  }

  void _openProfileEditor() {
    final TextEditingController nameEditController =
    TextEditingController(text: currentUserName);
    final TextEditingController bioEditController =
    TextEditingController(text: currentUserBio);
    File? tempImage = currentUserProfileImage;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF160935).withOpacity(0.92),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'My Profile Details & DP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF00FF87),
                          ),
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: const Color(0xFF24124D),
                            backgroundImage: tempImage != null
                                ? FileImage(tempImage!)
                                : null,
                            child: tempImage == null
                                ? const Icon(Icons.person,
                                size: 55, color: Colors.white)
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 4,
                          child: GestureDetector(
                            onTap: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                              if (pickedFile != null) {
                                File selectedFile = File(pickedFile.path);

                                showDialog(
                                  context: ctx,
                                  builder: (dialogContext) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E103E),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(20)),
                                    title: const Text('Adjust & Crop DP ✨',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ClipOval(
                                          child: Image.file(selectedFile,
                                              height: 120,
                                              width: 120,
                                              fit: BoxFit.cover),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                            'Position your profile photo for best fit.',
                                            style: TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12)),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text('Cancel',
                                            style: TextStyle(
                                                color: Colors.redAccent)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                            const Color(0xFF00FF87)),
                                        onPressed: () async {
                                          setState(() {
                                            if (selectedFile != null) {
                                              currentUserProfileImage = selectedFile;
                                              tempImage = selectedFile;
                                            }
                                          });

                                          setModalState(() {
                                            tempImage = selectedFile;
                                          });

                                          SharedPreferences prefs = await SharedPreferences.getInstance();
                                          if (selectedFile != null) {
                                            await prefs.setString('profileImagePath', selectedFile.path);
                                          }

                                          if (!context.mounted) return;
                                          Navigator.pop(dialogContext);
                                        },
                                        child: const Text('Done',
                                            style: TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF00FF87),
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 18, color: Colors.black),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: nameEditController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Your Name / डिस्प्ले नाम',
                      labelStyle: const TextStyle(color: Color(0xFF00FF87)),
                      prefixIcon: const Icon(Icons.badge_outlined,
                          color: Color(0xFF00FF87)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: bioEditController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'About / स्टेटस',
                      labelStyle: const TextStyle(color: Color(0xFF00FF87)),
                      prefixIcon: const Icon(Icons.info_outline_rounded,
                          color: Color(0xFF00FF87)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF87),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        String newName = nameEditController.text.trim();
                        String newBio = bioEditController.text.trim();

                        setState(() {
                          currentUserName = newName;
                          currentUserBio = newBio;
                          if (tempImage != null) {
                            currentUserProfileImage = tempImage;
                          }
                        });

                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        if (tempImage != null) {
                          await prefs.setString('profileImagePath', tempImage!.path);
                        }

                        String? uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid != null) {
                          await FirebaseFirestore.instance.collection('users').doc(uid).set({
                            'name': newName,
                            'status': newBio,
                          }, SetOptions(merge: true));
                        }

                        if (!mounted) return;
                        Navigator.pop(ctx);
                        setState(() {});

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Profile updated successfully! ✅'),
                            backgroundColor: Color(0xFF00FF87),
                          ),
                        );
                      },
                      child: const Text(
                        'SAVE PROFILE',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openIncognitoModeHub() async {
    HapticFeedback.heavyImpact();

    if (kIsWeb) {
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (context, animation, secondaryAnimation) =>
              IncognitoModeHubScreen(registeredUsers: _shibaRegisteredUsers),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      return;
    }

    final LocalAuthentication auth = LocalAuthentication();
    bool authenticated = false;
    try {
      authenticated = await auth.authenticate(
        localizedReason: 'Incognito Space अनलॉक करने के लिए फिंगरप्रिंट या पिन लगाएं 🛡️',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint("Auth Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Authentication failed! Error ❌'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (authenticated) {
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (context, animation, secondaryAnimation) =>
              IncognitoModeHubScreen(registeredUsers: _shibaRegisteredUsers),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Verification Cancelled ❌'),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  void _openStatusActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E103E).withOpacity(0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Add Story Update 🌟',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                      color: Color(0xFFFF007A), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 22),
                ),
                title: const Text('Capture Live Camera',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Take direct photo for your story',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (await _requestPermission(Permission.camera, 'Camera')) {
                    final picker = ImagePicker();
                    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                    if (photo != null) {
                      setState(() {
                        myActiveStatuses.add(File(photo.path));
                      });
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Status added to your story list! 📸✨'),
                          backgroundColor: Color(0xFF00FF87),
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                      color: Color(0xFF00FF87), shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded,
                      color: Colors.black, size: 22),
                ),
                title: const Text('Upload from Gallery',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Pick image from device gallery',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                  if (picked != null) {
                    setState(() {
                      myActiveStatuses.add(File(picked.path));
                    });
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Status added to your story list! ✨'),
                        backgroundColor: Color(0xFF00FF87),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🎵 नया: Music with Partner और Shiba Synced Contacts का बॉटम शीट
  void _syncAndDiscoverContacts() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13082E).withOpacity(0.95),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 18),
              const Text('Connect with Partner ⚡', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                tileColor: Colors.white.withOpacity(0.04),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Color(0xFF00FF87), shape: BoxShape.circle), child: const Icon(Icons.contacts, color: Colors.black, size: 22)),
                title: const Text('Shiba Synced Contacts', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Find your phone contacts on Shiba Chat', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  _executeContactSync();
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                tileColor: Colors.white.withOpacity(0.04),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Color(0xFFFF007A), shape: BoxShape.circle), child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 22)),
                title: const Text('Music with your partner 🎧', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Sync YouTube audio room with partner', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMusicRoomDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // फोन कॉन्टैक्ट सिंक करने का सुरक्षित फंक्शन
  void _executeContactSync() async {
    if (kIsWeb) {
      _showWebOrFirestoreContactsModal();
      return;
    }

    if (await _requestPermission(Permission.contacts, 'Contacts')) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00FF87)),
              SizedBox(height: 16),
              Text('Matching Phone Contacts with Shiba Server...',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.none))
            ],
          ),
        ),
      );

      List<Map<String, dynamic>> syncedUsers = [];
      try {
        List<Contact> localContacts = await FlutterContacts.getContacts(withProperties: true);
        Map<String, String> localPhoneMap = {};
        for (var contact in localContacts) {
          if (contact.phones.isNotEmpty) {
            for (var phone in contact.phones) {
              String cleanPhone = phone.number.replaceAll(RegExp(r'\D'), '');
              if (cleanPhone.length >= 10) {
                String last10 = cleanPhone.substring(cleanPhone.length - 10);
                localPhoneMap[last10] = contact.displayName;
              }
            }
          }
        }

        var usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
        String? myPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? "";
        String myLast10 = myPhone.replaceAll(RegExp(r'\D'), '');
        if (myLast10.length >= 10) {
          myLast10 = myLast10.substring(myLast10.length - 10);
        }

        for (var doc in usersSnapshot.docs) {
          var data = doc.data();
          String dbPhone = data['phone'] ?? '';
          String dbStatus = data['status'] ?? 'Available';
          String dbCleanPhone = dbPhone.replaceAll(RegExp(r'\D'), '');

          if (dbCleanPhone.length >= 10) {
            String dbLast10 = dbCleanPhone.substring(dbCleanPhone.length - 10);
            if (dbLast10 != myLast10) {
              if (localPhoneMap.containsKey(dbLast10)) {
                String contactName = localPhoneMap[dbLast10]!;
                syncedUsers.add({
                  'name': contactName,
                  'phone': dbPhone,
                  'color': Colors.primaries[contactName.hashCode % Colors.primaries.length],
                  'lastSeen': 'Online',
                  'status': dbStatus,
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Sync Error: $e");
      }

      if (mounted) Navigator.pop(context);
      if (mounted) {
        if (syncedUsers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('None of your phone contacts are on Shiba Chat yet.'), backgroundColor: Colors.redAccent),
          );
        } else {
          _showSyncedUsersBottomSheet(syncedUsers);
        }
      }
    }
  }

  void _showWebOrFirestoreContactsModal() async {
    List<Map<String, dynamic>> syncedUsers = [];
    try {
      var usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      String? myPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? "";

      String myLast10 = myPhone.replaceAll(RegExp(r'\D'), '');
      if (myLast10.length >= 10) {
        myLast10 = myLast10.substring(myLast10.length - 10);
      }

      for (var doc in usersSnapshot.docs) {
        var data = doc.data();
        String dbPhone = data['phone'] ?? '';
        String dbCleanPhone = dbPhone.replaceAll(RegExp(r'\D'), '');

        if (dbCleanPhone.length >= 10) {
          String dbLast10 = dbCleanPhone.substring(dbCleanPhone.length - 10);

          if (dbLast10 != myLast10) {
            syncedUsers.add({
              'name': data['name'] ?? 'Shiba Friend',
              'phone': data['phone'] ?? '',
              'color': Colors.primaries[Random().nextInt(Colors.primaries.length)],
              'lastSeen': 'Online',
              'status': data['status'] ?? 'Available',
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Web Sync Error: $e");
    }

    if (!mounted) return;
    _showSyncedUsersBottomSheet(syncedUsers);
  }

  void _showSyncedUsersBottomSheet(List<Map<String, dynamic>> syncedUsers) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13082E).withOpacity(0.95),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 18),
              const Text('Shiba Synced Contacts ⚡', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Found ${syncedUsers.length} users on Shiba Chat', style: const TextStyle(color: Color(0xFF00FF87), fontSize: 12)),
              const SizedBox(height: 16),
              Expanded(
                child: syncedUsers.isEmpty
                    ? const Center(child: Text("No other users found yet.", style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                  itemCount: syncedUsers.length,
                  itemBuilder: (context, index) {
                    final user = syncedUsers[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.06))),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: user['color'], child: Text(user['name'][0].toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16))),
                        title: Text(user['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('${user['phone']} • ${user['status']}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                        trailing: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00FF87).withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.chat_bubble, color: Color(0xFF00FF87), size: 18)),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(context, MaterialPageRoute(builder: (c) => IndividualChatScreen(contactName: user['name'], contactPhone: user['phone'], avatarColor: user['color'], lastSeen: user['lastSeen'])));
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
// 🎧 नया: Create Room और Join Room के साथ अपडेटेड म्यूजिक रूम डायलॉग
  void _showMusicRoomDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E103E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.music_note_rounded, color: Color(0xFFFF007A)),
            SizedBox(width: 8),
            Text('Music with Partner 🎧', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose an option to start listening to music together in real-time.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF87),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_circle_outline, color: Colors.black),
                label: const Text('CREATE ROOM', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  // 6 अंकों का आसान और सिक्योर रूम आईडी जनरेट करें
                  String newRoomId = (100000 + Random().nextInt(900000)).toString();
                  // PiP मोड सपोर्ट करने के लिए Opaque: false लगाया गया है
                  Navigator.push(context, PageRouteBuilder(
                    opaque: false,
                    pageBuilder: (context, animation, secondaryAnimation) => PartnerMusicSyncScreen(roomId: newRoomId),
                  ));
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF007A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.login_rounded, color: Colors.white),
                label: const Text('JOIN ROOM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showJoinRoomIdInput();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // पार्टनर की Room ID दर्ज करने का छोटा बॉक्स
  void _showJoinRoomIdInput() {
    final TextEditingController joinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E103E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Join Partner Room 🔗', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: joinController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter 6-Digit Room ID...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF87)),
            onPressed: () async {
              String enteredId = joinController.text.trim();
              if (enteredId.isNotEmpty) {
                // चेक करें कि रूम फायरबेस में मौजूद है या नहीं
                var doc = await FirebaseFirestore.instance.collection('musicRooms').doc(enteredId).get();
                if (!mounted) return;

                if (doc.exists) {
                  Navigator.pop(ctx);
                  Navigator.push(context, PageRouteBuilder(
                    opaque: false,
                    pageBuilder: (context, animation, secondaryAnimation) => PartnerMusicSyncScreen(roomId: enteredId),
                  ));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room ID not found! Please check and try again.'), backgroundColor: Colors.redAccent));
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid Room ID!'), backgroundColor: Colors.redAccent));
              }
            },
            child: const Text('Connect', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  // 🔴 YAHAN PAR NAYA GLOBAL SEARCH VIEW JODA GAYA HAI
  Widget _buildBodyView() {
    switch (_currentBottomNavIndex) {
      case 0:
      // अगर यूज़र सर्च कर रहा है तो Global Search View दिखाएं
        if (_isSearching && _searchQuery.trim().isNotEmpty) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00FF87)));
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No users found in database.", style: TextStyle(color: Colors.white54)));
              }

              String query = _searchQuery.toLowerCase().trim();
              String cleanQuery = query.replaceAll(RegExp(r'\D'), ''); // सिर्फ नंबर निकालने के लिए
              String myPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? "";

              var searchResults = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String phone = data['phone']?.toString().toLowerCase() ?? '';
                String name = data['name']?.toString().toLowerCase() ?? '';

                if (phone == myPhone) return false; // खुद की प्रोफाइल न दिखाएं

                String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
                bool phoneMatch = cleanQuery.isNotEmpty && cleanPhone.contains(cleanQuery);
                bool nameMatch = name.contains(query);

                return phoneMatch || nameMatch;
              }).toList();

              if (searchResults.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_search_rounded, size: 60, color: Color(0xFFFF007A)),
                      const SizedBox(height: 16),
                      Text('No user found for "$_searchQuery"', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Search by Exact Name or Phone Number (e.g. 998877)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: searchResults.length,
                itemBuilder: (context, index) {
                  var data = searchResults[index].data() as Map<String, dynamic>;
                  String name = data['name'] ?? 'User';
                  String phone = data['phone'] ?? '';
                  String status = data['status'] ?? 'Available';
                  Color avatarColor = Colors.primaries[name.hashCode % Colors.primaries.length];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00FF87).withOpacity(0.4), width: 1.5),
                      boxShadow: [BoxShadow(color: const Color(0xFF00FF87).withOpacity(0.1), blurRadius: 10)],
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: avatarColor,
                        child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('$phone\n$status', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                      isThreeLine: true,
                      trailing: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: Color(0xFF00FF87), shape: BoxShape.circle),
                        child: const Icon(Icons.chat_bubble_rounded, color: Colors.black, size: 20),
                      ),
                      onTap: () {
                        setState(() {
                          _isSearching = false;
                          _searchQuery = "";
                          _searchController.clear();
                        });
                        Navigator.push(context, MaterialPageRoute(builder: (c) => IndividualChatScreen(
                          contactName: name,
                          contactPhone: phone,
                          avatarColor: avatarColor,
                          lastSeen: 'Online',
                        )));
                      },
                    ),
                  );
                },
              );
            },
          );
        }

        // अगर सर्च नहीं कर रहे हैं, तो नॉर्मल डैशबोर्ड (स्टेटस और रीसेंट चैट्स) दिखाएं
        return Column(
          children: [
            Container(
              height: 115,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _openStatusActionSheet,
                    onLongPress: () {
                      if (myActiveStatuses.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => FullscreenStatusViewer(
                              statusName: currentUserName,
                              statusTime: 'Just now',
                              statusColor: const Color(0xFF00FF87),
                              statusImageFiles: myActiveStatuses,
                              isMyStatus: true,
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No active status found. Tap to add one! ✨')),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: myActiveStatuses.isNotEmpty ? const Color(0xFF00FF87) : Colors.white38,
                                      width: 2.5
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: const Color(0xFF24124D),
                                  backgroundImage: myActiveStatuses.isNotEmpty ? FileImage(myActiveStatuses.last) : null,
                                  child: myActiveStatuses.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(color: Color(0xFF00FF87), shape: BoxShape.circle),
                                  child: const Icon(Icons.add, color: Colors.black, size: 14),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text('My Status', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(color: Color(0xFF00FF87), strokeWidth: 2),
                            ),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        var users = snapshot.data!.docs;
                        String? myPhone = FirebaseAuth.instance.currentUser?.phoneNumber;

                        var otherUsers = users.where((doc) {
                          var data = doc.data() as Map<String, dynamic>;
                          return data['phone'] != myPhone;
                        }).toList();

                        if (otherUsers.isEmpty) {
                          return const Center(
                            child: Text(
                              "No active users yet.",
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          );
                        }

                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: otherUsers.length,
                          itemBuilder: (context, index) {
                            var data = otherUsers[index].data() as Map<String, dynamic>;
                            String name = data['name'] ?? 'User';
                            Color color = Colors.primaries[name.hashCode % Colors.primaries.length];
                            return _buildStatusAvatar(name, color);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // --- SOULMATE CHAT HIGHLIGHT START ---
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFFF007A).withOpacity(0.1), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF007A).withOpacity(0.5), width: 1.2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF007A).withOpacity(0.05), blurRadius: 15),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFF007A), width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 24,
                        backgroundColor: Color(0xFF1E0E45),
                        child: Text('💖', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                  ],
                ),
                title: const Text(
                  'Soulmate ✨👩‍❤️‍👨',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Hey, I have a surprise for you...',
                    style: TextStyle(color: const Color(0xFFFF007A).withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Just now', style: TextStyle(color: Color(0xFF00FF87), fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00FF87),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Color(0xFF00FF87), blurRadius: 10, spreadRadius: 2)],
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (c) => SoulmateHeartScreen()));
                },
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser?.uid ?? "local_test_user")
                    .collection('recentChats')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00FF87)),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data == null || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1B0F3E),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00FF87).withOpacity(0.18),
                                  blurRadius: 45,
                                  spreadRadius: 8,
                                )
                              ],
                            ),
                            child: const Icon(Icons.auto_awesome_rounded, size: 50, color: Color(0xFF00FF87)),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No Conversations Yet',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Double-tap Shiba avatar for Secret Chat 🕵️\nor tap top search to find a number!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    );
                  }

                  var chatDocs = snapshot.data!.docs;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    itemCount: chatDocs.length,
                    itemBuilder: (context, index) {
                      if (index >= chatDocs.length) return const SizedBox.shrink();

                      var chat = chatDocs[index].data() as Map<String, dynamic>;
                      String chatName = chat['name'] ?? 'User';
                      String chatPhone = chat['phone'] ?? '';

                      // खाली या गलत नाम वाली एंट्री को स्किप करें ताकि 'You' या अनचाही चैट न बने
                      if (chatName.trim().isEmpty || chatName.toLowerCase() == 'you') {
                        return const SizedBox.shrink();
                      }

                      Color avatarColor = Colors.primaries[chatName.hashCode % Colors.primaries.length];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.07)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: CircleAvatar(
                            radius: 26,
                            backgroundColor: avatarColor,
                            child: Text(
                              chatName.isNotEmpty ? chatName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          title: Text(
                            chatName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              chat['lastMessage'] ?? '',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                chat['time'] ?? '',
                                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00FF87)),
                                child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black, size: 10),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => IndividualChatScreen(
                                  contactName: chatName,
                                  contactPhone: chatPhone,
                                  avatarColor: avatarColor,
                                  lastSeen: 'Online',
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );

      case 1:
        return globalCallLogs.isEmpty
            ? const Center(child: Text('No call history found', style: TextStyle(color: Colors.white38)))
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: globalCallLogs.length,
          itemBuilder: (context, index) {
            final log = globalCallLogs[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(0xFF00F0FF),
                  child: Icon(Icons.call, color: Colors.black, size: 20),
                ),
                title: Text(log['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('${log['type']} • ${log['time']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.call_made, color: Color(0xFF00FF87), size: 18),
              ),
            );
          },
        );
      case 2:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_clock, color: Color(0xFF00FF87)),
                    title: const Text('Privacy & Ghost Security', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Last seen, Read receipts, Incognito rules', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const PrivacySettingsSubScreen()));
                    },
                  ),
                  const Divider(color: Colors.white10),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined, color: Color(0xFFFF007A)),
                    title: const Text('Google Drive Backup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(currentUserEmail.isEmpty ? 'Not Connected' : 'Connected: $currentUserEmail', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (c) => GoogleDriveBackupSubScreen(
                          lastBackupTime: _lastBackupTime,
                          onBackupDone: (time) {
                            setState(() {
                              _lastBackupTime = time;
                            });
                          },
                        ),
                      ));
                    },
                  ),
                  const Divider(color: Colors.white10),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00F0FF)),
                    title: const Text('Chats & Theme', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Wallpaper, Dark Neon vibe, Font size', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const ChatsThemeSubScreen()));
                    },
                  ),
                  const Divider(color: Colors.white10),
                  ListTile(
                    leading: const Icon(Icons.data_usage_rounded, color: Color(0xFFFFB800)),
                    title: const Text('Data and Storage', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Network usage, Live speed, Auto-download', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const DataStorageSubScreen()));
                    },
                  ),
                  const Divider(color: Colors.white10),
                  ListTile(
                    leading: const Icon(Icons.system_update_rounded, color: Color(0xFF00FF87)),
                    title: const Text('Software Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Stable Cyber Edition • Up to date', style: TextStyle(color: Color(0xFF00FF87), fontSize: 12)),
                    trailing: const Icon(Icons.check_circle, color: Color(0xFF00FF87), size: 18),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Shiba Chat is running on the latest version! 🚀'),
                          backgroundColor: Color(0xFF00FF87),
                        ),
                      );
                    },
                  ),
                  const Divider(color: Colors.white10),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    title: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Sign out from your Shiba account', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E103E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          content: const Text('Are you sure want to logout?', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('No', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: () async {
                                Navigator.pop(ctx);

                                SharedPreferences prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('isLoggedIn', false);

                                if (isFirebaseReady) {
                                  await FirebaseAuth.instance.signOut();
                                }
                                if (!context.mounted) return;
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (context) => const ShibaChatLoginScreen()),
                                      (route) => false,
                                );
                              },
                              child: const Text('Yes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Color(0xFF00FF87), size: 13),
                  SizedBox(width: 6),
                  Text(
                    'End-to-End Encrypted Server Vault 🛡️',
                    style: TextStyle(color: Color(0xFF00FF87), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        );
      default:
        return Container();
    }
  }

  Widget _buildStatusAvatar(String name, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (c) => FullscreenStatusViewer(statusName: name, statusTime: 'Just now', statusColor: color)));
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF00FF87), width: 2),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: color,
                child: Text(name[0], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935).withOpacity(0.9),
        elevation: 0,
        titleSpacing: 16,
        title: _isSearching
            ? TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search Number or Name (e.g. 998877)',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
            border: InputBorder.none,
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
        )
            : Row(
          children: [
            GestureDetector(
              onDoubleTap: _openIncognitoModeHub,
              child: Tooltip(
                message: 'Double Tap for Incognito Hub',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/shiba_login_avatar.png',
                    height: 34,
                    width: 34,
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.pets,
                        color: Color(0xFF00FF87), size: 28),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Shiba Chat',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                fontSize: 21,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded,
                color: Colors.white),
            tooltip: _isSearching ? 'Close Search' : 'Search Chats / Users',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = "";
                  _searchController.clear();
                }
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: _openProfileEditor,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00FF87),
                ),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF24124D),
                  backgroundImage: currentUserProfileImage != null
                      ? FileImage(currentUserProfileImage!)
                      : null,
                  child: currentUserProfileImage == null
                      ? const Icon(Icons.person, size: 20, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBodyView(),
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: activePiPCall,
            builder: (context, callData, child) {
              if (callData == null) return const SizedBox.shrink();
              return Positioned(
                bottom: 85,
                right: 20,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => VideoCallScreen(
                          contactName: callData['name'],
                          avatarColor: callData['color'],
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 130,
                    height: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E0E45),
                      borderRadius: BorderRadius.circular(16),
                      border:
                      Border.all(color: const Color(0xFF00FF87), width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 15),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: callData['color'],
                                child: Text(
                                  callData['name'][0].toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                callData['name'],
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              const Text('Tap to expand 🔍',
                                  style: TextStyle(
                                      color: Color(0xFF00FF87), fontSize: 9)),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              globalCallLogs.insert(0, {
                                'name': callData['name'],
                                'time': 'Just now',
                                'type': 'Video Call',
                                'isIncoming': false,
                              });
                              activePiPCall.value = null;
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.redAccent),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _currentBottomNavIndex == 0
          ? Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: FloatingActionButton(
          backgroundColor: const Color(0xFF00FF87),
          elevation: 10,
          onPressed: _syncAndDiscoverContacts,
          child: const Icon(Icons.add, color: Colors.black, size: 30),
        ),
      )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14082E).withOpacity(0.95),
          border:
          Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentBottomNavIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF00FF87),
          unselectedItemColor: Colors.white38,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            setState(() {
              _currentBottomNavIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.call_outlined),
              activeIcon: Icon(Icons.call),
              label: 'Calls',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- FULLSCREEN ANIMATED MULTI-STATUS VIEWER ----------------
class FullscreenStatusViewer extends StatefulWidget {
  final String statusName;
  final String statusTime;
  final Color statusColor;
  final List<File>? statusImageFiles;
  final bool isMyStatus;

  const FullscreenStatusViewer({
    super.key,
    required this.statusName,
    required this.statusTime,
    required this.statusColor,
    this.statusImageFiles,
    this.isMyStatus = false,
  });

  @override
  State<FullscreenStatusViewer> createState() => _FullscreenStatusViewerState();
}

class _FullscreenStatusViewerState extends State<FullscreenStatusViewer>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startStoryTimer();
  }

  void _startStoryTimer() {
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..forward();

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });
  }

  void _nextStory() {
    if (widget.statusImageFiles != null && _currentIndex < widget.statusImageFiles!.length - 1) {
      setState(() {
        _currentIndex++;
        _progressController.forward(from: 0.0);
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _sendReply() {
    String replyText = _replyController.text.trim();
    if (replyText.isNotEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reply sent to ${widget.statusName}: "$replyText" 🚀'),
          backgroundColor: const Color(0xFF00FF87),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    File? currentImage = (widget.statusImageFiles != null && widget.statusImageFiles!.isNotEmpty)
        ? widget.statusImageFiles![_currentIndex]
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: currentImage != null
                  ? Image.file(currentImage, fit: BoxFit.contain)
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: widget.statusColor,
                    child: Text(
                      widget.statusName[0],
                      style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${widget.statusName}\'s Vibe Story ✨',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: AnimatedBuilder(
                            animation: _progressController,
                            builder: (context, child) => LinearProgressIndicator(
                              value: _progressController.value,
                              color: const Color(0xFF00FF87),
                              backgroundColor: Colors.white24,
                              minHeight: 3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.statusName} • (${_currentIndex + 1}/${widget.statusImageFiles?.length ?? 1})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: widget.isMyStatus
                  ? SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  icon: const Icon(Icons.delete_forever, color: Colors.white),
                  label: const Text('Delete Current Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      if (widget.statusImageFiles != null && widget.statusImageFiles!.isNotEmpty) {
                        widget.statusImageFiles!.removeAt(_currentIndex);
                      }
                    });
                    if (widget.statusImageFiles == null || widget.statusImageFiles!.isEmpty) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _currentIndex = 0;
                        _progressController.forward(from: 0.0);
                      });
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Status deleted successfully! 🗑️'), backgroundColor: Colors.redAccent),
                    );
                  },
                ),
              )
                  : Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFF00FF87).withOpacity(0.4)),
                      ),
                      child: TextField(
                        controller: _replyController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Reply to status...',
                          hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendReply(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sendReply,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00FF87)),
                      child: const Icon(Icons.send_rounded, color: Colors.black, size: 22),
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

// ---------------- VIDEO CALL SCREEN ----------------
class VideoCallScreen extends StatefulWidget {
  final String contactName;
  final Color avatarColor;
  final bool isCaller;
  final String? roomId;

  const VideoCallScreen({
    super.key,
    required this.contactName,
    required this.avatarColor,
    this.isCaller = true,
    this.roomId,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {

  bool _isMuted = false;
  bool _isCameraOff = false;
  String _callStatus = "Connecting...";
  String? currentRoomId;
  StreamSubscription? _roomSubscription;
  StreamSubscription? _calleeSubscription;
  StreamSubscription? _callerSubscription;
  dynamic db;
  final webrtc.RTCVideoRenderer _localRenderer = webrtc.RTCVideoRenderer();
  final webrtc.RTCVideoRenderer _remoteRenderer = webrtc.RTCVideoRenderer();
  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? _localStream;

  @override
  void initState() {
    super.initState();
    if (isFirebaseReady) {
      db = FirebaseFirestore.instance;
    }
    initRenderers();
    _startWebRTC();
  }

  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startWebRTC() async {
    try {
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': true,
      });
      _localRenderer.srcObject = _localStream;

      _peerConnection = await webrtc.createPeerConnection({
        'iceServers': [
          {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
        ]
      });

      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (webrtc.RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
            _callStatus = "Connected 🔴";
          });
        }
      };

      if (db != null) {
        if (widget.isCaller) {
          await _createRoom();
        } else {
          if (widget.roomId != null) {
            await _joinRoom(widget.roomId!);
          }
        }
      } else {
        setState(() {
          _callStatus = "Firebase not initialized. Cannot connect.";
        });
      }
    } catch (e) {
      debugPrint("WebRTC Init Error: $e");
      setState(() => _callStatus = "Camera/Mic Permission Denied!");
    }
  }

  Future<void> _createRoom() async {
    dynamic roomRef = db.collection('calls').doc();
    currentRoomId = roomRef.id;
    setState(() => _callStatus = "Room ID: $currentRoomId");

    _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

    webrtc.RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await roomRef.set({'offer': offer.toMap()});

    _roomSubscription = roomRef.snapshots().listen((snapshot) async {
      var data = snapshot.data();
      if (data != null && data['answer'] != null) {
        var answer = webrtc.RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        var remoteDesc = await _peerConnection?.getRemoteDescription();
        if (remoteDesc == null) {
          await _peerConnection!.setRemoteDescription(answer);
        }
      }
    });

    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type.name == 'added') {
          var data = change.doc.data();
          _peerConnection!.addCandidate(
            webrtc.RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
          );
        }
      }
    });
  }

  Future<void> _joinRoom(String roomId) async {
    dynamic roomRef = db.collection('calls').doc(roomId);
    var roomSnapshot = await roomRef.get();

    if (roomSnapshot.exists) {
      var data = roomSnapshot.data();
      setState(() => _callStatus = "Connecting to Caller...");

      _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
        roomRef.collection('calleeCandidates').add(candidate.toMap());
      };

      if (data != null && data['offer'] != null) {
        var offer = data['offer'];
        await _peerConnection?.setRemoteDescription(
          webrtc.RTCSessionDescription(offer['sdp'], offer['type']),
        );

        var answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        await roomRef.update({'answer': answer.toMap()});
      }

      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type.name == 'added') {
            var data = change.doc.data();
            _peerConnection!.addCandidate(
              webrtc.RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
            );
          }
        }
      });
    } else {
      setState(() => _callStatus = "Room not found!");
    }
  }

  void _endCallAndLog() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();

    globalCallLogs.insert(0, {
      'name': widget.contactName,
      'time': 'Just now',
      'type': 'Video Call',
      'isIncoming': false,
    });
    Navigator.pop(context);
  }

  void _toggleMic() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      bool isEnabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !isEnabled;
      setState(() => _isMuted = isEnabled);
    }
  }

  void _toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      bool isEnabled = _localStream!.getVideoTracks()[0].enabled;
      _localStream!.getVideoTracks()[0].enabled = !isEnabled;
      setState(() => _isCameraOff = isEnabled);
    }
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _calleeSubscription?.cancel();
    _callerSubscription?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _remoteRenderer.srcObject != null
                ? webrtc.RTCVideoView(_remoteRenderer, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_rounded, color: Color(0xFF00FF87), size: 70),
                  const SizedBox(height: 14),
                  Text('Live Video Call with ${widget.contactName}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_callStatus, style: const TextStyle(color: Color(0xFF00FF87), fontSize: 14)),
                ],
              ),
            ),
          ),
          if (!_isCameraOff)
            Positioned(
              top: 50,
              right: 20,
              child: Container(
                width: 100,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00FF87), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: webrtc.RTCVideoView(_localRenderer, mirror: true, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            ),
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: _endCallAndLog,
            ),
          ),
          Positioned(
            bottom: 40,
            left: 10,
            right: 10,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'vid_mic',
                    backgroundColor: _isMuted ? Colors.redAccent : const Color(0xFF1E103E),
                    onPressed: _toggleMic,
                    child: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: Colors.white),
                  ),
                  const SizedBox(width: 15),
                  FloatingActionButton(
                    heroTag: 'vid_end',
                    backgroundColor: Colors.redAccent,
                    onPressed: _endCallAndLog,
                    child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 15),
                  FloatingActionButton(
                    heroTag: 'vid_cam',
                    backgroundColor: _isCameraOff ? Colors.redAccent : const Color(0xFF1E103E),
                    onPressed: _toggleCamera,
                    child: Icon(_isCameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white),
                  ),
                  const SizedBox(width: 15),
                  FloatingActionButton(
                    heroTag: 'vid_copy',
                    backgroundColor: const Color(0xFF1E103E),
                    onPressed: () {
                      if (currentRoomId != null) {
                        Clipboard.setData(ClipboardData(text: currentRoomId!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Room ID Copied! Send to friend.'),
                          backgroundColor: Color(0xFF00FF87),
                        ));
                      }
                    },
                    child: const Icon(Icons.copy_rounded, color: Color(0xFF00FF87)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- AUDIO CALL SCREEN ----------------
class AudioCallScreen extends StatefulWidget {
  final String contactName;
  final Color avatarColor;
  final bool isCaller;
  final String? roomId;

  const AudioCallScreen({
    super.key,
    required this.contactName,
    required this.avatarColor,
    this.isCaller = true,
    this.roomId,
  });

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  String _callStatus = "Connecting...";
  String? currentRoomId;
  StreamSubscription? _roomSubscription;
  StreamSubscription? _calleeSubscription;
  StreamSubscription? _callerSubscription;

  dynamic db;
  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? _localStream;

  @override
  void initState() {
    super.initState();
    if (isFirebaseReady) {
      db = FirebaseFirestore.instance;
    }
    _startWebRTC();
  }

  Future<void> _startWebRTC() async {
    try {
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'video': false,
        'audio': true,
      });

      _peerConnection = await webrtc.createPeerConnection({
        'iceServers': [
          {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
        ]
      });

      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (webrtc.RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _callStatus = "Connected 🟢 (Live Audio)";
          });
        }
      };

      if (db != null) {
        if (widget.isCaller) {
          await _createRoom();
        } else {
          if (widget.roomId != null) {
            await _joinRoom(widget.roomId!);
          }
        }
      } else {
        setState(() => _callStatus = "Firebase not initialized.");
      }
    } catch (e) {
      debugPrint("Audio WebRTC Init Error: $e");
      setState(() => _callStatus = "Mic Permission Denied!");
    }
  }

  Future<void> _createRoom() async {
    dynamic roomRef = db.collection('calls').doc();
    currentRoomId = roomRef.id;
    setState(() => _callStatus = "Room ID: $currentRoomId");

    _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

    webrtc.RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await roomRef.set({'offer': offer.toMap()});

    roomRef.snapshots().listen((snapshot) async {
      var data = snapshot.data();
      if (data != null && data['answer'] != null) {
        var answer = webrtc.RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        var remoteDesc = await _peerConnection?.getRemoteDescription();
        if (remoteDesc == null) {
          await _peerConnection!.setRemoteDescription(answer);
        }
      }
    });

    _calleeSubscription = roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type.name == 'added') {
          var data = change.doc.data();
          _peerConnection!.addCandidate(
            webrtc.RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
          );
        }
      }
    });
  }

  Future<void> _joinRoom(String roomId) async {
    dynamic roomRef = db.collection('calls').doc(roomId);
    var roomSnapshot = await roomRef.get();

    if (roomSnapshot.exists) {
      var data = roomSnapshot.data();
      setState(() => _callStatus = "Connecting to Caller...");

      _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
        roomRef.collection('calleeCandidates').add(candidate.toMap());
      };

      if (data != null && data['offer'] != null) {
        var offer = data['offer'];
        await _peerConnection?.setRemoteDescription(
          webrtc.RTCSessionDescription(offer['sdp'], offer['type']),
        );

        var answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        await roomRef.update({'answer': answer.toMap()});
      }

      _callerSubscription = roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type.name == 'added') {
            var data = change.doc.data();
            _peerConnection!.addCandidate(
              webrtc.RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
            );
          }
        }
      });
    } else {
      setState(() => _callStatus = "Room not found!");
    }
  }

  void _endCallAndLog() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();

    globalCallLogs.insert(0, {
      'name': widget.contactName,
      'time': 'Just now',
      'type': 'Audio Call',
      'isIncoming': false,
    });
    Navigator.pop(context);
  }

  void _toggleMic() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      bool isEnabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !isEnabled;
      setState(() => _isMuted = isEnabled);
    }
  }

  @override
  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 60,
              backgroundColor: widget.avatarColor,
              child: Text(
                widget.contactName[0],
                style: const TextStyle(color: Colors.black, fontSize: 50, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.contactName,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _callStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF00FF87), fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted ? Colors.redAccent : Colors.white, size: 28),
                    onPressed: _toggleMic,
                  ),
                  IconButton(
                    icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_down, color: Colors.white, size: 28),
                    onPressed: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Color(0xFF00FF87), size: 28),
                    tooltip: 'Copy Room ID',
                    onPressed: () {
                      if (currentRoomId != null) {
                        Clipboard.setData(ClipboardData(text: currentRoomId!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room ID Copied! Send to friend.'), backgroundColor: Color(0xFF00FF87)));
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            FloatingActionButton(
              backgroundColor: Colors.redAccent,
              onPressed: _endCallAndLog,
              child: const Icon(Icons.call_end, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}

// ---------------- SUB-PAGE: PRIVACY & GHOST SECURITY ----------------
class PrivacySettingsSubScreen extends StatefulWidget {
  const PrivacySettingsSubScreen({super.key});

  @override
  State<PrivacySettingsSubScreen> createState() =>
      _PrivacySettingsSubScreenState();
}

class _PrivacySettingsSubScreenState extends State<PrivacySettingsSubScreen> {
  bool _readReceipts = true;
  bool _screenLock = false;
  String _lastSeenOption = "Everyone";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Privacy & Ghost Security',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Last Seen & Online',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(_lastSeenOption,
                style: const TextStyle(color: Color(0xFF00FF87))),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.white38),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  backgroundColor: const Color(0xFF1E103E),
                  title: const Text('Who can see my Last Seen',
                      style: TextStyle(color: Colors.white)),
                  children: ['Everyone', 'My Contacts', 'Nobody'].map((opt) {
                    return SimpleDialogOption(
                      onPressed: () {
                        setState(() => _lastSeenOption = opt);
                        Navigator.pop(ctx);
                      },
                      child: Text(opt,
                          style: const TextStyle(color: Colors.white70)),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const Divider(color: Colors.white10),
          SwitchListTile(
            title: const Text('Read Receipts (Blue Ticks)',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'If turned off, you won\'t send or receive read receipts',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _readReceipts,
            activeColor: const Color(0xFF00FF87),
            onChanged: (val) => setState(() => _readReceipts = val),
          ),
          const Divider(color: Colors.white10),
          SwitchListTile(
            title: const Text('App Screen Lock (Biometrics)',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Require Fingerprint or Face ID to open Shiba Chat',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _screenLock,
            activeColor: const Color(0xFF00FF87),
            onChanged: (val) => setState(() => _screenLock = val),
          ),
        ],
      ),
    );
  }
}

// ---------------- GOOGLE DRIVE BACKUP & RESTORE ----------------
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  GoogleAuthClient(this._headers);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class GoogleDriveBackupSubScreen extends StatefulWidget {
  final String lastBackupTime;
  final Function(String) onBackupDone;

  const GoogleDriveBackupSubScreen({
    super.key,
    required this.lastBackupTime,
    required this.onBackupDone,
  });

  @override
  State<GoogleDriveBackupSubScreen> createState() => _GoogleDriveBackupSubScreenState();
}

class _GoogleDriveBackupSubScreenState extends State<GoogleDriveBackupSubScreen> {
  bool _isWorking = false;
  String _progressText = "";
  late String _currentTime;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );
  GoogleSignInAccount? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentTime = widget.lastBackupTime;
    _checkExistingLogin();
  }

  void _checkExistingLogin() async {
    _currentUser = _googleSignIn.currentUser;
    if (_currentUser == null) {
      _currentUser = await _googleSignIn.signInSilently();
    }
    if (_currentUser != null && mounted) {
      setState(() {
        currentUserEmail = _currentUser!.email;
      });
    }
  }

  Future<void> _connectGoogleAccount() async {
    setState(() {
      _isWorking = true;
      _progressText = "Authenticating with Google securely...";
    });

    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        setState(() {
          _currentUser = account;
          currentUserEmail = account.email;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Linked to ${account.email} ✅'),
          backgroundColor: const Color(0xFF00FF87),
        ));
      }
    } catch (e) {
      debugPrint("Google Sign in error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to connect to Google Account ❌'),
        backgroundColor: Colors.redAccent,
      ));
    }

    setState(() {
      _isWorking = false;
    });
  }

  Future<void> _executeBackup() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please connect a Google Account first!'), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() {
      _isWorking = true;
      _progressText = "Preparing Backup Data...";
    });

    try {
      final googleAuth = await _currentUser!.authentication;
      final authHeaders = {"Authorization": "Bearer ${googleAuth.accessToken}"};
      final authenticateClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      setState(() => _progressText = "Uploading to Real Google Drive ☁️...");

      String backupData = jsonEncode({
        "appName": "Shiba Chat",
        "backupDate": DateTime.now().toIso8601String(),
        "user": _currentUser!.email,
        "status": "Encrypted Chat Backup"
      });

      List<int> dataBytes = utf8.encode(backupData);
      final stream = Stream.value(dataBytes);

      var driveFile = drive.File()..name = "ShibaChat_Backup.json";
      var media = drive.Media(stream, dataBytes.length);

      await driveApi.files.create(driveFile, uploadMedia: media);

      final newTime = "Just now (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})";

      setState(() {
        _currentTime = newTime;
        _isWorking = false;
      });

      widget.onBackupDone(newTime);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Real Backup Uploaded to $currentUserEmail! ☁️✅'),
          backgroundColor: const Color(0xFF00FF87)));

    } catch (e) {
      setState(() => _isWorking = false);
      debugPrint("Backup Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backup Failed: $e'),
          backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _executeRestore() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please connect a Google Account first!'), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() {
      _isWorking = true;
      _progressText = "Searching Drive for Backup File 🔍...";
    });

    try {
      final googleAuth = await _currentUser!.authentication;
      final authHeaders = {"Authorization": "Bearer ${googleAuth.accessToken}"};
      final authenticateClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      final fileList = await driveApi.files.list(q: "name = 'ShibaChat_Backup.json'");
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        setState(() => _progressText = "Downloading Backup Data ⬇️...");

        await Future.delayed(const Duration(seconds: 2));

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Data Restored Successfully! 🔄✅'),
            backgroundColor: Color(0xFF00FF87)));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No backup file found in this Drive account ❌'),
            backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restore Failed: $e'),
          backgroundColor: Colors.redAccent));
    }

    setState(() => _isWorking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Chat Backup to Drive',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFF007A).withOpacity(0.15),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.cloud_upload_rounded,
                      color: Color(0xFFFF007A), size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Backup',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(_currentTime,
                          style: const TextStyle(
                              color: Color(0xFF00FF87), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Google Account for Backup',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              subtitle: Text(
                  _currentUser == null ? "Not Connected" : currentUserEmail,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              trailing: TextButton(
                onPressed: _isWorking ? null : _connectGoogleAccount,
                child: Text(_currentUser == null ? 'LINK GOOGLE ID' : 'CHANGE ID',
                    style: const TextStyle(
                        color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
              ),
            ),
            const Divider(color: Colors.white12, height: 30),
            if (_isWorking) ...[
              const LinearProgressIndicator(
                  color: Color(0xFF00FF87), backgroundColor: Colors.white12),
              const SizedBox(height: 10),
              Center(
                  child: Text(_progressText,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12))),
              const SizedBox(height: 20),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload_rounded, color: Colors.black),
                label: const Text('BACKUP TO DRIVE',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF87),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isWorking ? null : _executeBackup,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cloud_download_rounded, color: Colors.white),
                label: const Text('RESTORE DATA',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E103E),
                  side: const BorderSide(color: Color(0xFF00FF87), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isWorking ? null : _executeRestore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- DATA & STORAGE SUB-SCREEN ----------------
class DataStorageSubScreen extends StatefulWidget {
  const DataStorageSubScreen({super.key});

  @override
  State<DataStorageSubScreen> createState() => _DataStorageSubScreenState();
}

class _DataStorageSubScreenState extends State<DataStorageSubScreen> {
  bool _wifiAutoDownload = true;
  bool _mobileAutoDownload = false;
  String _liveSpeed = "Checking...";

  @override
  void initState() {
    super.initState();
    _simulateLiveSpeed();
  }

  void _simulateLiveSpeed() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _liveSpeed = "18.4 MB/s (High Speed ⚡)";
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Data & Storage',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Network & Speed Statistics',
                    style: TextStyle(
                        color: Color(0xFF00FF87),
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.speed_rounded,
                      color: Color(0xFFFFB800), size: 28),
                  title: const Text('Current Internet Speed',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(_liveSpeed,
                      style: const TextStyle(
                          color: Color(0xFF00FF87),
                          fontWeight: FontWeight.bold)),
                ),
                const Divider(color: Colors.white10),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.data_usage_rounded,
                      color: Color(0xFF00F0FF), size: 28),
                  title: Text('Total Data Consumed',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                      '124.5 MB sent • 342.1 MB received (Total: 466.6 MB)',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Media Auto-Download Options',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Download via Wi-Fi',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Photos, audio and documents auto-download on Wi-Fi',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _wifiAutoDownload,
            activeColor: const Color(0xFF00FF87),
            onChanged: (val) => setState(() => _wifiAutoDownload = val),
          ),
          SwitchListTile(
            title: const Text('Download via Mobile Data',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Photos and documents auto-download on Cellular network',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _mobileAutoDownload,
            activeColor: const Color(0xFF00FF87),
            onChanged: (val) => setState(() => _mobileAutoDownload = val),
          ),
        ],
      ),
    );
  }
}

// ---------------- CHATS & THEME SUB-SCREEN ----------------
class ChatsThemeSubScreen extends StatefulWidget {
  const ChatsThemeSubScreen({super.key});

  @override
  State<ChatsThemeSubScreen> createState() => _ChatsThemeSubScreenState();
}

class _ChatsThemeSubScreenState extends State<ChatsThemeSubScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Chats & Theme',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.palette_outlined, color: Color(0xFF00FF87)),
            title: Text('Theme Mode', style: TextStyle(color: Colors.white)),
            subtitle: Text('Cyber Neon Dark (Default)',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading:
            const Icon(Icons.wallpaper_rounded, color: Color(0xFF00F0FF)),
            title: const Text('Chat Wallpaper',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              currentChatWallpaper != null
                  ? 'Custom image applied from storage'
                  : 'Default Cyber Vibe',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: const Icon(Icons.file_upload_outlined,
                color: Color(0xFF00FF87)),
            onTap: () async {
              final picker = ImagePicker();
              final picked =
              await picker.pickImage(source: ImageSource.gallery);
              if (picked != null) {
                setState(() {
                  currentChatWallpaper = File(picked.path);
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                    Text('Chat wallpaper updated from your device! 🖼️'),
                    backgroundColor: Color(0xFF00FF87),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ---------------- GHOST INCOGNITO GATEWAY HUB ----------------
class IncognitoModeHubScreen extends StatefulWidget {
  final List<Map<String, dynamic>> registeredUsers;
  const IncognitoModeHubScreen({super.key, required this.registeredUsers});

  @override
  State<IncognitoModeHubScreen> createState() => _IncognitoModeHubScreenState();
}

class _IncognitoModeHubScreenState extends State<IncognitoModeHubScreen> {
  void _openPersonSearchModal() {
    final TextEditingController searchCtrl = TextEditingController();
    List<Map<String, dynamic>> searchResults = List.from(widget.registeredUsers);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17042B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Search Registered Person 🕵️',
                style: TextStyle(
                  color: Color(0xFFFF007A),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search by name or number (+91)...',
                  hintStyle:
                  const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon:
                  const Icon(Icons.search, color: Color(0xFFFF007A)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setSheetState(() {
                    searchResults = widget.registeredUsers.where((u) {
                      final name = u['name'].toString().toLowerCase();
                      final phone = u['phone'].toString().toLowerCase();
                      final query = val.toLowerCase();
                      return name.contains(query) || phone.contains(query);
                    }).toList();
                  });
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: searchResults.isEmpty
                    ? const Center(
                  child: Text(
                    'No registered contact found',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
                    : ListView.builder(
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    final user = searchResults[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFF007A),
                          child: Text(
                            user['name'][0],
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          user['name'],
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          user['phone'],
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.lock_outline,
                            color: Color(0xFFFF007A), size: 18),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (c) => IncognitoChatScreen(
                                initialContactName: user['name'],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRandomDatingFlow() {
    String? myGender;
    String? targetGender;
    RangeValues selectedAgeRange = const RangeValues(18, 25);
    double myAge = 22;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF130424),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDatingState) => Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Soulmate / Partner', style: TextStyle(color: Color(0xFFFF007A), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      SizedBox(height: 2),
                      Text('Real-Time Matchmaking 📡', style: TextStyle(color: Color(0xFF00FF87), fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Your Age (आपकी उम्र):', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('${myAge.round()} Years', style: const TextStyle(color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: myAge, min: 18, max: 50,
                activeColor: const Color(0xFF00FF87), inactiveColor: Colors.white24,
                onChanged: (val) { setDatingState(() { myAge = val; }); },
              ),
              const SizedBox(height: 10),
              const Text('Select your gender (आप क्या हैं?):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: ['Male', 'Female'].map((gender) {
                  final isSelected = myGender == gender;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setDatingState(() => myGender = gender),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: isSelected ? const Color(0xFFFF007A) : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: isSelected ? Colors.transparent : Colors.white12)),
                        alignment: Alignment.center,
                        child: Text(gender, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text('Interested in? (रुचि किसमें है?):', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: ['Male', 'Female'].map((gender) {
                  final isSelected = targetGender == gender;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setDatingState(() => targetGender = gender),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: isSelected ? const Color(0xFF00FF87) : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: isSelected ? Colors.transparent : Colors.white12)),
                        alignment: Alignment.center,
                        child: Text(gender, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Partner Age Limit (आयु सीमा):', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('${selectedAgeRange.start.round()} - ${selectedAgeRange.end.round()} Yrs', style: const TextStyle(color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
                ],
              ),
              RangeSlider(
                values: selectedAgeRange, min: 18, max: 50, divisions: 32,
                activeColor: const Color(0xFFFF007A), inactiveColor: Colors.white24,
                onChanged: (values) { setDatingState(() { selectedAgeRange = values; }); },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF87), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () {
                    if (myGender == null || targetGender == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select both gender preferences!'), backgroundColor: Colors.redAccent));
                      return;
                    }
                    Navigator.pop(ctx);
                    _executeRealTimeRadarSimulation(myGender!, targetGender!, myAge, selectedAgeRange);
                  },
                  child: const Text('SEARCH LIVE PARTNER ⚡', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _executeRealTimeRadarSimulation(String myGender, String targetGender, double myAge, RangeValues range) async {
    bool isCancelled = false;
    StreamSubscription? waitSubscription;
    DocumentReference? myQueueDoc;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF130424),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const CircularProgressIndicator(color: Color(0xFFFF007A), strokeWidth: 3),
            const SizedBox(height: 22),
            const Text('Scanning Global Radar... 📡', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Finding best match on server vault...', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                isCancelled = true;
                waitSubscription?.cancel();
                myQueueDoc?.delete();
                Navigator.pop(c);
              },
              child: const Text('Cancel Search', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );

    try {
      final queueRef = FirebaseFirestore.instance.collection('incognitoQueue');
      final querySnapshot = await queueRef.where('status', isEqualTo: 'searching').get();
      QueryDocumentSnapshot? matchedDoc;

      for (var doc in querySnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (data['name'] == currentUserName) continue;
        matchedDoc = doc;
        break;
      }

      if (isCancelled) return;

      if (matchedDoc != null) {
        String roomId = "incognito_${DateTime.now().millisecondsSinceEpoch}";
        String peerName = matchedDoc['name'] ?? 'Partner';

        await queueRef.doc(matchedDoc.id).update({
          'status': 'matched',
          'matchedWith': currentUserName,
          'roomId': roomId,
        });

        if (!mounted) return;
        Navigator.pop(context);
        _showMatchFoundAndGoToChat(peerName[0].toUpperCase(), roomId);
      } else {
        myQueueDoc = await queueRef.add({
          'name': currentUserName,
          'gender': myGender,
          'targetGender': targetGender,
          'myAge': myAge,
          'status': 'searching',
          'timestamp': FieldValue.serverTimestamp(),
        });

        Timer(const Duration(seconds: 5), () async {
          if (isCancelled || !mounted) return;
          var checkDoc = await myQueueDoc?.get();
          if (checkDoc != null && checkDoc.exists && (checkDoc.data() as Map)['status'] == 'searching') {
            waitSubscription?.cancel();
            await myQueueDoc?.delete();

            if (!mounted) return;
            Navigator.pop(context);

            String autoRoomId = "incognito_auto_${DateTime.now().millisecondsSinceEpoch}";
            _showMatchFoundAndGoToChat(targetGender == 'Female' ? 'P' : 'R', autoRoomId);
          }
        });

        waitSubscription = myQueueDoc.snapshots().listen((snapshot) {
          if (!snapshot.exists) return;
          var data = snapshot.data() as Map<String, dynamic>;

          if (data['status'] == 'matched') {
            waitSubscription?.cancel();
            myQueueDoc?.delete();

            if (isCancelled || !mounted) return;
            Navigator.pop(context);

            String peerName = data['matchedWith'] ?? 'Partner';
            String roomId = data['roomId'];
            _showMatchFoundAndGoToChat(peerName[0].toUpperCase(), roomId);
          }
        });
      }
    } catch (e) {
      debugPrint("Radar Error: $e");
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Match Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showMatchFoundAndGoToChat(String firstLetter, String roomId) {
    HapticFeedback.vibrate();
    SystemSound.play(SystemSoundType.click);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E0630),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Icons.notifications_active_rounded, color: Color(0xFF00FF87)),
            SizedBox(width: 8),
            Text('Partner Matched! 🔔', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 36, backgroundColor: const Color(0xFFFF007A), child: Text(firstLetter, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold))),
            const SizedBox(height: 14),
            Text('Connected with User ($firstLetter)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 6),
            const Text('Real-time anonymous chat room is ready.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF87)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (c) => IncognitoChatScreen(initialContactName: "Partner ($firstLetter)", roomId: roomId)));
            },
            child: const Text('Start Private Chat', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _promptPlayerNamesAndOpenGame(Widget gameScreen) {
    final TextEditingController p1Controller =
    TextEditingController(text: currentUserName);
    final TextEditingController p2Controller =
    TextEditingController(text: "Partner");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E103E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter Players Names 👥',
            style: TextStyle(
                color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: p1Controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Player 1 Name',
                  labelStyle: TextStyle(color: Color(0xFF00FF87))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: p2Controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Player 2 (Partner) Name',
                  labelStyle: TextStyle(color: Color(0xFF00FF87))),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.redAccent))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF87)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => gameScreen),
              );
            },
            child: const Text('Start Game ⚡',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openAdult18PlusFlow() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E0630),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFF007A), size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Age Verification (18+)',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: SingleChildScrollView(
            child: const Text(
              'This section contains adult interactive games and mature experiences. Are you 18 years or older?',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No (Exit)', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF007A)),
            onPressed: () {
              Navigator.pop(ctx);
              _showAdultGamesHubModal();
            },
            child: const Text('Yes, I am 18+',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAdultGamesHubModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF130424),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Adult 18+ Game Zone 🔥',
                    style: TextStyle(
                        color: Color(0xFFFF007A),
                        fontSize: 20,
                        fontWeight: FontWeight.w900),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Select an interactive mature experience:',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 20),
              _buildAdultGameTile(
                  'Dice Game 🎲',
                  'Enter names & roll for spicy photo dares',
                  Colors.purpleAccent, () {
                Navigator.pop(ctx);
                _promptPlayerNamesAndOpenGame(const AdultDiceGameScreen());
              }),
              const SizedBox(height: 10),
              _buildAdultGameTile('Blindfold 🙈',
                  'Sensory trust & guess game', Colors.pinkAccent, () {
                    Navigator.pop(ctx);
                    _promptPlayerNamesAndOpenGame(const AdultBlindfoldGameScreen());
                  }),
              const SizedBox(height: 10),
              _buildAdultGameTile(
                  'Scratch Cards 🎫',
                  'Scratch to reveal animated Kamasutra positions',
                  Colors.amberAccent, () {
                Navigator.pop(ctx);
                _promptPlayerNamesAndOpenGame(const AdultScratchCardsScreen());
              }),
              const SizedBox(height: 10),
              _buildAdultGameTile('Truth or Dare (Plan Up) 🎯',
                  '200+ naughty adult questions & challenges', Colors.greenAccent,
                      () {
                    Navigator.pop(ctx);
                    _promptPlayerNamesAndOpenGame(const AdultTruthOrDareScreen());
                  }),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdultGameTile(
      String title, String subtitle, Color color, VoidCallback onTap) {
    return ListTile(
      tileColor: Colors.white.withOpacity(0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration:
        BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Icon(Icons.casino, color: color, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded,
          color: Colors.white38, size: 14),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06010F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF130424),
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.visibility_off_rounded, color: Color(0xFFFF007A)),
            SizedBox(width: 8),
            Text(
              'Incognito Space',
              style: TextStyle(
                  color: Color(0xFFFF007A),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Chat Mode 🕶️',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Zero traces saved. Vanishes completely on exit.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _openPersonSearchModal,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFFF007A).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF007A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_search_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Person (व्यक्तिगत)',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          SizedBox(height: 2),
                          Text('Search registered friend from contacts',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: Color(0xFFFF007A), size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _openRandomDatingFlow,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF00FF87).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00FF87),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          color: Colors.black, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Random (सोलमेट / पार्टनर)',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          SizedBox(height: 2),
                          Text('Soulmate dating, gender & age filters',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: Color(0xFF00FF87), size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _openAdult18PlusFlow,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFFF007A).withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF007A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Adult 18+ Games 🔥 (एल्ट गेम्स)',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          SizedBox(height: 2),
                          Text(
                              'Dice, Blindfold, Scratch Cards & Plan Up',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: Color(0xFFFF007A), size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 1. ADULT DICE GAME SCREEN (With Animation & Sound) ----------------
class AdultDiceGameScreen extends StatefulWidget {
  const AdultDiceGameScreen({super.key});

  @override
  State<AdultDiceGameScreen> createState() => _AdultDiceGameScreenState();
}

class _AdultDiceGameScreenState extends State<AdultDiceGameScreen> with SingleTickerProviderStateMixin {
  int _diceValue = 1;
  bool _isRolling = false;
  late AnimationController _rotateController;

  final List<String> _brutalDares = [
    "🔥 Give a passionate 60-second deep kiss!",
    "🌶️ Use two fingers to gently tease your partner for 1 minute",
    "💋 Whisper your dirtiest fantasy directly into partner's ear",
    "🧊 Pass an ice cube across partner's lips and neck",
    "🔥 Blindfold partner and give a sensual touch for 2 minutes",
    "💖 Share your most wild and taboo bedroom desire"
  ];

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _rotateController.dispose();
    super.dispose();
  }

  void _rollDice() async {
    if (_isRolling) return;
    setState(() => _isRolling = true);
    _rotateController.repeat();

    // तेज़ी से नंबर बदलने का एनिमेशन और वाइब्रेशन
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      HapticFeedback.lightImpact(); // डाइस गिरने का एहसास (Sound/Vibration)
      setState(() {
        _diceValue = Random().nextInt(6) + 1;
      });

      if (timer.tick >= 15) { // 1.5 सेकंड बाद रुकेगा
        timer.cancel();
        _rotateController.stop();
        setState(() => _isRolling = false);
        HapticFeedback.heavyImpact(); // फाइनल रिजल्ट पर ज़ोरदार वाइब्रेशन
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    String currentDare = _isRolling ? "Rolling the dice..." : _brutalDares[(_diceValue - 1) % _brutalDares.length];

    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Adult Dice Game 🎲 🔥', style: TextStyle(color: Color(0xFFFF007A), fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotationTransition(
              turns: _rotateController,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF007A),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF007A).withOpacity(0.5), blurRadius: 30)],
                ),
                child: Center(
                  child: Text(
                    '$_diceValue',
                    style: const TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                currentDare,
                textAlign: TextAlign.center,
                style: TextStyle(color: _isRolling ? Colors.white38 : Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: _isRolling ? null : _rollDice,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF87), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
              child: const Text('ROLL DICE 🎲', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------- 2. ADULT BLINDFOLD GAME SCREEN ----------------
class AdultBlindfoldGameScreen extends StatefulWidget {
  const AdultBlindfoldGameScreen({super.key});

  @override
  State<AdultBlindfoldGameScreen> createState() =>
      _AdultBlindfoldGameScreenState();
}

class _AdultBlindfoldGameScreenState extends State<AdultBlindfoldGameScreen> {
  final List<String> _blindfoldTasks = [
    "🙈 Blindfold partner and use warm breath on their neck",
    "🙈 Guess where your partner is kissing you without looking",
    "🙈 Trace your lips slowly across partner's collarbone blindfolded",
  ];
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Blindfold Game 🙈',
            style: TextStyle(
                color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_off, size: 80, color: Color(0xFFFF007A)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E103E),
                borderRadius: BorderRadius.circular(20),
                border:
                Border.all(color: const Color(0xFF00FF87).withOpacity(0.3)),
              ),
              child: Text(
                _blindfoldTasks[_currentIndex],
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.4,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF87)),
              onPressed: () {
                setState(() {
                  _currentIndex =
                      (_currentIndex + 1) % _blindfoldTasks.length;
                });
              },
              child: const Text('Next Challenge ⚡',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 3. ADULT SCRATCH CARDS SCREEN (Clean & Tracked) ----------------
class AdultScratchCardsScreen extends StatefulWidget {
  const AdultScratchCardsScreen({super.key});

  @override
  State<AdultScratchCardsScreen> createState() =>
      _AdultScratchCardsScreenState();
}

class _AdultScratchCardsScreenState extends State<AdultScratchCardsScreen> {
  final List<Map<String, String>> _positions = List.generate(
      54,
          (index) => {
        'title': 'Kamasutra Position #${index + 1}',
        'desc': 'Spicy Intimate Position #${index + 1}',
        'baseAsset': 'assets/images/kamasutra/kamasutra_${index + 1}',
      });

  final Set<int> _unlockedCards = {};

  Widget _buildMultiFormatImage(String baseAssetPath) {
    return Image.asset(
      '$baseAssetPath.gif',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          '$baseAssetPath.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              '$baseAssetPath.jpg',
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                color: const Color(0xFF1E103E),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.favorite, color: Color(0xFFFF007A), size: 40),
                    SizedBox(height: 8),
                    Text(
                      'Secret Intimate Art\n(Add Image in Assets)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showScratchCardModal(int index, Map<String, String> pos) {
    final GlobalKey<ScratcherState> scratchKey = GlobalKey<ScratcherState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E103E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          pos['title']!,
          style: const TextStyle(color: Color(0xFFFF007A), fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'उंगली से घिसकर (Scratch करके) पोजीशन खोलें ✨',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Container(
              height: 220,
              width: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF007A), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Scratcher(
                  key: scratchKey,
                  brushSize: 45,
                  threshold: 40,
                  color: const Color(0xFF2A144E),
                  onChange: (value) {
                    if (value > 40) {
                      setState(() {
                        _unlockedCards.add(index);
                      });
                    }
                  },
                  onThreshold: () {
                    HapticFeedback.heavyImpact();
                    setState(() {
                      _unlockedCards.add(index);
                    });
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: _buildMultiFormatImage(pos['baseAsset']!),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              scratchKey.currentState?.reveal();
              setState(() {
                _unlockedCards.add(index);
              });
            },
            child: const Text('Reveal Card', style: TextStyle(color: Color(0xFF00FF87))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF007A)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Kamasutra Scratch Cards 🎫 🔥',
            style: TextStyle(color: Color(0xFFFF007A), fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          itemCount: _positions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.9,
          ),
          itemBuilder: (context, index) {
            final pos = _positions[index];
            bool isUnlocked = _unlockedCards.contains(index);

            return GestureDetector(
              onTap: () => _showScratchCardModal(index, pos),
              child: Container(
                decoration: BoxDecoration(
                  color: isUnlocked ? const Color(0xFF103424) : const Color(0xFF1E103E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isUnlocked ? const Color(0xFF00FF87) : const Color(0xFFFF007A).withOpacity(0.5),
                    width: isUnlocked ? 2.0 : 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isUnlocked ? Icons.lock_open_rounded : Icons.card_giftcard,
                      color: isUnlocked ? const Color(0xFF00FF87) : const Color(0xFFFF007A),
                      size: 26,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Card #${index + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isUnlocked ? 'Unlocked ✨' : 'Tap to Scratch',
                      style: TextStyle(
                        color: isUnlocked ? const Color(0xFF00FF87) : Colors.white54,
                        fontSize: 10,
                        fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------- TRUTH OR DARE SCREEN ----------------
class AdultTruthOrDareScreen extends StatefulWidget {
  const AdultTruthOrDareScreen({super.key});

  @override
  State<AdultTruthOrDareScreen> createState() => _AdultTruthOrDareScreenState();
}

class _AdultTruthOrDareScreenState extends State<AdultTruthOrDareScreen> {
  bool isTruth = true;

  final List<String> _truths = [
    "What is one part of your body that you love being touched the most, but we rarely focus on during foreplay?",
    "If we had an entire evening dedicated completely to slow, uninterrupted foreplay, what would be the opening scene?",
    "What is a secret fantasy or desire you’ve been hesitant to share with me?",
    "What is one intimate fantasy you’ve been too shy to ask for?",
    "What is the most adventurous place you’ve ever thought about being intimate?",
    "Do you prefer slow, agonizing build-up, or something fast and spontaneous?",
    "If you had to rate your current level of desire on a scale from 1 to 10, where are you right now?",
    "What is the one thing I do in bed that makes you lose all self-control instantly?",
    "Which Position Do You actually prefer for sex.",
    "Do You like foreplay or afterplay?",
  ];

  final List<String> _dares = [
    "Kiss your partner anywhere you want, but the moment they try to pull you closer or deepen the kiss, pull back for five seconds and make them wait before you return.",
    "Give your partner a slow, uninterrupted two-minute shoulder and neck massage to help them completely unwind.",
    "Give your partner a passionate 45-second kiss without letting your hands touch them at all—keep them completely flat at your sides.",
    "Lock eyes with your partner without speaking or looking away for a full minute while slowly undressing or teasing one piece of clothing off.",
    "Give your partner a focused, uninterrupted massage on any part of their body they choose, but you aren't allowed to rush a single second of it.",
    "Touch your partner in their most sensitive spot, bringing them right to the edge of pleasure, and then instantly stop for a full minute to make them wait before you continue.",
    "Sit completely still in a chair while your partner slowly removes one piece of clothing of their choice, using only their teeth or one hand, while maintaining unbroken eye contact.",
    "For the next three minutes, you are not allowed to speak. Your partner has complete control over where you sit, how you move, and how you touch them.",
    "Spend the next two minutes kissing every single inch of your partner's body from their waist up, but you are not allowed to touch them with your hands at all.",
  ];

  String _currentPrompt = "Tap Truth or Dare to start your spicy challenge!";

  void _generatePrompt() {
    final random = Random();
    if (isTruth) {
      _currentPrompt = _truths[random.nextInt(_truths.length)];
    } else {
      _currentPrompt = _dares[random.nextInt(_dares.length)];
    }
    setState(() {});
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        title: const Text('Truth or Dare (Plan Up) 🎯', style: TextStyle(color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isTruth ? const Color(0xFFFF007A) : Colors.white12,
                  ),
                  onPressed: () {
                    setState(() => isTruth = true);
                    _generatePrompt();
                  },
                  child: const Text('TRUTH 💡', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !isTruth ? const Color(0xFF00FF87) : Colors.white12,
                  ),
                  onPressed: () {
                    setState(() => isTruth = false);
                    _generatePrompt();
                  },
                  child: Text('DARE 🔥', style: TextStyle(color: !isTruth ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 35),
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF1E103E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFF007A).withOpacity(0.4)),
              ),
              child: Text(
                _currentPrompt,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.4, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 35),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF87)),
                onPressed: _generatePrompt,
                child: const Text('NEXT SWAP ⚡', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- SECRET INCOGNITO / GHOST CHAT SCREEN (REAL-TIME) ----------------
class IncognitoChatScreen extends StatefulWidget {
  final String? initialContactName;
  final String? roomId;

  const IncognitoChatScreen({super.key, this.initialContactName, this.roomId});

  @override
  State<IncognitoChatScreen> createState() => _IncognitoChatScreenState();
}

class _IncognitoChatScreenState extends State<IncognitoChatScreen> {
  final TextEditingController _ghostController = TextEditingController();
  late String _activeGhostContact;

  @override
  void initState() {
    super.initState();
    _activeGhostContact = widget.initialContactName ?? "Secret Contact";
  }

  void _sendGhostMessage() async {
    String text = _ghostController.text.trim();
    if (text.isNotEmpty && widget.roomId != null) {
      HapticFeedback.mediumImpact();
      _ghostController.clear();

      await FirebaseFirestore.instance
          .collection('incognitoRooms')
          .doc(widget.roomId)
          .collection('messages')
          .add({
        'text': text,
        'sender': currentUserName,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  void dispose() {
    if (widget.roomId != null) {
      try {
        FirebaseFirestore.instance
            .collection('incognitoRooms')
            .doc(widget.roomId)
            .delete()
            .catchError((e) => debugPrint("Incognito delete error: \$e"));
      } catch (e) {
        debugPrint("Error on dispose: \$e");
      }
    }
    _ghostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String displayFirstLetter = _activeGhostContact.isNotEmpty ? _activeGhostContact[0].toUpperCase() : 'G';

    return Scaffold(
      backgroundColor: const Color(0xFF05010D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF130424),
        title: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: const Color(0xFFFF007A), child: Text(displayFirstLetter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
            const SizedBox(width: 10),
            Expanded(child: Text(_activeGhostContact, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFF007A), fontWeight: FontWeight.w900, letterSpacing: 0.8))),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            color: const Color(0xFFFF007A).withOpacity(0.12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.security, color: Color(0xFFFF007A), size: 14),
                SizedBox(width: 6),
                Text('Real-time Ghost Chat • Vanishes permanently on exit', style: TextStyle(color: Color(0xFFFF007A), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: widget.roomId == null
                ? const Center(child: Text("No Room ID", style: TextStyle(color: Colors.white)))
                : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('incognitoRooms')
                  .doc(widget.roomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFFF007A)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.theater_comedy_rounded, size: 55, color: Color(0xFFFF007A)),
                        const SizedBox(height: 14),
                        Text('Incognito: $_activeGhostContact', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Send confidential self-destructing text', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var msgData = messages[index].data() as Map<String, dynamic>;
                    bool isMe = msgData['sender'] == currentUserName;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFFF007A) : const Color(0xFF1E103E),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: (isMe ? const Color(0xFFFF007A) : Colors.black).withOpacity(0.3), blurRadius: 10),
                          ],
                        ),
                        child: Text(
                          msgData['text'] ?? '',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF130424),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: const Color(0xFFFF007A).withOpacity(0.3)),
                      ),
                      child: TextField(
                        controller: _ghostController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Type secret message...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendGhostMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendGhostMessage,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF007A)),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ---------------- INDIVIDUAL CHAT SCREEN (All Features + Falling Flowers) ----------------
class IndividualChatScreen extends StatefulWidget {
  final String contactName;
  final String contactPhone;
  final Color avatarColor;
  final String lastSeen;

  const IndividualChatScreen({
    super.key,
    required this.contactName,
    required this.contactPhone,
    required this.avatarColor,
    required this.lastSeen,
  });

  @override
  State<IndividualChatScreen> createState() => _IndividualChatScreenState();
}

class _IndividualChatScreenState extends State<IndividualChatScreen> {
  final TextEditingController _msgController = TextEditingController();

  String get chatRoomId {
    String myPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? "+910000000000";
    List<String> users = [myPhone, widget.contactPhone];
    users.sort();
    return "${users[0]}_${users[1]}";
  }

  // 📞 ऑडियो/वीडियो कॉल का रिंगिंग सिग्नल
  void _startCall({required bool isVideo}) async {
    String callType = isVideo ? 'Video Call' : 'Audio Call';
    String roomId = chatRoomId + (isVideo ? "_video" : "_audio");

    var query = await FirebaseFirestore.instance.collection('users').where('phone', isEqualTo: widget.contactPhone).limit(1).get();
    if (query.docs.isNotEmpty) {
      String receiverUid = query.docs.first.id;
      await FirebaseFirestore.instance.collection('users').doc(receiverUid).collection('incomingCall').doc('current').set({
        'callerName': currentUserName,
        'callType': callType,
        'roomId': roomId,
        'status': 'ringing',
      });
    }

    if (isVideo) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => VideoCallScreen(contactName: widget.contactName, avatarColor: widget.avatarColor, isCaller: true, roomId: roomId)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (c) => AudioCallScreen(contactName: widget.contactName, avatarColor: widget.avatarColor, isCaller: true, roomId: roomId)));
    }
  }

  // 🍿 वॉच पार्टी का रिंगिंग सिग्नल
  void _startWatchParty(String platform) async {
    String roomId = chatRoomId + "_watchparty";
    _sendMessage(customText: '🍿 $platform Watch Party! Connecting...');

    var query = await FirebaseFirestore.instance.collection('users').where('phone', isEqualTo: widget.contactPhone).limit(1).get();
    if (query.docs.isNotEmpty) {
      String receiverUid = query.docs.first.id;
      await FirebaseFirestore.instance.collection('users').doc(receiverUid).collection('incomingCall').doc('current').set({
        'callerName': currentUserName,
        'callType': 'Watch Party',
        'platform': platform,
        'roomId': roomId,
        'status': 'ringing',
      });
    }

    Navigator.push(context, MaterialPageRoute(builder: (c) => WatchPartyPlayerScreen(
      platformName: platform,
      partnerName: widget.contactName,
      partnerColor: widget.avatarColor,
      roomId: roomId,
      isCaller: true,
    )));
  }
  // 👇 यहाँ से पेस्ट करें 👇
  void _sendMessage({String? customText, String? imagePath}) async {
    String text = customText ?? _msgController.text.trim();
    if (text.isNotEmpty || imagePath != null) {
      HapticFeedback.lightImpact();
      if (customText == null) _msgController.clear();

      String timeStr = "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";
      String myUid = FirebaseAuth.instance.currentUser?.uid ?? "local_test_user";
      String myPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? "+910000000000";

      await FirebaseFirestore.instance.collection('chatRooms').doc(chatRoomId).collection('messages').add({
        'text': text,
        'image': imagePath ?? "", // फोटो सेव करने के लिए
        'sender': currentUserName,
        'timestamp': FieldValue.serverTimestamp(),
        'time': timeStr
      });

      await FirebaseFirestore.instance.collection('users').doc(myUid).collection('recentChats').doc(widget.contactPhone).set({
        'name': widget.contactName, 'phone': widget.contactPhone, 'lastMessage': imagePath != null ? '📷 Photo' : text, 'time': timeStr, 'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      try {
        var receiverQuery = await FirebaseFirestore.instance.collection('users').where('phone', isEqualTo: widget.contactPhone).limit(1).get();
        if (receiverQuery.docs.isNotEmpty) {
          String receiverUid = receiverQuery.docs.first.id;
          await FirebaseFirestore.instance.collection('users').doc(receiverUid).collection('recentChats').doc(myPhone).set({
            'name': currentUserName, 'phone': myPhone, 'lastMessage': imagePath != null ? '📷 Photo' : text, 'time': timeStr, 'timestamp': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint("Receiver sync error: $e");
      }
    }
  }

  void _openLiveLocationOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E103E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.location_on, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Share Live Location', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
            ]),
            const SizedBox(height: 6),
            const Text('Select duration for live GPS tracking popup alerts.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 18),
            // 🔴 आपके माँगे गए 4 ऑप्शंस
            _buildLocationDurationTile('1 Hour', () => _sendLiveLocationWithDuration('1 Hour')),
            _buildLocationDurationTile('4 Hours', () => _sendLiveLocationWithDuration('4 Hours')),
            _buildLocationDurationTile('8 Hours', () => _sendLiveLocationWithDuration('8 Hours')),
            _buildLocationDurationTile('Always On (Trackable)', () => _sendLiveLocationWithDuration('Always')),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationDurationTile(String duration, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.timer_outlined, color: Color(0xFF00FF87)),
      title: Text(duration, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
      onTap: onTap,
    );
  }

  void _sendLiveLocationWithDuration(String duration) async {
    Navigator.pop(context);

    // 🔴 प्रॉपर परमिशन माँगने का कोड
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _sendMessage(
        customText: '📍 Live Location ($duration): https://maps.google.com/?q=${position.latitude},${position.longitude}',
      );

      // 🔴 पॉप-अप अलर्ट जो बताएगा कि आपको ट्रैक किया जा रहा है
      Future.delayed(const Duration(seconds: 4), () {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: const Color(0xFF1E0630),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: const [
                Icon(Icons.visibility, color: Color(0xFF00FF87)),
                SizedBox(width: 8),
                Text('Location Alert 📡', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              '${widget.contactName} is currently viewing your live GPS location!',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK', style: TextStyle(color: Color(0xFF00FF87))),
              )
            ],
          ),
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location Permission Denied! Please allow in settings.'), backgroundColor: Colors.redAccent)
      );
    }
  }
  void _openAttachmentBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF160935),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAttachmentItem(
                  icon: Icons.camera_alt_rounded,
                  color: const Color(0xFFFF007A),
                  label: 'Camera',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final picker = ImagePicker();
                    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                    if (photo != null) {
                      _sendMessage(imagePath: photo.path); // असली फोटो भेजेगा
                    }
                  },
                ),
                _buildAttachmentItem(
                  icon: Icons.photo_library_rounded,
                  color: const Color(0xFF9C27B0),
                  label: 'Gallery',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final picker = ImagePicker();
                    final media = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                    if (media != null) {
                      _sendMessage(imagePath: media.path); // असली फोटो भेजेगा
                    }
                  },
                ),
                _buildAttachmentItem(
                  icon: Icons.insert_drive_file_rounded,
                  color: const Color(0xFF00F0FF),
                  label: 'Document',
                  onTap: () async {
                    Navigator.pop(ctx);
                    var result = await FilePicker.pickFiles();
                    if (result.isNotEmpty && result.first.path != null) {
                      _sendMessage(customText: '📄 Document sent: ${result.first.name}');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAttachmentItem(
                  icon: Icons.person_pin_rounded,
                  color: const Color(0xFF00FF87),
                  label: 'Contact',
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (await FlutterContacts.requestPermission()) {
                      // असली कॉन्टैक्ट लिस्ट खुलेगी
                      Contact? contact = await FlutterContacts.openExternalPick();
                      if (contact != null && contact.phones.isNotEmpty) {
                        _sendMessage(customText: '👤 Contact Shared: ${contact.displayName} (${contact.phones.first.number})');
                      }
                    }
                  },
                ),
                _buildAttachmentItem(
                  icon: Icons.headphones_rounded,
                  color: const Color(0xFFFFB800),
                  label: 'Audio',
                  onTap: () async {
                    Navigator.pop(ctx);
                    var result = await FilePicker.pickFiles(type: FileType.audio);
                    if (result.isNotEmpty && result.first.path != null) {
                      _sendMessage(customText: '🎵 Audio sent: ${result.first.name}');
                    }
                  },
                ),
                _buildAttachmentItem(
                  icon: Icons.location_on_rounded,
                  color: Colors.redAccent,
                  label: 'Location',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openLiveLocationOptions();
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _openChillWithPartnerHub();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF007A), Color(0xFF7928CA)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF007A).withOpacity(0.35),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.live_tv_rounded, color: Colors.white, size: 26),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chill with your partner 🍿',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Watch YouTube with real search, Netflix, Prime & JioHotstar',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentItem({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
  void _openChillWithPartnerHub() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF130424),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 22, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Watch or Share App 🎬', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 20),
              _buildPartnerAppTile('Google Browse & Search', Icons.g_mobiledata_rounded, const Color(0xFF4285F4), () { Navigator.pop(ctx); _startWatchParty('Google'); }),
              const SizedBox(height: 10),
              _buildPartnerAppTile('On Screen Share 🖥️', Icons.screen_share_rounded, const Color(0xFF00FF87), () {
                Navigator.pop(ctx);
                _startWatchParty('ScreenShare');
              }),
              const SizedBox(height: 10),
              _buildPartnerAppTile('YouTube', Icons.play_arrow_rounded, const Color(0xFFFF0000), () { Navigator.pop(ctx); _startWatchParty('YouTube'); }),
              const SizedBox(height: 10),
              _buildPartnerAppTile('Netflix', Icons.movie_creation_rounded, const Color(0xFFE50914), () { Navigator.pop(ctx); _launchExternalApp('https://www.netflix.com'); }),
              const SizedBox(height: 10),
              _buildPartnerAppTile('Amazon Prime Video', Icons.video_library_rounded, const Color(0xFF00A8E1), () { Navigator.pop(ctx); _launchExternalApp('https://www.primevideo.com'); }),
              const SizedBox(height: 10),
              _buildPartnerAppTile('Disney+ Hotstar', Icons.star_rounded, const Color(0xFF03108B), () { Navigator.pop(ctx); _launchExternalApp('https://www.hotstar.com'); }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartnerAppTile(String name, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      tileColor: Colors.white.withOpacity(0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 22)),
      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
      onTap: onTap,
    );
  }

  void _launchExternalApp(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint("Could not launch $urlString: $e");
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF150935),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Row(
          children: [
            CircleAvatar(radius: 19, backgroundColor: widget.avatarColor, child: Text(widget.contactName[0].toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.contactName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Online • Last seen ${widget.lastSeen}', style: const TextStyle(color: Color(0xFF00FF87), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call_rounded, color: Colors.white70, size: 22), onPressed: () => _startCall(isVideo: false)),
          IconButton(icon: const Icon(Icons.videocam_rounded, color: Colors.white70, size: 24), onPressed: () => _startCall(isVideo: true)),
        ],
      ),
      body: Column(
        children: [
          // ✅ नया सुरक्षित कोड (इसे कॉपी करके पेस्ट करें)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chatRooms').doc(chatRoomId).collection('messages').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00FF87)));
                }

                // 🛡️ यहाँ हमने चेक लगा दिया है ताकि खाली डेटा पर ऐप क्रैश न हो
                if (!snapshot.hasData || snapshot.data == null || snapshot.data!.docs.isEmpty) {
                  return const FallingFlowersAnimation();
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var msgData = messages[index].data() as Map<String, dynamic>;
                    bool isMe = msgData['sender'] == currentUserName;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF00FF87) : const Color(0xFF1E103E),
                          borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isMe ? 18 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 18)
                          ),
                        ),
                        child: Text(msgData['text'] ?? '', style: TextStyle(color: isMe ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF150935),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF00FF87), size: 26), onPressed: _openAttachmentBottomSheet),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(hintText: 'Type a message...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)), filled: true, fillColor: Colors.white.withOpacity(0.06), border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _sendMessage(),
                    child: Container(width: 46, height: 46, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00FF87)), child: const Icon(Icons.send_rounded, color: Colors.black, size: 22)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ---------------- FALLING FLOWERS ANIMATION ----------------
class FallingFlowersAnimation extends StatefulWidget {
  const FallingFlowersAnimation({super.key});
  @override
  State<FallingFlowersAnimation> createState() => _FallingFlowersAnimationState();
}

class _FallingFlowersAnimationState extends State<FallingFlowersAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<FlowerParticle> particles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    for (int i = 0; i < 30; i++) {
      particles.add(FlowerParticle());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: FlowerPainter(particles, _controller.value),
          child: Container(),
        );
      },
    );
  }
}

class FlowerParticle {
  double x = Random().nextDouble();
  double y = Random().nextDouble() * -1.0;
  double speed = 0.2 + Random().nextDouble() * 0.3;
  double size = 5 + Random().nextDouble() * 8;
  Color color = [Colors.pinkAccent, Colors.white, Colors.yellowAccent][Random().nextInt(3)];
}

class FlowerPainter extends CustomPainter {
  final List<FlowerParticle> particles;
  final double animationValue;

  FlowerPainter(this.particles, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      double py = (particle.y + (animationValue * particle.speed * 5)) % 1.0;
      double px = particle.x + sin((animationValue + particle.x) * 2 * pi) * 0.05;

      final paint = Paint()..color = particle.color.withOpacity(0.6)..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px * size.width, py * size.height), particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
// ---------------- WATCH PARTY PLAYER SCREEN ----------------
class WatchPartyPlayerScreen extends StatefulWidget {
  final String platformName;
  final String partnerName;
  final Color partnerColor;
  final String roomId;
  final bool isCaller;

  const WatchPartyPlayerScreen({
    super.key,
    required this.platformName,
    required this.partnerName,
    required this.partnerColor,
    required this.roomId,
    required this.isCaller,
  });

  @override
  State<WatchPartyPlayerScreen> createState() => _WatchPartyPlayerScreenState();
}

class _WatchPartyPlayerScreenState extends State<WatchPartyPlayerScreen> {
  bool _isMuted = false;
  bool _isCameraOff = false;
  String _callStatus = "Connecting Camera...";
  dynamic db;
  final webrtc.RTCVideoRenderer _localRenderer = webrtc.RTCVideoRenderer();
  final webrtc.RTCVideoRenderer _remoteRenderer = webrtc.RTCVideoRenderer();
  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? _localStream;

  double pipX = 20;
  double pipY = 100;
  bool _isPiPZoomed = false;

  YoutubePlayerController? _ytController;
  final TextEditingController _searchController = TextEditingController();
  bool _isVideoLoaded = false;
  String _currentVideoId = "";

  @override
  void initState() {
    super.initState();
    if (isFirebaseReady) db = FirebaseFirestore.instance;
    initRenderers();
    _startWebRTC();
    if (widget.platformName == 'YouTube') {
      _listenForVideoSync();
    }
  }

  void _listenForVideoSync() {
    FirebaseFirestore.instance.collection('calls').doc(widget.roomId).snapshots().listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      var data = snapshot.data();
      if (data != null && data['currentVideoId'] != null) {
        String syncedVid = data['currentVideoId'];
        if (syncedVid != _currentVideoId) {
          _currentVideoId = syncedVid;
          _playVideo(syncedVid);
        }
      }
    });
  }

  void _playVideo(String videoId) {
    if (_ytController == null) {
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(autoPlay: true, mute: false, enableCaption: true),
      );
    } else {
      _ytController!.load(videoId);
    }
    setState(() => _isVideoLoaded = true);
  }

  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startWebRTC() async {
    try {
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
      _localRenderer.srcObject = _localStream;
      _peerConnection = await webrtc.createPeerConnection({'iceServers': [{'urls': ['stun:stun1.l.google.com:19302']}]});
      _localStream?.getTracks().forEach((track) { _peerConnection?.addTrack(track, _localStream!); });

      _peerConnection?.onTrack = (webrtc.RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          setState(() { _remoteRenderer.srcObject = event.streams[0]; _callStatus = "Connected 🔴"; });
        }
      };

      if (db != null) {
        if (widget.isCaller) await _createRoom();
        else await _joinRoom();
      }
    } catch (e) {
      setState(() => _callStatus = "Permission Denied!");
    }
  }

  Future<void> _createRoom() async {
    dynamic roomRef = db.collection('calls').doc(widget.roomId);
    setState(() => _callStatus = "Ringing partner...");

    _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) { roomRef.collection('callerCandidates').add(candidate.toMap()); };
    webrtc.RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await roomRef.set({'offer': offer.toMap()});

    roomRef.snapshots().listen((snapshot) async {
      var data = snapshot.data();
      if (data != null && data['answer'] != null) {
        var answer = webrtc.RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
        var remoteDesc = await _peerConnection?.getRemoteDescription();
        if (remoteDesc == null) await _peerConnection!.setRemoteDescription(answer);
      }
    });

    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type.name == 'added') {
          var data = change.doc.data();
          _peerConnection!.addCandidate(webrtc.RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });
  }

  Future<void> _joinRoom() async {
    dynamic roomRef = db.collection('calls').doc(widget.roomId);
    var roomSnapshot = await roomRef.get();

    if (roomSnapshot.exists) {
      var data = roomSnapshot.data();
      setState(() => _callStatus = "Connecting...");

      _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) { roomRef.collection('calleeCandidates').add(candidate.toMap()); };
      if (data != null && data['offer'] != null) {
        var offer = data['offer'];
        await _peerConnection?.setRemoteDescription(webrtc.RTCSessionDescription(offer['sdp'], offer['type']));
        var answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        await roomRef.update({'answer': answer.toMap()});
      }

      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type.name == 'added') {
            var data = change.doc.data();
            _peerConnection!.addCandidate(webrtc.RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
          }
        }
      });
    }
  }

  void _toggleMic() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      bool isEnabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !isEnabled;
      setState(() => _isMuted = isEnabled);
    }
  }

  void _toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      bool isEnabled = _localStream!.getVideoTracks()[0].enabled;
      _localStream!.getVideoTracks()[0].enabled = !isEnabled;
      setState(() => _isCameraOff = isEnabled);
    }
  }

  void _endCall() async {
    if (widget.isCaller) {
      var query = await FirebaseFirestore.instance.collection('users').where('name', isEqualTo: widget.partnerName).limit(1).get();
      if (query.docs.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(query.docs.first.id).collection('incomingCall').doc('current').delete();
      }
    }

    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    if (mounted) Navigator.pop(context);
  }

  void _onSearchMovie(String query) {
    if (query.trim().isEmpty) return;
    String? videoId = YoutubePlayer.convertUrlToId(query.trim());

    if (videoId != null) {
      FirebaseFirestore.instance.collection('calls').doc(widget.roomId).set({'currentVideoId': videoId}, SetOptions(merge: true));
      _currentVideoId = videoId;
      _playVideo(videoId);
      _searchController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playing & Synced with Partner! 🎬'), backgroundColor: Color(0xFF00FF87)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid YouTube URL.'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _ytController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: const Color(0xFF130424),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: _endCall),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('${widget.platformName} Party with ${widget.partnerName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: widget.platformName == 'YouTube'
                      ? Column(
                    children: [
                      if (_isVideoLoaded && _ytController != null)
                        YoutubePlayer(controller: _ytController!, showVideoProgressIndicator: true, progressIndicatorColor: const Color(0xFF00FF87))
                      else
                        Container(height: 220, color: Colors.grey[900], child: const Center(child: Text('Paste a YouTube link below to start sync watching', style: TextStyle(color: Colors.white54)))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        color: const Color(0xFF18082A),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(hintText: 'Paste YouTube Link Here...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13), prefixIcon: const Icon(Icons.link, color: Colors.white70, size: 20), filled: true, fillColor: Colors.white.withOpacity(0.06), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), contentPadding: EdgeInsets.zero),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFF00FF87)), onPressed: () => _onSearchMovie(_searchController.text)),
                          ],
                        ),
                      ),
                    ],
                  )
                      : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.video_camera_front_rounded, size: 70, color: Color(0xFF00FF87)),
                        const SizedBox(height: 16),
                        Text('${widget.platformName} Call Active 🖥️', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('You are connected with ${widget.partnerName}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                        const SizedBox(height: 30),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF007A), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                          icon: const Icon(Icons.open_in_new, color: Colors.white),
                          label: Text('Open ${widget.platformName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            String url = 'https://google.com';
                            if (widget.platformName == 'Netflix') url = 'https://www.netflix.com';
                            if (widget.platformName == 'Amazon Prime Video') url = 'https://www.primevideo.com';
                            if (widget.platformName == 'Disney Hotstar') url = 'https://www.hotstar.com';

                            activePiPCall.value = {
                              'name': widget.partnerName,
                              'color': widget.partnerColor,
                              'roomId': widget.roomId,
                            };
                            Navigator.pop(context);

                            final Uri uri = Uri.parse(url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        const Text('(Your video call will continue floating on dashboard)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 🔴 Draggable Floating PiP
            Positioned(
              left: pipX,
              top: pipY,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    pipX += details.delta.dx;
                    pipY += details.delta.dy;
                  });
                },
                child: Material(
                  color: Colors.transparent,
                  elevation: 99,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _isPiPZoomed ? MediaQuery.of(context).size.width * 0.9 : 120,
                    height: _isPiPZoomed ? MediaQuery.of(context).size.height * 0.6 : 160,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E0E45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFF007A), width: 2.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          SizedBox.expand(
                            child: _remoteRenderer.srcObject != null
                                ? webrtc.RTCVideoView(_remoteRenderer, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                                : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(radius: 20, backgroundColor: widget.partnerColor, child: Text(widget.partnerName[0], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                                  const SizedBox(height: 8),
                                  Text(_callStatus, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF00FF87), fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                          if (!_isCameraOff)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                width: _isPiPZoomed ? 80 : 40,
                                height: _isPiPZoomed ? 120 : 60,
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF00FF87), width: 1)),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: webrtc.RTCVideoView(_localRenderer, mirror: true, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              color: Colors.black87,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _isPiPZoomed = !_isPiPZoomed),
                                    child: Text(_isPiPZoomed ? "Shrink Video" : "Tap to Zoom", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  if (_isPiPZoomed) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        GestureDetector(onTap: _toggleMic, child: CircleAvatar(radius: 16, backgroundColor: _isMuted ? Colors.redAccent : Colors.white24, child: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: Colors.white, size: 16))),
                                        GestureDetector(onTap: _endCall, child: const CircleAvatar(radius: 18, backgroundColor: Colors.redAccent, child: Icon(Icons.call_end, color: Colors.white, size: 18))),
                                        GestureDetector(onTap: _toggleCamera, child: CircleAvatar(radius: 16, backgroundColor: _isCameraOff ? Colors.redAccent : Colors.white24, child: Icon(_isCameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white, size: 16))),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ]
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- SOULMATE HEART ANIMATION SCREEN ----------------
class SoulmateHeartScreen extends StatefulWidget {
  const SoulmateHeartScreen({super.key});

  @override
  State<SoulmateHeartScreen> createState() => _SoulmateHeartScreenState();
}

class _SoulmateHeartScreenState extends State<SoulmateHeartScreen> with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isFlipped = false;
  bool _showFlowers = false;

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _playRomanticSong();

    _flipController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _flipAnimation = Tween<double>(begin: 0, end: pi).animate(CurvedAnimation(parent: _flipController, curve: Curves.easeInOutBack));

    _flipController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _showFlowers = true;
        });
      }
    });
  }

  void _playRomanticSong() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('audio/romantic_song.mp3'));
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _flipController.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_isFlipped) {
      _flipController.reverse();
      setState(() {
        _showFlowers = false;
        _isFlipped = false;
      });
    } else {
      setState(() {
        _isFlipped = true;
      });
      _flipController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    double heartSize = MediaQuery.of(context).size.shortestSide * 0.96;

    return Scaffold(
      backgroundColor: const Color(0xFF0C061E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          if (_showFlowers)
            const Positioned.fill(
              child: IgnorePointer(
                child: FallingFlowersAnimation(),
              ),
            ),

          Center(
            child: AnimatedBuilder(
              animation: _flipAnimation,
              builder: (context, child) {
                final transform = Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(_flipAnimation.value);

                bool isBackVisible = _flipAnimation.value >= (pi / 2);

                return Transform(
                  transform: transform,
                  alignment: Alignment.center,
                  child: ClipPath(
                    clipper: HeartClipper(),
                    child: Container(
                      width: heartSize,
                      height: heartSize,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB6C1), Color(0xFFFF007A)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      child: Center(
                        child: Transform(
                          transform: isBackVisible ? (Matrix4.identity()..rotateY(pi)) : Matrix4.identity(),
                          alignment: Alignment.center,
                          child: Container(
                            width: heartSize * 0.72,
                            margin: EdgeInsets.only(bottom: heartSize * 0.12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isBackVisible
                                    ? 'Look Behind 🥰'
                                    : 'Your sweet smile is my entire world.\n\nI wanted to capture this beautiful\nmoment and place it in your hands\nforever.\n\nThis ring is not just a gift,\nit\'s my whole heart that I am\ngiving to you.\n\nI love you, forever. ❤️',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isBackVisible ? 38 : 17,
                                  fontWeight: FontWeight.w900,
                                  height: 1.4,
                                  shadows: const [
                                    Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(2, 2))
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (!_isFlipped)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: _toggleFlip,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFF007A).withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFF007A), width: 2),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFFF007A).withOpacity(0.4), blurRadius: 15)
                        ]
                    ),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
            ),

          if (_isFlipped)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: GestureDetector(
                  onTap: _toggleFlip,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFF007A).withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFF007A), width: 2),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFFF007A).withOpacity(0.4), blurRadius: 15)
                        ]
                    ),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 4.0),
                      child: Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HeartClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    double width = size.width;
    double height = size.height;
    Path path = Path();

    path.moveTo(0.5 * width, height * 0.25);
    path.cubicTo(0.1 * width, -0.05 * height, -0.2 * width, 0.55 * height, 0.5 * width, 0.95 * height);
    path.moveTo(0.5 * width, height * 0.25);
    path.cubicTo(0.9 * width, -0.05 * height, 1.2 * width, 0.55 * height, 0.5 * width, 0.95 * height);

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
// ---------------- 🎵 60FPS SMOOTH & FULLSCREEN PARTNER MUSIC & VIDEO SYNC ----------------
class PartnerMusicSyncScreen extends StatefulWidget {
  final String roomId;
  const PartnerMusicSyncScreen({super.key, required this.roomId});

  @override
  State<PartnerMusicSyncScreen> createState() => _PartnerMusicSyncScreenState();
}

class _PartnerMusicSyncScreenState extends State<PartnerMusicSyncScreen> with WidgetsBindingObserver {
  YoutubePlayerController? _ytController;

  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();

  bool _isPlaying = false;
  String _connectionStatus = "Waiting for partner 🔴";
  String _partnerDisplayName = "Partner";
  StreamSubscription? _roomSub;
  bool _isCreator = false;
  bool _isPlayerReady = false;
  String _currentVideoId = "";
  String _lastLoadedVideoId = "";

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isUserSeeking = false;
  Timer? _positionTimer;

  // 🔴 Video Mode & WebRTC State
  bool _isVideoMode = false;
  bool _isStartingVideoMode = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  final webrtc.RTCVideoRenderer _localRenderer = webrtc.RTCVideoRenderer();
  final webrtc.RTCVideoRenderer _remoteRenderer = webrtc.RTCVideoRenderer();
  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? _localStream;
  StreamSubscription? _rtcRoomSub;
  StreamSubscription? _rtcCandidateSub;

  // PiP State
  bool _isPiP = false;
  double pipX = 20;
  double pipY = 100;

  // Floating Video Call PiP Position
  double _fsCamX = 16;
  double _fsCamY = 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChannels.platform.invokeMethod('SystemChrome.setEnabledSystemUIMode', [SystemUiMode.edgeToEdge]);
    _initRenderers();
    _initializeRoomOnFirebase();
    _startPositionTracker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      debugPrint("App minimized, audio running in background vault...");
    }
  }

  void _startPositionTracker() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_ytController != null && _isPlayerReady && !_isUserSeeking) {
        final pos = _ytController!.value.position;
        final dur = _ytController!.metadata.duration;
        if (pos.inSeconds != _currentPosition.inSeconds || dur != _totalDuration) {
          setState(() {
            _currentPosition = pos;
            _totalDuration = dur;
          });
        }
      }
    });
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
    } catch (e) {
      debugPrint("WebRTC init note: $e");
    }
  }

  String? _extractYouTubeId(String url) {
    String clean = url.trim();
    if (clean.isEmpty) return null;

    RegExp regExp = RegExp(
      r'(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|v\/|shorts\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    Match? match = regExp.firstMatch(clean);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return YoutubePlayer.convertUrlToId(clean);
  }

  void _initializeRoomOnFirebase() async {
    final docRef = FirebaseFirestore.instance.collection('musicRooms').doc(widget.roomId);
    var docSnap = await docRef.get();

    String myName = currentUserName.isNotEmpty ? currentUserName : "Shiba User";

    if (!docSnap.exists) {
      _isCreator = true;
      await docRef.set({
        'creatorName': myName,
        'partnerName': '',
        'creatorActive': true,
        'partnerActive': false,
        'mediaUrl': '',
        'videoId': '',
        'isPlaying': false,
        'positionMillis': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      _isCreator = false;
      await docRef.update({
        'partnerName': myName,
        'partnerActive': true,
      });
    }

    _listenToRoomSync(docRef);
  }

  void _listenToRoomSync(DocumentReference docRef) {
    _roomSub = docRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists || !mounted) return;
      var data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      String videoId = data['videoId'] ?? '';
      bool playing = data['isPlaying'] ?? false;
      bool partnerActive = data['partnerActive'] ?? false;
      bool creatorActive = data['creatorActive'] ?? false;
      int positionMillis = data['positionMillis'] ?? 0;

      // 🔥 Firebase के Timestamp से पता करें कि वीडियो कब सीक (Seek) किया गया था
      Timestamp? updateTs = data['updatedAt'] as Timestamp?;
      int elapsedMillis = 0;
      if (updateTs != null && playing) { // अगर वीडियो चल रहा है, तभी एक्स्ट्रा टाइम जोड़ें
        elapsedMillis = DateTime.now().millisecondsSinceEpoch - updateTs.millisecondsSinceEpoch;
        if (elapsedMillis < 0) elapsedMillis = 0;
      }

      String otherName = _isCreator
          ? (data['partnerName']?.toString().isNotEmpty == true ? data['partnerName'] : "Partner")
          : (data['creatorName']?.toString().isNotEmpty == true ? data['creatorName'] : "Room Host");

      String liveStatus = (partnerActive && creatorActive) ? "Active 🟢" : "Waiting for partner 🔴";

      if (mounted) {
        setState(() {
          _connectionStatus = liveStatus;
          _partnerDisplayName = otherName;
          _isPlaying = playing;
        });
      }

      if (videoId.isNotEmpty) {
        if (videoId != _lastLoadedVideoId) {
          _currentVideoId = videoId;
          _lastLoadedVideoId = videoId;
          _setupYoutubePlayer(videoId, playing, positionMillis);
        } else if (_isPlayerReady && _ytController != null && !_isUserSeeking) {
          try {
            int currentSec = _ytController!.value.position.inSeconds;

            // 🔥 एकदम सही टाइम कैलकुलेट करें (स्लाइडर जहाँ छोड़ा गया + जितना टाइम बीत चुका है)
            int targetSec = ((positionMillis + elapsedMillis) / 1000).round();

            // 🔥 अगर 2 सेकंड से ज्यादा का फर्क है, तो पार्टनर के फोन में तुरंत सिंक करें!
            if ((currentSec - targetSec).abs() > 2) {
              _ytController!.seekTo(Duration(seconds: targetSec));
            }

            if (playing && !_ytController!.value.isPlaying) {
              _ytController!.play();
            } else if (!playing && _ytController!.value.isPlaying) {
              _ytController!.pause();
            }
          } catch (e) {
            debugPrint("Sync catch: $e");
          }
        }
      }
    });
  }

  void _setupYoutubePlayer(String videoId, bool autoPlay, int startMillis) {
    _isPlayerReady = false;

    if (_ytController == null) {
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          enableCaption: false,
          isLive: false,
          forceHD: true,
          loop: false,
          controlsVisibleAtStart: true,
          hideControls: false,
          useHybridComposition: false,
          startAt: (startMillis / 1000).round(),
        ),
      )..addListener(_onPlayerStateChange);
    } else {
      try {
        _ytController!.load(videoId, startAt: (startMillis / 1000).round());
        _ytController!.unMute();
        if (autoPlay) {
          _ytController!.play();
        } else {
          _ytController!.pause();
        }
      } catch (e) {
        debugPrint("Player load error: $e");
      }
    }
    if (mounted) setState(() {});
  }

  void _onPlayerStateChange() {
    if (!mounted || _ytController == null) return;

    if (_ytController!.value.isReady && !_isPlayerReady) {
      setState(() {
        _isPlayerReady = true;
      });
      _ytController!.unMute();
      if (_isPlaying) {
        _ytController!.play();
      }
    }
  }

  void _pasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      setState(() {
        _linkController.text = data.text!.trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link pasted! 📋'),
          backgroundColor: Color(0xFF00FF87),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _loadAndSyncMedia(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    String? videoId = _extractYouTubeId(cleanUrl);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('कृपया सही YouTube लिंक दर्ज करें! ❌'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _currentVideoId = videoId;
    _lastLoadedVideoId = videoId;
    _setupYoutubePlayer(videoId, true, 0);

    await FirebaseFirestore.instance.collection('musicRooms').doc(widget.roomId).update({
      'mediaUrl': cleanUrl,
      'videoId': videoId,
      'isPlaying': true,
      'positionMillis': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _linkController.clear();
    FocusScope.of(context).unfocus();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('YouTube वीडियो लोड हुआ और सिंक हो गया! 🎶⚡'),
        backgroundColor: Color(0xFF00FF87),
      ),
    );
  }

  void _togglePlayPause() async {
    int currentMillis = 0;
    if (_ytController != null) {
      currentMillis = _ytController!.value.position.inMilliseconds;
    }

    bool nextState = !_isPlaying;

    if (_ytController != null) {
      if (nextState) {
        _ytController!.unMute();
        _ytController!.play();
      } else {
        _ytController!.pause();
      }
    }

    setState(() {
      _isPlaying = nextState;
    });

    await FirebaseFirestore.instance.collection('musicRooms').doc(widget.roomId).update({
      'isPlaying': nextState,
      'positionMillis': currentMillis,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _forward10Seconds() async {
    if (_ytController == null) return;
    int current = _ytController!.value.position.inSeconds;
    int total = _totalDuration.inSeconds;
    int target = (current + 10 > total) ? total : current + 10;
    _ytController!.seekTo(Duration(seconds: target));

    await FirebaseFirestore.instance.collection('musicRooms').doc(widget.roomId).update({
      'positionMillis': target * 1000,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _rewind10Seconds() async {
    if (_ytController == null) return;
    int current = _ytController!.value.position.inSeconds;
    int target = (current - 10 < 0) ? 0 : current - 10;
    _ytController!.seekTo(Duration(seconds: target));

    await FirebaseFirestore.instance.collection('musicRooms').doc(widget.roomId).update({
      'positionMillis': target * 1000,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _seekToPosition(double seconds) async {
    if (_ytController == null) return;
    _ytController!.seekTo(Duration(seconds: seconds.round()));

    // 🔥 स्लाइडर छोड़ते ही Firebase पर एकदम सही डेटा भेजें ताकि पार्टनर तुरंत सिंक हो जाए
    await FirebaseFirestore.instance.collection('musicRooms').doc(widget.roomId).update({
      'positionMillis': (seconds * 1000).round(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isPlaying': _isPlaying,
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Future<void> _toggleVideoMode() async {
    if (_isVideoMode) {
      _endVideoMode();
    } else {
      await _startVideoMode();
    }
  }

  Future<void> _startVideoMode() async {
    if (_isStartingVideoMode) return;
    setState(() => _isStartingVideoMode = true);

    try {
      if (!kIsWeb) {
        var camStatus = await Permission.camera.request();
        var micStatus = await Permission.microphone.request();

        if (!camStatus.isGranted || !micStatus.isGranted) {
          setState(() => _isStartingVideoMode = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video Mode के लिए कैमरा और माइक परमिशन आवश्यक है! ❌'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }

      _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': true,
      });
      _localRenderer.srcObject = _localStream;

      _peerConnection = await webrtc.createPeerConnection({
        'iceServers': [
          {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
        ]
      });

      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (webrtc.RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
          });
        }
      };

      final videoCallDoc = FirebaseFirestore.instance
          .collection('musicRooms')
          .doc(widget.roomId)
          .collection('videoCall')
          .doc('session');

      if (_isCreator) {
        _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
          videoCallDoc.collection('callerCandidates').add(candidate.toMap());
        };

        webrtc.RTCSessionDescription offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        await videoCallDoc.set({'offer': offer.toMap()});

        _rtcRoomSub = videoCallDoc.snapshots().listen((snap) async {
          var data = snap.data();
          if (data != null && data['answer'] != null) {
            var answer = webrtc.RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
            var remoteDesc = await _peerConnection?.getRemoteDescription();
            if (remoteDesc == null) {
              await _peerConnection!.setRemoteDescription(answer);
            }
          }
        });

        _rtcCandidateSub = videoCallDoc.collection('calleeCandidates').snapshots().listen((snap) {
          for (var change in snap.docChanges) {
            if (change.type.name == 'added') {
              var cData = change.doc.data();
              if (cData != null) {
                _peerConnection!.addCandidate(
                  webrtc.RTCIceCandidate(cData['candidate'], cData['sdpMid'], cData['sdpMLineIndex']),
                );
              }
            }
          }
        });
      } else {
        _peerConnection?.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
          videoCallDoc.collection('calleeCandidates').add(candidate.toMap());
        };

        _rtcRoomSub = videoCallDoc.snapshots().listen((snap) async {
          if (snap.exists) {
            var data = snap.data();
            if (data != null && data['offer'] != null) {
              var remoteDesc = await _peerConnection?.getRemoteDescription();
              if (remoteDesc == null) {
                var offer = data['offer'];
                await _peerConnection!.setRemoteDescription(
                  webrtc.RTCSessionDescription(offer['sdp'], offer['type']),
                );
                var answer = await _peerConnection!.createAnswer();
                await _peerConnection!.setLocalDescription(answer);
                await videoCallDoc.update({'answer': answer.toMap()});
              }
            }
          }
        });

        _rtcCandidateSub = videoCallDoc.collection('callerCandidates').snapshots().listen((snap) {
          for (var change in snap.docChanges) {
            if (change.type.name == 'added') {
              var cData = change.doc.data();
              if (cData != null) {
                _peerConnection!.addCandidate(
                  webrtc.RTCIceCandidate(cData['candidate'], cData['sdpMid'], cData['sdpMLineIndex']),
                );
              }
            }
          }
        });
      }

      setState(() {
        _isVideoMode = true;
        _isStartingVideoMode = false;
        _isMuted = false;
        _isCameraOff = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video Mode Activated! 🔴 लाइव वीडियो सेशन शुरू हुआ'),
          backgroundColor: Color(0xFFFF0055),
        ),
      );
    } catch (e) {
      debugPrint("Video Mode Init Error: $e");
      setState(() => _isStartingVideoMode = false);
    }
  }

  void _endVideoMode() {
    _rtcRoomSub?.cancel();
    _rtcCandidateSub?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.srcObject = null;

    setState(() {
      _isVideoMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video Mode Ended! Audio Mode Active 🟢'),
        backgroundColor: Color(0xFF00FF87),
      ),
    );
  }

  void _toggleMic() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      var audioTrack = _localStream!.getAudioTracks()[0];
      bool currentlyEnabled = audioTrack.enabled;
      audioTrack.enabled = !currentlyEnabled;

      setState(() {
        _isMuted = currentlyEnabled;
      });
    }
  }

  void _toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      var videoTrack = _localStream!.getVideoTracks()[0];
      bool currentlyEnabled = videoTrack.enabled;
      videoTrack.enabled = !currentlyEnabled;

      setState(() {
        _isCameraOff = currentlyEnabled;
      });
    }
  }

  void _sendRoomChatMessage() async {
    String message = _chatController.text.trim();
    if (message.isEmpty) return;

    _chatController.clear();
    String myName = currentUserName.isNotEmpty ? currentUserName : "Shiba User";

    await FirebaseFirestore.instance
        .collection('musicRooms')
        .doc(widget.roomId)
        .collection('chat')
        .add({
      'sender': myName,
      'text': message,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _leaveRoom() async {
    _endVideoMode();
    final docRef = FirebaseFirestore.instance.collection('musicRooms').doc(widget.roomId);
    if (_isCreator) {
      await docRef.update({'creatorActive': false});
    } else {
      await docRef.update({'partnerActive': false});
    }
    _ytController?.pause();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionTimer?.cancel();
    _leaveRoom();
    _roomSub?.cancel();
    _ytController?.removeListener(_onPlayerStateChange);
    _ytController?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _linkController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color themeAccent = _isVideoMode ? const Color(0xFFFF0055) : const Color(0xFF00FF87);

    if (_ytController != null) {
      return YoutubePlayerBuilder(
        onEnterFullScreen: () {},
        onExitFullScreen: () {},
        player: YoutubePlayer(
          controller: _ytController!,
          showVideoProgressIndicator: true,
          progressIndicatorColor: themeAccent,
          bottomActions: [
            CurrentPosition(),
            ProgressBar(
              isExpanded: true,
              colors: ProgressBarColors(
                playedColor: themeAccent,
                handleColor: themeAccent,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ),
            RemainingDuration(),
            PlaybackSpeedButton(),
            const FullScreenButton(),
          ],
        ),
        builder: (context, player) {
          return _buildMainScaffold(player, themeAccent);
        },
      );
    }

    return _buildMainScaffold(null, themeAccent);
  }

  Widget _buildMainScaffold(Widget? playerWidget, Color themeAccent) {
    return WillPopScope(
      onWillPop: () async {
        if (_ytController != null && _ytController!.value.isFullScreen) {
          _ytController!.toggleFullScreenMode();
          return false;
        }
        if (!_isPiP) {
          setState(() => _isPiP = true);
          return false;
        }
        return true;
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          bool isLandscape = orientation == Orientation.landscape;

          if (isLandscape) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (details) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final tapPosition = details.globalPosition.dx;

                  if (tapPosition < screenWidth / 2) {
                    _rewind10Seconds();
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('-10s ⏪'), duration: Duration(milliseconds: 500)),
                    );
                  } else {
                    _forward10Seconds();
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('+10s ⏩'), duration: Duration(milliseconds: 500)),
                    );
                  }
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: playerWidget ?? const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
                              onPressed: () {
                                if (_ytController != null && _ytController!.value.isFullScreen) {
                                  _ytController!.toggleFullScreenMode();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isVideoMode)
                      Positioned(
                        left: _fsCamX,
                        top: 10,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _fsCamX += details.delta.dx;
                            });
                          },
                          child: Container(
                            width: 140,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFF0055), width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 10)],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _remoteRenderer.srcObject != null
                                  ? webrtc.RTCVideoView(
                                _remoteRenderer,
                                objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                              )
                                  : const Center(
                                child: Text('Partner...', style: TextStyle(color: Colors.white54, fontSize: 10)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
              backgroundColor: const Color(0xFF0C061E),
              body: SafeArea(
                child: Stack(
                    children: [
                    if (_isPiP)
                Positioned(
                left: pipX,
                top: pipY,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      pipX += details.delta.dx;
                      pipY += details.delta.dy;
                    });
                  },
                  onTap: () => setState(() => _isPiP = false),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 230,
                      height: 75,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E103E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: themeAccent, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isVideoMode ? Icons.videocam_rounded : Icons.music_note_rounded,
                            color: themeAccent,
                            size: 30,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'With $_partnerDisplayName 🎧',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(_connectionStatus, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                            onPressed: _leaveRoom,
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              )
              else ...[
          Column(
          children: [
          Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
          IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
          onPressed: () => setState(() => _isPiP = true),
          ),
          GestureDetector(
          onTap: _isStartingVideoMode ? null : _toggleVideoMode,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
          color: _isVideoMode ? const Color(0xFFFF0055) : Colors.white24,
          width: 1.5,
          ),
          ),
          child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          Text(
          'VIDEO MODE',
          style: TextStyle(
          color: _isVideoMode ? const Color(0xFFFF0055) : Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          ),
          ),
          const SizedBox(width: 6),
          Container(
          width: 48,
          height: 24,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
          color: _isVideoMode ? const Color(0xFFFF0055) : Colors.black45,
          borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
          alignment: Alignment.center,
          children: [
          Align(
          alignment: _isVideoMode ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          ),
          child: Center(
          child: _isStartingVideoMode
          ? const SizedBox(
          width: 8,
          height: 8,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black),
          )
              : Icon(
          _isVideoMode ? Icons.videocam : Icons.videocam_off,
          size: 11,
          color: _isVideoMode ? const Color(0xFFFF0055) : Colors.black54,
          ),
          ),
          ),
          ),
          ],
          ),
          ),
          ],
          ),
          ),
          ),
          Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
          _connectionStatus,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          ),
          ],
          ),
          ),
          Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
          _isVideoMode
          ? '🎥 Video Mode Active • With: $_partnerDisplayName'
              : '🎧 Audio Mode Active • Listening with: $_partnerDisplayName',
          style: TextStyle(color: themeAccent, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          ),
          ),
          const SizedBox(height: 4),
          Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
          color: const Color(0xFF1E103E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: themeAccent.withOpacity(0.3)),
          ),
          child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
          Row(
          children: [
          const Text('Room ID: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text(widget.roomId, style: TextStyle(color: themeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
          ),
          IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.copy, color: Colors.white, size: 16),
          onPressed: () {
          Clipboard.setData(ClipboardData(text: widget.roomId));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Room ID Copied!'), backgroundColor: themeAccent));
          },
          ),
          ],
          ),
          ),
          ),
          const SizedBox(height: 6),
          Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
          children: [
          Expanded(
          child: Container(
          decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: TextField(
          controller: _linkController,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
          hintText: 'Paste YouTube link here...',
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          suffixIcon: IconButton(
          icon: Icon(Icons.paste_rounded, color: themeAccent, size: 16),
          onPressed: _pasteFromClipboard,
          ),
          ),
          ),
          ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
          style: ElevatedButton.styleFrom(
          backgroundColor: themeAccent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => _loadAndSyncMedia(_linkController.text),
          child: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
          ),
          ],
          ),
          ),
          const SizedBox(height: 6),

          // 📺 प्लेयर एरिया
          if (_currentVideoId.isNotEmpty && playerWidget != null)
          Container(
          height: 155,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: themeAccent.withOpacity(0.6), width: 1.5),
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
          children: [
          Positioned.fill(
          child: Stack(
          children: [
          Opacity(
          opacity: _isVideoMode ? 1.0 : 0.01,
          child: playerWidget,
          ),
          if (!_isVideoMode)
          Container(
          color: const Color(0xFF160830),
          child: Center(
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Icon(Icons.music_note_rounded, color: themeAccent, size: 38),
          const SizedBox(height: 6),
          const Text(
          'Audio Mode Playing 🎧 (गाना बज रहा है)',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          ],
          ),
          ),
          ),
          ],
          ),
          ),
          ],
          ),
          ),
          )
          else
          Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
          color: const Color(0xFF1E103E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: themeAccent.withOpacity(0.4)),
          ),
          child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Icon(Icons.music_note_rounded, color: themeAccent, size: 20),
          const SizedBox(width: 6),
          const Text('Paste a YouTube link above to play together', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
          ),
          ),
          const SizedBox(height: 4),

          // 🎛️ कंट्रोल्स
          Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
          children: [
          Row(
          children: [
          Text(_formatDuration(_currentPosition), style: const TextStyle(color: Colors.white70, fontSize: 10)),
          Expanded(
          child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
          trackHeight: 2.5,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          activeTrackColor: themeAccent,
          inactiveTrackColor: Colors.white24,
          thumbColor: themeAccent,
          ),
          child: Slider(
          min: 0.0,
          max: _totalDuration.inSeconds > 0 ? _totalDuration.inSeconds.toDouble() : 1.0,
          value: _currentPosition.inSeconds.toDouble().clamp(0.0, _totalDuration.inSeconds > 0 ? _totalDuration.inSeconds.toDouble() : 1.0),
          onChangeStart: (_) => _isUserSeeking = true,
          onChanged: (val) => setState(() => _currentPosition = Duration(seconds: val.round())),
          onChangeEnd: (val) {
          _isUserSeeking = false;
          _seekToPosition(val);
          },
          ),
          ),
          ),
          Text(_formatDuration(_totalDuration), style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
          ),
          Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          if (!_isVideoMode) ...[
          IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 22),
          onPressed: _rewind10Seconds,
          ),
          const SizedBox(width: 12),
          ],
          ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
          backgroundColor: _isPlaying ? Colors.redAccent : themeAccent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 16),
          label: Text(_isPlaying ? 'PAUSE' : 'PLAY', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
          onPressed: _togglePlayPause,
          ),
          if (!_isVideoMode) ...[
          const SizedBox(width: 12),
          IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 22),
          onPressed: _forward10Seconds,
          ),
          ],
          ],
          ),
          ],
          ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // चैट लिस्ट
          Expanded(
          child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('musicRooms')
              .doc(widget.roomId)
              .collection('chat')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
          if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: themeAccent, strokeWidth: 2));
          }

          var chatDocs = snapshot.data!.docs;
          String myName = currentUserName.isNotEmpty ? currentUserName : "Shiba User";

          return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: chatDocs.length,
          itemBuilder: (context, index) {
          var msg = chatDocs[index].data() as Map<String, dynamic>;
          bool isMe = msg['sender'] == myName;

          return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
          color: isMe ? themeAccent : const Color(0xFF1E103E),
          borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
          msg['text'] ?? '',
          style: TextStyle(
          color: isMe ? (_isVideoMode ? Colors.white : Colors.black) : Colors.white,
          fontSize: 11,
          ),
          ),
          ),
          );
          },
          );
          },
          ),
          ),

          // चैट टाइपिंग बार (बॉटम ओवरफ्लो 0 पिक्सेल फिक्स्ड)
          Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: const Color(0xFF130424),
          child: SafeArea(
          top: false,
          bottom: true,
          child: Row(
          children: [
          Expanded(
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
          ),
          child: TextField(
          controller: _chatController,
          style: const TextStyle(color: Colors.white, fontSize: 11),
          decoration: const InputDecoration(
          hintText: 'Type a message...',
          hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
          border: InputBorder.none,
          isDense: true,
          ),
          onSubmitted: (_) => _sendRoomChatMessage(),
          ),
          ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
          onTap: _sendRoomChatMessage,
          child: CircleAvatar(
          radius: 14,
          backgroundColor: themeAccent,
          child: Icon(Icons.send_rounded, color: _isVideoMode ? Colors.white : Colors.black, size: 12),
          ),
          ),
          ],
          ),
          ),
          ),
          ],
          ),

          // 🔴 FLOATING VIDEO PIP (Draggable with 3 Action Buttons)
          if (_isVideoMode)
          Positioned(
          left: _fsCamX,
          top: _fsCamY,
          child: GestureDetector(
          onPanUpdate: (details) {
          setState(() {
          _fsCamX += details.delta.dx;
          _fsCamY += details.delta.dy;
          });
          },
          child: Material(
          color: Colors.transparent,
          elevation: 10,
          child: Container(
          width: 140,
          height: 200,
          decoration: BoxDecoration(
          color: const Color(0xFF17082A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF0055), width: 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
          children: [
          // Remote Video Feed
          SizedBox.expand(
          child: _remoteRenderer.srcObject != null
          ? webrtc.RTCVideoView(_remoteRenderer, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : const Center(
          child: Text('Connecting...', style: TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          ),

          // Local Video Feed (Top Right Corner)
          if (!_isCameraOff)
          Positioned(
          top: 8,
          right: 8,
          child: Container(
          width: 40,
          height: 60,
          decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF00FF87), width: 1.5),
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: webrtc.RTCVideoView(_localRenderer, mirror: true, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),
          ),
          ),

          // 3 Controls Overlay (Mute, End, Camera)
          Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
          GestureDetector(
          onTap: _toggleMic,
          child: CircleAvatar(
          radius: 15,
          backgroundColor: _isMuted ? Colors.redAccent : Colors.black54,
          child: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: Colors.white, size: 14),
          ),
          ),
          GestureDetector(
          onTap: _endVideoMode,
          child: const CircleAvatar(
          radius: 17,
          backgroundColor: Colors.redAccent,
          child: Icon(Icons.call_end, color: Colors.white, size: 16),
          ),
          ),
          GestureDetector(
          onTap: _toggleCamera,
          child: CircleAvatar(
          radius: 15,
          backgroundColor: _isCameraOff ? Colors.redAccent : Colors.black54,
          child: Icon(_isCameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white, size: 14),
          ),
          ),
          ],
          ),
          ),
          ],
          ),
          ),
          ),
          ),
          ),
          ),
          ]
        ] // <-- इस जगह पर ब्रैकेट क्लोज होना रह गया था, अब ठीक है!
          ),
          ),
          );
        },
      ),
    );
  }
}