// ignore_for_file: prefer_const_constructors, use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:timeago/timeago.dart' as timeago;

// ----------------------------------------------------------------------
// Constants & Helpers
// ----------------------------------------------------------------------

class ApiConstants {
  static const String baseUrl = 'https://tweeter.runflare.run/api';
  static const String uploadsUrl = 'https://tweeter.runflare.run/api/files';
  static const String thumbnailsUrl = 'https://tweeter.runflare.run/api/thumbnails';

  static Uri uri(String endpoint) => Uri.parse('$baseUrl$endpoint');
  static Uri fileUri(String filePath) => Uri.parse('$uploadsUrl/$filePath');
  static Uri thumbUri(String thumbPath) => Uri.parse('$thumbnailsUrl/$thumbPath');
}

class StorageKeys {
  static const String token = 'auth_token';
  static const String userId = 'user_id';
}

class DateFormatter {
  static String format(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 7) {
      return DateFormat.yMMMd().add_jm().format(date);
    } else {
      return timeago.format(date, locale: 'en');
    }
  }
}

// ----------------------------------------------------------------------
// Models
// ----------------------------------------------------------------------

class User {
  final int id;
  final String username;
  final String name;
  final String? bio;
  final String? phone;
  final String? profilePicture;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.name,
    this.bio,
    this.phone,
    this.profilePicture,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      name: json['name'],
      bio: json['bio'],
      phone: json['phone'],
      profilePicture: json['profile_picture'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'name': name,
    'bio': bio,
    'phone': phone,
    'profile_picture': profilePicture,
    'created_at': createdAt.toIso8601String(),
  };
}

class Chat {
  final int id;
  final String type; // private, group, channel
  final String? title;
  final DateTime createdAt;
  final bool isPublic;
  final int participantsCount;
  final User? otherUser; // for private chats

  Chat({
    required this.id,
    required this.type,
    this.title,
    required this.createdAt,
    required this.isPublic,
    required this.participantsCount,
    this.otherUser,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      type: json['type'],
      title: json['title'],
      createdAt: DateTime.parse(json['created_at']),
      isPublic: json['is_public'],
      participantsCount: json['participants_count'],
      otherUser: json['other_user'] != null ? User.fromJson(json['other_user']) : null,
    );
  }
}

class Message {
  final int id;
  final int senderId;
  final String senderName;
  final String? content;
  final String? mediaPath;
  final String? mediaType;
  final String? thumbnailPath;
  final DateTime createdAt;
  final DateTime? editedAt;
  final List<ReadReceipt> readBy;
  final int readCount;

  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.content,
    this.mediaPath,
    this.mediaType,
    this.thumbnailPath,
    required this.createdAt,
    this.editedAt,
    required this.readBy,
    required this.readCount,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      senderId: json['sender_id'],
      senderName: json['sender_name'],
      content: json['content'],
      mediaPath: json['media_path'],
      mediaType: json['media_type'],
      thumbnailPath: json['thumbnail_path'],
      createdAt: DateTime.parse(json['created_at']),
      editedAt: json['edited_at'] != null ? DateTime.parse(json['edited_at']) : null,
      readBy: (json['read_by'] as List)
          .map((e) => ReadReceipt.fromJson(e))
          .toList(),
      readCount: json['read_count'],
    );
  }
}

class ReadReceipt {
  final int userId;
  final DateTime readAt;

  ReadReceipt({required this.userId, required this.readAt});

  factory ReadReceipt.fromJson(Map<String, dynamic> json) {
    return ReadReceipt(
      userId: json['user_id'],
      readAt: DateTime.parse(json['read_at']),
    );
  }
}

class Participant {
  final int userId;
  final String role;
  final DateTime joinedAt;

  Participant({required this.userId, required this.role, required this.joinedAt});
}

// ----------------------------------------------------------------------
// API Service
// ----------------------------------------------------------------------

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs?.getString(StorageKeys.token);
  }

  String? get token => _token;

  Future<void> setToken(String token) async {
    _token = token;
    await _prefs?.setString(StorageKeys.token, token);
  }

  Future<void> clearToken() async {
    _token = null;
    await _prefs?.remove(StorageKeys.token);
    await _prefs?.remove(StorageKeys.userId);
  }

  Future<int?> getUserId() async {
    return _prefs?.getInt(StorageKeys.userId);
  }

  Future<void> setUserId(int id) async {
    await _prefs?.setInt(StorageKeys.userId, id);
  }

  Map<String, String> _headers({bool multipart = false}) {
    final headers = {
      'Accept': 'application/json',
    };
    if (!multipart) {
      headers['Content-Type'] = 'application/json';
    }
    if (_token != null) {
      headers['Authorization'] = _token!;
    }
    return headers;
  }

  // Generic request methods
  Future<dynamic> get(String endpoint) async {
    final uri = ApiConstants.uri(endpoint);
    final response = await http.get(uri, headers: _headers());
    return _processResponse(response);
  }

  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    final uri = ApiConstants.uri(endpoint);
    final response = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _processResponse(response);
  }

  Future<dynamic> put(String endpoint, {Map<String, dynamic>? body}) async {
    final uri = ApiConstants.uri(endpoint);
    final response = await http.put(
      uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _processResponse(response);
  }

  Future<dynamic> delete(String endpoint) async {
    final uri = ApiConstants.uri(endpoint);
    final response = await http.delete(uri, headers: _headers());
    return _processResponse(response);
  }

  Future<dynamic> multipartRequest(
      String method,
      String endpoint,
      Map<String, String> fields,
      List<http.MultipartFile> files,
      ) async {
    final uri = ApiConstants.uri(endpoint);
    var request = http.MultipartRequest(method, uri);
    request.headers.addAll(_headers(multipart: true));
    request.fields.addAll(fields);
    request.files.addAll(files);
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _processResponse(response);
  }

  dynamic _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      throw Exception('API error: ${response.statusCode} - ${response.body}');
    }
  }

  // ------------------------------------------------------------------
  // Auth
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> login(String username, String password) async {
    final body = {'username': username, 'password': password};
    final res = await post('/login', body: body);
    return res;
  }

  Future<Map<String, dynamic>> register(String username, String name, String password,
      {String? phone, String? bio}) async {
    final body = {
      'username': username,
      'name': name,
      'password': password,
      if (phone != null) 'phone': phone,
      if (bio != null) 'bio': bio,
    };
    final res = await post('/register', body: body);
    return res;
  }

  Future<void> logout() async {
    await post('/logout');
    await clearToken();
  }

  // ------------------------------------------------------------------
  // Users
  // ------------------------------------------------------------------
  Future<List<User>> getUsers() async {
    final res = await get('/users');
    return (res as List).map((e) => User.fromJson(e)).toList();
  }

  Future<User> getUser(int id) async {
    final res = await get('/users/$id');
    return User.fromJson(res);
  }

  Future<User> updateUser(int id,
      {String? name, String? bio, String? phone, String? username, File? profilePicture}) async {
    final fields = <String, String>{};
    if (name != null) fields['name'] = name;
    if (bio != null) fields['bio'] = bio;
    if (phone != null) fields['phone'] = phone;
    if (username != null) fields['username'] = username;

    List<http.MultipartFile> files = [];
    if (profilePicture != null) {
      final bytes = await profilePicture.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'profile_picture',
        bytes,
        filename: path.basename(profilePicture.path),
      );
      files.add(multipartFile);
    }

    final res = await multipartRequest('PUT', '/users/$id', fields, files);
    return User.fromJson(res);
  }

  // ------------------------------------------------------------------
  // Chats
  // ------------------------------------------------------------------
  Future<List<Chat>> getChats() async {
    final res = await get('/chats');
    return (res as List).map((e) => Chat.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> createPrivateChat(int userId) async {
    final body = {'type': 'private', 'user_id': userId};
    return await post('/chats', body: body);
  }

  Future<Map<String, dynamic>> createGroup(String title, {bool isPublic = false}) async {
    final body = {'type': 'group', 'title': title, 'is_public': isPublic};
    return await post('/chats', body: body);
  }

  Future<Map<String, dynamic>> createChannel(String title, {bool isPublic = false}) async {
    final body = {'type': 'channel', 'title': title, 'is_public': isPublic};
    return await post('/chats', body: body);
  }

  // ------------------------------------------------------------------
  // Messages
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>> sendMessage(
      int chatId,
      {String? content, File? media, String? mediaTypeOverride}) async {
    final fields = <String, String>{};
    if (content != null && content.isNotEmpty) {
      fields['content'] = content;
    }
    List<http.MultipartFile> files = [];
    if (media != null) {
      final bytes = await media.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'media',
        bytes,
        filename: path.basename(media.path),
      );
      files.add(multipartFile);
    }
    return await multipartRequest('POST', '/chats/$chatId/messages', fields, files);
  }

  Future<Map<String, dynamic>> getMessages(int chatId, {int page = 1, int perPage = 30}) async {
    final res = await get('/chats/$chatId/messages?page=$page&per_page=$perPage');
    return res;
  }

  Future<Map<String, dynamic>> editMessage(int messageId, String content) async {
    final body = {'content': content};
    return await put('/messages/$messageId', body: body);
  }

  Future<void> deleteMessage(int messageId) async {
    await delete('/messages/$messageId');
  }

  Future<void> markRead(int messageId) async {
    await post('/messages/$messageId/read');
  }

  // ------------------------------------------------------------------
  // Group/Channel management
  // ------------------------------------------------------------------
  Future<void> addMember(int chatId, int userId, {String role = 'member'}) async {
    final body = {'user_id': userId, 'role': role};
    await post('/chats/$chatId/members', body: body);
  }

  Future<void> removeMember(int chatId, int userId) async {
    await delete('/chats/$chatId/members/$userId');
  }

  Future<void> subscribeChannel(int chatId) async {
    await post('/channels/$chatId/subscribe');
  }

  Future<void> unsubscribeChannel(int chatId) async {
    await delete('/channels/$chatId/subscribe');
  }
}

// ----------------------------------------------------------------------
// Providers (State Management)
// ----------------------------------------------------------------------

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  User? _currentUser;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _api.token != null;

  Future<void> checkAuthStatus() async {
    await _api.init();
    if (_api.token != null) {
      final userId = await _api.getUserId();
      if (userId != null) {
        try {
          _currentUser = await _api.getUser(userId);
          notifyListeners();
        } catch (e) {
          // Token invalid
          await _api.clearToken();
        }
      }
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _api.login(username, password);
      await _api.setToken(res['token']);
      await _api.setUserId(res['user_id']);
      _currentUser = await _api.getUser(res['user_id']);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> register(String username, String name, String password,
      {String? phone, String? bio}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.register(username, name, password, phone: phone, bio: bio);
      // after registration, login
      await login(username, password);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _api.logout();
      _currentUser = null;
    } catch (e) {
      // still clear local
      await _api.clearToken();
      _currentUser = null;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateProfile({
    String? name,
    String? bio,
    String? phone,
    String? username,
    File? profilePicture,
  }) async {
    if (_currentUser == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      _currentUser = await _api.updateUser(
        _currentUser!.id,
        name: name,
        bio: bio,
        phone: phone,
        username: username,
        profilePicture: profilePicture,
      );
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  List<Chat> _chats = [];
  Map<int, List<Message>> _messages = {}; // chatId -> messages
  Map<int, int> _messagePages = {}; // chatId -> current page
  Map<int, bool> _hasMoreMessages = {}; // chatId -> has more
  bool _isLoading = false;

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;

  Future<void> loadChats() async {
    _isLoading = true;
    notifyListeners();
    try {
      _chats = await _api.getChats();
    } catch (e) {
      // handle error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Message> getMessages(int chatId) {
    return _messages[chatId] ?? [];
  }

  bool hasMoreMessages(int chatId) => _hasMoreMessages[chatId] ?? false;

  Future<void> loadMessages(int chatId, {bool reset = true}) async {
    if (reset) {
      _messages[chatId] = [];
      _messagePages[chatId] = 1;
      _hasMoreMessages[chatId] = true;
    }
    if (!(_hasMoreMessages[chatId] ?? true)) return;

    _isLoading = true;
    notifyListeners();
    try {
      final page = _messagePages[chatId] ?? 1;
      final res = await _api.getMessages(chatId, page: page, perPage: 30);
      final List<Message> newMessages = (res['messages'] as List)
          .map((e) => Message.fromJson(e))
          .toList();
      if (newMessages.isNotEmpty) {
        _messages[chatId] = [...?_messages[chatId], ...newMessages];
        _messagePages[chatId] = page + 1;
      }
      _hasMoreMessages[chatId] = newMessages.length >= 30 && _messages[chatId]!.length < res['total'];
    } catch (e) {
      // handle error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(int chatId, {String? text, File? media}) async {
    try {
      final res = await _api.sendMessage(chatId, content: text, media: media);
      final message = Message.fromJson({
        'id': res['message_id'],
        'sender_id': ApiService().token, // will be replaced later
        'sender_name': 'You',
        'content': text,
        'media_path': null, // we need to fetch
        'media_type': null,
        'thumbnail_path': null,
        'created_at': res['created_at'],
        'edited_at': null,
        'read_by': [],
        'read_count': 0,
      });
      // prepend to list (newest first in UI? Actually we display from bottom)
      _messages[chatId]?.insert(0, message);
      notifyListeners();
      // auto-mark read
      _api.markRead(res['message_id']);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> editMessage(int chatId, int messageId, String newContent) async {
    try {
      await _api.editMessage(messageId, newContent);
      final index = _messages[chatId]?.indexWhere((m) => m.id == messageId);
      if (index != null && index != -1) {
        final msg = _messages[chatId]![index];
        _messages[chatId]![index] = Message(
          id: msg.id,
          senderId: msg.senderId,
          senderName: msg.senderName,
          content: newContent,
          mediaPath: msg.mediaPath,
          mediaType: msg.mediaType,
          thumbnailPath: msg.thumbnailPath,
          createdAt: msg.createdAt,
          editedAt: DateTime.now(),
          readBy: msg.readBy,
          readCount: msg.readCount,
        );
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMessage(int chatId, int messageId) async {
    try {
      await _api.deleteMessage(messageId);
      _messages[chatId]?.removeWhere((m) => m.id == messageId);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> markRead(int chatId, int messageId) async {
    await _api.markRead(messageId);
    // update read receipt locally
    final currentUserId = await ApiService().getUserId();
    if (currentUserId != null) {
      final index = _messages[chatId]?.indexWhere((m) => m.id == messageId);
      if (index != null && index != -1) {
        final msg = _messages[chatId]![index];
        final alreadyRead = msg.readBy.any((r) => r.userId == currentUserId);
        if (!alreadyRead) {
          _messages[chatId]![index] = Message(
            id: msg.id,
            senderId: msg.senderId,
            senderName: msg.senderName,
            content: msg.content,
            mediaPath: msg.mediaPath,
            mediaType: msg.mediaType,
            thumbnailPath: msg.thumbnailPath,
            createdAt: msg.createdAt,
            editedAt: msg.editedAt,
            readBy: [
              ...msg.readBy,
              ReadReceipt(userId: currentUserId, readAt: DateTime.now())
            ],
            readCount: msg.readCount + 1,
          );
          notifyListeners();
        }
      }
    }
  }
}

class UserProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  List<User> _users = [];
  bool _isLoading = false;

  List<User> get users => _users;
  bool get isLoading => _isLoading;

  Future<void> loadUsers() async {
    _isLoading = true;
    notifyListeners();
    try {
      _users = await _api.getUsers();
    } catch (e) {
      // handle error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

// ----------------------------------------------------------------------
// Main & App
// ----------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: MaterialApp(
        title: 'Telegram Clone',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: AppBarTheme(
            elevation: 0,
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconTheme: IconThemeData(color: Colors.black),
            titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
        ),
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.isLoading) {
              return SplashScreen();
            }
            if (auth.isAuthenticated && auth.currentUser != null) {
              return HomeScreen();
            } else {
              return LoginScreen();
            }
          },
        ),
        routes: {
          '/login': (_) => LoginScreen(),
          '/register': (_) => RegisterScreen(),
          '/home': (_) => HomeScreen(),
          '/profile': (_) => ProfileScreen(),
          '/edit-profile': (_) => EditProfileScreen(),
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Screens
// ----------------------------------------------------------------------

class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message, size: 80, color: Colors.blue).animate().scale(duration: 600.ms).then().shake(),
            SizedBox(height: 20),
            Text('Telegram Clone', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeIn));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await auth.login(_usernameController.text.trim(), _passwordController.text.trim());
        // navigation handled by auth state change
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 100, color: Colors.blue),
                  SizedBox(height: 20),
                  Text('Welcome back!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  SizedBox(height: 8),
                  Text('Sign in to continue', style: TextStyle(fontSize: 16, color: Colors.grey[600]), textAlign: TextAlign.center),
                  SizedBox(height: 40),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          validator: (v) => v!.isEmpty ? 'Username required' : null,
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          validator: (v) => v!.isEmpty ? 'Password required' : null,
                        ),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: auth.isLoading ? null : _login,
                          child: auth.isLoading
                              ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text('Sign In', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                    child: Text("Don't have an account? Sign up"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  bool _obscurePassword = true;

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await auth.register(
          _usernameController.text.trim(),
          _nameController.text.trim(),
          _passwordController.text.trim(),
          phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
          bio: _bioController.text.trim().isNotEmpty ? _bioController.text.trim() : null,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
                  validator: (v) => v!.isEmpty ? 'Username required' : null,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge)),
                  validator: (v) => v!.isEmpty ? 'Name required' : null,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => v!.length < 6 ? 'Password too short' : null,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone)),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: 'Bio (optional)', prefixIcon: Icon(Icons.info), alignLabelWithHint: true),
                ),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : _register,
                  child: auth.isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('Sign Up', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.loadChats();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Telegram'),
        leading: IconButton(
          icon: CircleAvatar(
            backgroundImage: auth.currentUser?.profilePicture != null
                ? CachedNetworkImageProvider(ApiConstants.fileUri(auth.currentUser!.profilePicture!).toString())
                : null,
            child: auth.currentUser?.profilePicture == null
                ? Text(auth.currentUser?.name[0] ?? 'U', style: TextStyle(color: Colors.white))
                : null,
            backgroundColor: Colors.blue,
          ),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: 'Chats', icon: Icon(Icons.chat)),
            Tab(text: 'Contacts', icon: Icon(Icons.people)),
            Tab(text: 'Channels', icon: Icon(Icons.campaign)),
          ],
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(auth.currentUser?.name ?? 'User'),
                accountEmail: Text('@${auth.currentUser?.username ?? ''}'),
                currentAccountPicture: CircleAvatar(
                  backgroundImage: auth.currentUser?.profilePicture != null
                      ? CachedNetworkImageProvider(ApiConstants.fileUri(auth.currentUser!.profilePicture!).toString())
                      : null,
                  child: auth.currentUser?.profilePicture == null
                      ? Text(auth.currentUser?.name[0] ?? 'U', style: TextStyle(fontSize: 30))
                      : null,
                ),
              ),
              ListTile(
                leading: Icon(Icons.person),
                title: Text('Profile'),
                onTap: () => Navigator.pushNamed(context, '/profile'),
              ),
              ListTile(
                leading: Icon(Icons.edit),
                title: Text('Edit Profile'),
                onTap: () => Navigator.pushNamed(context, '/edit-profile'),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.exit_to_app),
                title: Text('Logout'),
                onTap: () async {
                  await auth.logout();
                },
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Chats Tab
          chatProvider.isLoading && chatProvider.chats.isEmpty
              ? Center(child: CircularProgressIndicator())
              : RefreshIndicator(
            onRefresh: _loadData,
            child: chatProvider.chats.isEmpty
                ? Center(child: Text('No chats yet'))
                : ListView.builder(
              itemCount: chatProvider.chats.length,
              itemBuilder: (ctx, i) => ChatTile(chat: chatProvider.chats[i]),
            ),
          ),
          // Contacts Tab
          Consumer<UserProvider>(
            builder: (context, userProvider, _) {
              if (userProvider.isLoading && userProvider.users.isEmpty) {
                userProvider.loadUsers();
                return Center(child: CircularProgressIndicator());
              }
              return RefreshIndicator(
                onRefresh: userProvider.loadUsers,
                child: ListView.builder(
                  itemCount: userProvider.users.length,
                  itemBuilder: (ctx, i) {
                    final user = userProvider.users[i];
                    if (user.id == auth.currentUser?.id) return SizedBox.shrink();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user.profilePicture != null
                            ? CachedNetworkImageProvider(ApiConstants.fileUri(user.profilePicture!).toString())
                            : null,
                        child: user.profilePicture == null ? Text(user.name[0]) : null,
                      ),
                      title: Text(user.name),
                      subtitle: Text('@${user.username}'),
                      trailing: IconButton(
                        icon: Icon(Icons.message),
                        onPressed: () async {
                          final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                          final res = await chatProvider.createPrivateChat(user.id);
                          final chatId = res['chat_id'];
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: chatId, title: user.name)),
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
          // Channels Tab
          Consumer<ChatProvider>(
            builder: (context, cp, _) {
              final channels = cp.chats.where((c) => c.type == 'channel').toList();
              return ListView.builder(
                itemCount: channels.length,
                itemBuilder: (ctx, i) => ChatTile(chat: channels[i]),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatBottomSheet(),
        child: Icon(Icons.edit),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _showNewChatBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => NewChatSheet(),
    );
  }
}

class ChatTile extends StatelessWidget {
  final Chat chat;
  const ChatTile({Key? key, required this.chat}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isPrivate = chat.type == 'private';
    final title = isPrivate ? chat.otherUser?.name ?? 'Chat' : chat.title;
    final subtitle = isPrivate ? '@${chat.otherUser?.username}' : '${chat.type} · ${chat.participantsCount} members';
    final imageUrl = isPrivate
        ? chat.otherUser?.profilePicture != null
        ? ApiConstants.fileUri(chat.otherUser!.profilePicture!).toString()
        : null
        : null;

    return ListTile(
      leading: Hero(
        tag: 'chat_${chat.id}',
        child: CircleAvatar(
          backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
          backgroundColor: Colors.primaries[chat.id % Colors.primaries.length],
          child: imageUrl == null ? Text(title?[0] ?? 'C') : null,
        ),
      ),
      title: Text(title ?? 'Unknown'),
      subtitle: Text(subtitle),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              chatId: chat.id,
              title: title ?? 'Chat',
              isGroup: chat.type != 'private',
            ),
          ),
        );
      },
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.2);
  }
}

class NewChatSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 20),
          ListTile(
            leading: CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.person, color: Colors.white)),
            title: Text('New Private Chat'),
            onTap: () {
              Navigator.pop(context);
              _showUsersSheet(context);
            },
          ),
          ListTile(
            leading: CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.group, color: Colors.white)),
            title: Text('New Group'),
            onTap: () {
              Navigator.pop(context);
              _showCreateGroupDialog(context);
            },
          ),
          ListTile(
            leading: CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.campaign, color: Colors.white)),
            title: Text('New Channel'),
            onTap: () {
              Navigator.pop(context);
              _showCreateChannelDialog(context);
            },
          ),
        ],
      ),
    );
  }

  void _showUsersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) {
          return Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Select user', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 16),
                Expanded(
                  child: Consumer<UserProvider>(
                    builder: (context, up, _) {
                      if (up.users.isEmpty) {
                        up.loadUsers();
                        return Center(child: CircularProgressIndicator());
                      }
                      final currentUserId = ApiService().token; // not reliable
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: up.users.length,
                        separatorBuilder: (_, __) => Divider(),
                        itemBuilder: (_, i) {
                          final user = up.users[i];
                          if (user.id == ApiService().getUserId()) return SizedBox.shrink();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: user.profilePicture != null
                                  ? CachedNetworkImageProvider(ApiConstants.fileUri(user.profilePicture!).toString())
                                  : null,
                              child: user.profilePicture == null ? Text(user.name[0]) : null,
                            ),
                            title: Text(user.name),
                            subtitle: Text('@${user.username}'),
                            onTap: () async {
                              Navigator.pop(ctx); // close sheet
                              final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                              final res = await chatProvider.createPrivateChat(user.id);
                              final chatId = res['chat_id'];
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatDetailScreen(
                                    chatId: chatId,
                                    title: user.name,
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
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCreateGroupDialog(BuildContext context) async {
    final TextEditingController titleController = TextEditingController();
    return showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('New Group'),
          content: TextField(
            controller: titleController,
            decoration: InputDecoration(hintText: 'Group name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  Navigator.pop(ctx);
                  final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                  final res = await chatProvider.createGroup(titleController.text);
                  final chatId = res['chat_id'];
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatDetailScreen(
                        chatId: chatId,
                        title: titleController.text,
                        isGroup: true,
                      ),
                    ),
                  );
                }
              },
              child: Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateChannelDialog(BuildContext context) async {
    final TextEditingController titleController = TextEditingController();
    bool isPublic = true;
    return showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text('New Channel'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(hintText: 'Channel name'),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Public'),
                      Switch(
                        value: isPublic,
                        onChanged: (v) => setState(() => isPublic = v),
                      ),
                      Text(isPublic ? 'Yes' : 'No'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (titleController.text.isNotEmpty) {
                      Navigator.pop(ctx);
                      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                      final res = await chatProvider.createChannel(titleController.text, isPublic: isPublic);
                      final chatId = res['chat_id'];
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatDetailScreen(
                            chatId: chatId,
                            title: titleController.text,
                            isGroup: true,
                          ),
                        ),
                      );
                    }
                  },
                  child: Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ChatDetailScreen extends StatefulWidget {
  final int chatId;
  final String title;
  final bool isGroup;

  ChatDetailScreen({Key? key, required this.chatId, required this.title, this.isGroup = false}) : super(key: key);

  @override
  _ChatDetailScreenState createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;
  File? _selectedMedia;
  String? _mediaPreviewPath;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.loadMessages(widget.chatId, reset: true);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _selectedMedia == null) return;
    setState(() => _isSending = true);
    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      await chatProvider.sendMessage(
        widget.chatId,
        text: _messageController.text.trim().isNotEmpty ? _messageController.text.trim() : null,
        media: _selectedMedia,
      );
      _messageController.clear();
      _clearMedia();
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _clearMedia() {
    setState(() {
      _selectedMedia = null;
      _mediaPreviewPath = null;
    });
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedMedia = File(pickedFile.path);
        _mediaPreviewPath = pickedFile.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.getMessages(widget.chatId);
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Hero(
              tag: 'chat_${widget.chatId}',
              child: CircleAvatar(
                backgroundColor: Colors.primaries[widget.chatId % Colors.primaries.length],
                child: Text(widget.title[0]),
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: TextStyle(fontSize: 16)),
                if (widget.isGroup)
                  Text('Group', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: Icon(Icons.info),
              onPressed: () {
                // navigate to group info
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty && chatProvider.isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
              reverse: true,
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (ctx, index) {
                final message = messages[index];
                final isMe = message.senderId == auth.currentUser?.id;
                return MessageBubble(
                  message: message,
                  isMe: isMe,
                  onEdit: isMe ? (newText) => _editMessage(message.id, newText) : null,
                  onDelete: isMe ? () => _deleteMessage(message.id) : null,
                );
              },
            ),
          ),
          if (_mediaPreviewPath != null)
            Container(
              height: 100,
              padding: EdgeInsets.all(8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(_mediaPreviewPath!), width: 80, height: 80, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: _clearMedia,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(offset: Offset(0, -1), blurRadius: 3, color: Colors.grey.withOpacity(0.1)),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file),
                  onPressed: _pickMedia,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    maxLines: null,
                  ),
                ),
                SizedBox(width: 8),
                _isSending
                    ? Container(width: 40, height: 40, child: CircularProgressIndicator())
                    : CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editMessage(int messageId, String newText) async {
    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      await chatProvider.editMessage(widget.chatId, messageId, newText);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Edit failed')));
    }
  }

  Future<void> _deleteMessage(int messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete message'),
        content: Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        await chatProvider.deleteMessage(widget.chatId, messageId);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed')));
      }
    }
  }
}

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final Function(String)? onEdit;
  final VoidCallback? onDelete;

  const MessageBubble({Key? key, required this.message, required this.isMe, this.onEdit, this.onDelete}) : super(key: key);

  @override
  _MessageBubbleState createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showActions = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);
    final color = widget.isMe ? Colors.blue : Colors.grey[300];
    final textColor = widget.isMe ? Colors.white : Colors.black;

    return GestureDetector(
      onLongPress: () {
        setState(() => _showActions = !_showActions);
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!widget.isMe)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Text(widget.message.senderName, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ),
            Row(
              mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (_showActions && widget.onDelete != null)
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: widget.onDelete,
                  ),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: widget.isMe
                          ? borderRadius.copyWith(bottomRight: Radius.circular(4))
                          : borderRadius.copyWith(bottomLeft: Radius.circular(4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.message.mediaPath != null)
                          _buildMedia(),
                        if (widget.message.content != null)
                          Text(widget.message.content!, style: TextStyle(color: textColor)),
                        if (widget.message.editedAt != null)
                          Text('edited', style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7))),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormatter.format(widget.message.createdAt),
                              style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
                            ),
                            if (widget.isMe && widget.message.readCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(Icons.done_all, size: 14, color: textColor.withOpacity(0.7)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showActions && widget.onEdit != null)
                  IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: () => _showEditDialog(),
                  ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: Offset(0.8, 0.8));
  }

  Widget _buildMedia() {
    final isImage = widget.message.mediaType == 'image';
    final url = ApiConstants.fileUri(widget.message.mediaPath!);
    final thumbUrl = widget.message.thumbnailPath != null ? ApiConstants.thumbUri(widget.message.thumbnailPath!) : null;

    return GestureDetector(
      onTap: () {
        // open full screen image
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: thumbUrl?.toString() ?? url.toString(),
          placeholder: (_, __) => Container(width: 150, height: 150, color: Colors.grey[300]),
          errorWidget: (_, __, ___) => Icon(Icons.broken_image),
        ),
      ),
    );
  }

  void _showEditDialog() {
    final controller = TextEditingController(text: widget.message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit message'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                widget.onEdit?.call(controller.text);
                Navigator.pop(ctx);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser!;
    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Hero(
              tag: 'profile_${user.id}',
              child: CircleAvatar(
                radius: 60,
                backgroundImage: user.profilePicture != null
                    ? CachedNetworkImageProvider(ApiConstants.fileUri(user.profilePicture!).toString())
                    : null,
                child: user.profilePicture == null
                    ? Text(user.name[0], style: TextStyle(fontSize: 40))
                    : null,
              ),
            ),
            SizedBox(height: 20),
            Text(user.name, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text('@${user.username}', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            SizedBox(height: 8),
            if (user.bio != null && user.bio!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(user.bio!, textAlign: TextAlign.center),
              ),
            Divider(height: 40),
            ListTile(
              leading: Icon(Icons.phone),
              title: Text(user.phone ?? 'Not provided'),
            ),
            ListTile(
              leading: Icon(Icons.calendar_today),
              title: Text('Joined ${DateFormat.yMMMd().format(user.createdAt)}'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/edit-profile'),
              child: Text('Edit Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  File? _newProfilePicture;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser!;
    _nameController.text = user.name;
    _bioController.text = user.bio ?? '';
    _phoneController.text = user.phone ?? '';
    _usernameController.text = user.username;
    _profileImageUrl = user.profilePicture;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _newProfilePicture = File(picked.path);
        _profileImageUrl = picked.path;
      });
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await auth.updateProfile(
          name: _nameController.text.trim(),
          bio: _bioController.text.trim().isNotEmpty ? _bioController.text.trim() : null,
          phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
          username: _usernameController.text.trim() != auth.currentUser?.username ? _usernameController.text.trim() : null,
          profilePicture: _newProfilePicture,
        );
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: auth.isLoading ? null : _save,
            child: auth.isLoading ? CircularProgressIndicator() : Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: _newProfilePicture != null
                          ? FileImage(_newProfilePicture!)
                          : (_profileImageUrl != null
                          ? CachedNetworkImageProvider(ApiConstants.fileUri(_profileImageUrl!).toString())
                          : null),
                      child: _profileImageUrl == null && _newProfilePicture == null
                          ? Text(auth.currentUser?.name[0] ?? 'U', style: TextStyle(fontSize: 40))
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.camera_alt, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'Full Name'),
                validator: (v) => v!.isEmpty ? 'Name required' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Username'),
                validator: (v) => v!.isEmpty ? 'Username required' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(labelText: 'Phone'),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                maxLines: 3,
                decoration: InputDecoration(labelText: 'Bio', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}