import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;

// ------------------- Configuration -------------------
const String baseUrl = 'https://tweeter.runflare.run/';

// ------------------- Models -------------------
class UserProfile {
  final int id;
  final String username;
  final String email;
  final String? fullName;
  final String? bio;
  final String? avatarUrl;
  final bool isActive;
  final DateTime lastSeen;
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    this.fullName,
    this.bio,
    this.avatarUrl,
    required this.isActive,
    required this.lastSeen,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      fullName: json['full_name'],
      bio: json['bio'],
      avatarUrl: json['avatar_url'],
      isActive: json['is_active'],
      lastSeen: DateTime.parse(json['last_seen']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'full_name': fullName,
        'bio': bio,
        'avatar_url': avatarUrl,
        'is_active': isActive,
        'last_seen': lastSeen.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

class Token {
  final String accessToken;
  final String tokenType;

  Token({required this.accessToken, required this.tokenType});

  factory Token.fromJson(Map<String, dynamic> json) {
    return Token(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
    );
  }
}

class ConversationOut {
  final int id;
  final String type;
  final String? name;
  final int createdBy;
  final DateTime createdAt;
  final List<ConversationParticipant> participants;

  ConversationOut({
    required this.id,
    required this.type,
    this.name,
    required this.createdBy,
    required this.createdAt,
    required this.participants,
  });

  factory ConversationOut.fromJson(Map<String, dynamic> json) {
    return ConversationOut(
      id: json['id'],
      type: json['type'],
      name: json['name'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      participants: (json['participants'] as List)
          .map((p) => ConversationParticipant.fromJson(p))
          .toList(),
    );
  }
}

class ConversationParticipant {
  final int userId;
  final String role;

  ConversationParticipant({required this.userId, required this.role});

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) {
    return ConversationParticipant(
      userId: json['user_id'],
      role: json['role'],
    );
  }
}

class MessageOut {
  final int id;
  final int conversationId;
  final int senderId;
  final String content;
  final String messageType;
  final String? fileUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
  final int? replyToMessageId;
  final int? forwardedFromMessageId;
  final List<dynamic> reactions;
  final List<int> readBy;

  MessageOut({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.messageType,
    this.fileUrl,
    required this.createdAt,
    this.updatedAt,
    required this.isDeleted,
    this.replyToMessageId,
    this.forwardedFromMessageId,
    this.reactions = const [],
    this.readBy = const [],
  });

  factory MessageOut.fromJson(Map<String, dynamic> json) {
    return MessageOut(
      id: json['id'],
      conversationId: json['conversation_id'],
      senderId: json['sender_id'],
      content: json['content'],
      messageType: json['message_type'],
      fileUrl: json['file_url'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      isDeleted: json['is_deleted'],
      replyToMessageId: json['reply_to_message_id'],
      forwardedFromMessageId: json['forwarded_from_message_id'],
      reactions: json['reactions'] ?? [],
      readBy: (json['read_by'] as List?)?.cast<int>() ?? [],
    );
  }
}

class ReactionOut {
  final int id;
  final int messageId;
  final int userId;
  final String reaction;
  final DateTime createdAt;

  ReactionOut({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.reaction,
    required this.createdAt,
  });

  factory ReactionOut.fromJson(Map<String, dynamic> json) {
    return ReactionOut(
      id: json['id'],
      messageId: json['message_id'],
      userId: json['user_id'],
      reaction: json['reaction'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

// ------------------- API Service -------------------
class ApiService {
  final String baseUrl;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  String? _token;

  ApiService({required this.baseUrl});

  Future<Map<String, String>> _headers() async {
    _token ??= await storage.read(key: 'token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
    };
  }

  Future<Map<String, String>> _multipartHeaders() async {
    _token ??= await storage.read(key: 'token');
    return {
      'Authorization': 'Bearer $_token',
    };
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await storage.write(key: 'token', value: token);
  }

  Future<void> clearToken() async {
    _token = null;
    await storage.delete(key: 'token');
  }

  // Auth
  Future<UserProfile> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
    String? bio,
    String? avatarUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'full_name': fullName,
        'bio': bio,
        'avatar_url': avatarUrl,
      }),
    );
    if (response.statusCode == 201) {
      return UserProfile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Register failed: ${response.body}');
    }
  }

  Future<Token> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      final token = Token.fromJson(jsonDecode(response.body));
      await saveToken(token.accessToken);
      return token;
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  // Users
  Future<List<UserProfile>> listUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => UserProfile.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load users');
    }
  }

  Future<UserProfile> getUser(int userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return UserProfile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load user');
    }
  }

  Future<UserProfile> updateMyProfile({String? fullName, String? bio, String? avatarUrl}) async {
    final response = await http.put(
      Uri.parse('$baseUrl/users/me'),
      headers: await _headers(),
      body: jsonEncode({
        'full_name': fullName,
        'bio': bio,
        'avatar_url': avatarUrl,
      }),
    );
    if (response.statusCode == 200) {
      return UserProfile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update profile');
    }
  }

  Future<UserProfile> uploadAvatar(File file) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/users/me/avatar'),
    );
    request.headers.addAll(await _multipartHeaders());
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      return UserProfile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to upload avatar');
    }
  }

  // Conversations
  Future<List<ConversationOut>> listConversations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => ConversationOut.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load conversations');
    }
  }

  Future<ConversationOut> createConversation(String type, List<int> participantIds, {String? name}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations'),
      headers: await _headers(),
      body: jsonEncode({
        'type': type,
        'name': name,
        'participant_ids': participantIds,
      }),
    );
    if (response.statusCode == 200) {
      return ConversationOut.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create conversation');
    }
  }

  Future<ConversationOut> getConversation(int convId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/$convId'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return ConversationOut.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get conversation');
    }
  }

  Future<void> updateConversation(int convId, {String? name}) async {
    final response = await http.put(
      Uri.parse('$baseUrl/conversations/$convId?name=${name ?? ''}'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update conversation');
    }
  }

  Future<void> deleteConversation(int convId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/conversations/$convId'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete conversation');
    }
  }

  Future<void> addParticipant(int convId, int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$convId/participants?user_id=$userId'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to add participant');
    }
  }

  Future<void> removeParticipant(int convId, int userId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/conversations/$convId/participants/$userId'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to remove participant');
    }
  }

  // Messages
  Future<List<MessageOut>> listMessages(int convId, {int limit = 50, int offset = 0}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/$convId/messages?limit=$limit&offset=$offset'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => MessageOut.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load messages');
    }
  }

  Future<MessageOut> sendMessage(int convId, String content,
      {String messageType = 'text', int? replyToMessageId, int? forwardedFromMessageId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$convId/messages'),
      headers: await _headers(),
      body: jsonEncode({
        'content': content,
        'message_type': messageType,
        'reply_to_message_id': replyToMessageId,
        'forwarded_from_message_id': forwardedFromMessageId,
      }),
    );
    if (response.statusCode == 200) {
      return MessageOut.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to send message');
    }
  }

  Future<MessageOut> editMessage(int msgId, String content) async {
    final response = await http.put(
      Uri.parse('$baseUrl/messages/$msgId?content=${Uri.encodeComponent(content)}'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return MessageOut.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to edit message');
    }
  }

  Future<void> deleteMessage(int msgId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/messages/$msgId'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete message');
    }
  }

  Future<ReactionOut> addReaction(int msgId, String reaction) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages/$msgId/reactions'),
      headers: await _headers(),
      body: jsonEncode({'reaction': reaction}),
    );
    if (response.statusCode == 200) {
      return ReactionOut.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to add reaction');
    }
  }

  Future<void> removeReaction(int msgId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/messages/$msgId/reactions'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to remove reaction');
    }
  }

  Future<void> markAsRead(int msgId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages/$msgId/read'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to mark as read');
    }
  }

  // File upload
  Future<String> uploadFile(File file) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload'),
    );
    request.headers.addAll(await _multipartHeaders());
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      // Assume response returns {"file_url": "..."}
      final data = jsonDecode(response.body);
      return data['file_url'];
    } else {
      throw Exception('Failed to upload file');
    }
  }
}

// ------------------- Providers -------------------
class AuthProvider extends ChangeNotifier {
  final ApiService api;
  UserProfile? _currentUser;
  bool _isLoading = false;
  String? _error;

  AuthProvider({required this.api});

  UserProfile? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await api.login(username, password);
      // After login, fetch current user (we don't have /users/me, but we can get from /users? maybe)
      // For simplicity, we'll just set a placeholder. In real app, you might need /users/me.
      // We'll fetch the user list and find by username? Not ideal. Let's assume /users/me exists but it's not in spec. We'll use /users and find by username.
      final users = await api.listUsers();
      _currentUser = users.firstWhere((u) => u.username == username);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
    String? bio,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final user = await api.register(
        username: username,
        email: email,
        password: password,
        fullName: fullName,
        bio: bio,
      );
      // Auto login after register
      await api.login(username, password);
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await api.clearToken();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> updateProfile({String? fullName, String? bio, String? avatarUrl}) async {
    try {
      _currentUser = await api.updateMyProfile(fullName: fullName, bio: bio, avatarUrl: avatarUrl);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> uploadAvatar(File file) async {
    try {
      _currentUser = await api.uploadAvatar(file);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
}

class ConversationsProvider extends ChangeNotifier {
  final ApiService api;
  List<ConversationOut> _conversations = [];
  bool _isLoading = false;
  String? _error;

  ConversationsProvider({required this.api});

  List<ConversationOut> get conversations => _conversations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadConversations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _conversations = await api.listConversations();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createConversation(String type, List<int> participantIds, {String? name}) async {
    try {
      final newConv = await api.createConversation(type, participantIds, name: name);
      _conversations.add(newConv);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateConversation(int convId, {String? name}) async {
    try {
      await api.updateConversation(convId, name: name);
      final index = _conversations.indexWhere((c) => c.id == convId);
      if (index != -1) {
        _conversations[index] = await api.getConversation(convId);
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteConversation(int convId) async {
    try {
      await api.deleteConversation(convId);
      _conversations.removeWhere((c) => c.id == convId);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addParticipant(int convId, int userId) async {
    try {
      await api.addParticipant(convId, userId);
      final index = _conversations.indexWhere((c) => c.id == convId);
      if (index != -1) {
        _conversations[index] = await api.getConversation(convId);
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeParticipant(int convId, int userId) async {
    try {
      await api.removeParticipant(convId, userId);
      final index = _conversations.indexWhere((c) => c.id == convId);
      if (index != -1) {
        _conversations[index] = await api.getConversation(convId);
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }
}

class MessagesProvider extends ChangeNotifier {
  final ApiService api;
  final int conversationId;
  List<MessageOut> _messages = [];
  bool _isLoading = false;
  String? _error;

  MessagesProvider({required this.api, required this.conversationId});

  List<MessageOut> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadMessages({int limit = 50}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _messages = await api.listMessages(conversationId, limit: limit);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String content,
      {String messageType = 'text', int? replyToMessageId, int? forwardedFromMessageId}) async {
    try {
      final newMsg = await api.sendMessage(
        conversationId,
        content,
        messageType: messageType,
        replyToMessageId: replyToMessageId,
        forwardedFromMessageId: forwardedFromMessageId,
      );
      _messages.insert(0, newMsg); // Assuming newest first? Actually depends on API ordering. We'll insert at beginning if sorted descending.
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> editMessage(int msgId, String content) async {
    try {
      final edited = await api.editMessage(msgId, content);
      final index = _messages.indexWhere((m) => m.id == msgId);
      if (index != -1) {
        _messages[index] = edited;
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMessage(int msgId) async {
    try {
      await api.deleteMessage(msgId);
      _messages.removeWhere((m) => m.id == msgId);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addReaction(int msgId, String reaction) async {
    try {
      final reactionOut = await api.addReaction(msgId, reaction);
      // Update the message's reactions list
      final index = _messages.indexWhere((m) => m.id == msgId);
      if (index != -1) {
        // We need to refresh the message to get updated reactions, but we can also manually add.
        // For simplicity, we'll reload the message.
        final updatedMessages = await api.listMessages(conversationId, limit: 50);
        _messages = updatedMessages;
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeReaction(int msgId) async {
    try {
      await api.removeReaction(msgId);
      final index = _messages.indexWhere((m) => m.id == msgId);
      if (index != -1) {
        final updatedMessages = await api.listMessages(conversationId, limit: 50);
        _messages = updatedMessages;
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> markAsRead(int msgId) async {
    try {
      await api.markAsRead(msgId);
      // Update locally
      final index = _messages.indexWhere((m) => m.id == msgId);
      if (index != -1) {
        // We don't have the updated readBy list without refetching
        // For simplicity, we'll just ignore local update.
      }
    } catch (e) {
      rethrow;
    }
  }
}

// ------------------- Main App -------------------
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final ApiService api = ApiService(baseUrl: baseUrl);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(api: api)),
        ChangeNotifierProvider(create: (_) => ConversationsProvider(api: api)),
      ],
      child: MaterialApp(
        title: 'Messenger',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.currentUser != null) {
              return const HomeScreen();
            } else {
              return const LoginScreen();
            }
          },
        ),
      ),
    );
  }
}

// ------------------- Screens -------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      bool success;
      if (_isLogin) {
        success = await auth.login(_usernameController.text, _passwordController.text);
      } else {
        // Register uses more fields, for simplicity we'll use same username/password and dummy email
        success = await auth.register(
          username: _usernameController.text,
          email: '${_usernameController.text}@example.com',
          password: _passwordController.text,
        );
      }
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(auth.error ?? 'Error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade300, Colors.purple.shade300],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(_isLogin ? 20 : 40),
                        ),
                        child: const Icon(Icons.chat, color: Colors.white, size: 40),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isLogin ? 'Welcome Back' : 'Create Account',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: 'Username'),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      Consumer<AuthProvider>(
                        builder: (context, auth, child) {
                          return auth.isLoading
                              ? const CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _submit,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(_isLogin ? 'Login' : 'Register'),
                                );
                        },
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLogin = !_isLogin;
                          });
                        },
                        child: Text(_isLogin ? 'Need an account? Register' : 'Already have an account? Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ConversationsProvider>(context, listen: false).loadConversations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messenger'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Contacts'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              await auth.logout();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ConversationsList(),
          ContactsList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateConversationScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ConversationsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ConversationsProvider>(context);
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null) {
      return Center(child: Text('Error: ${provider.error}'));
    }
    if (provider.conversations.isEmpty) {
      return const Center(child: Text('No conversations'));
    }
    return ListView.builder(
      itemCount: provider.conversations.length,
      itemBuilder: (ctx, i) {
        final conv = provider.conversations[i];
        return ListTile(
          leading: CircleAvatar(
            child: Text(conv.name?[0] ?? '?'),
          ),
          title: Text(conv.name ?? 'Conversation ${conv.id}'),
          subtitle: Text('${conv.participants.length} participants'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(conversation: conv),
              ),
            );
          },
        );
      },
    );
  }
}

class ContactsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    return FutureBuilder<List<UserProfile>>(
      future: api.listUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final users = snapshot.data!;
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (ctx, i) {
            final user = users[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: user.avatarUrl != null
                    ? CachedNetworkImageProvider(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null ? Text(user.username[0]) : null,
              ),
              title: Text(user.fullName ?? user.username),
              subtitle: Text(user.email),
              onTap: () {
                // Start private conversation with this user
                _startPrivateChat(context, user);
              },
            );
          },
        );
      },
    );
  }

  void _startPrivateChat(BuildContext context, UserProfile user) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final conversationsProvider = Provider.of<ConversationsProvider>(context, listen: false);
    // Check if conversation already exists (in memory) - ideally we should check on server
    // For simplicity, create new private conversation
    try {
      await conversationsProvider.createConversation(
        'private',
        [auth.currentUser!.id, user.id],
      );
      // Navigate to that conversation
      // Reload conversations
      await conversationsProvider.loadConversations();
      // Optionally navigate to the new chat
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class CreateConversationScreen extends StatefulWidget {
  const CreateConversationScreen({super.key});

  @override
  State<CreateConversationScreen> createState() => _CreateConversationScreenState();
}

class _CreateConversationScreenState extends State<CreateConversationScreen> {
  final _nameController = TextEditingController();
  String _type = 'private'; // or 'group'
  List<int> _selectedUserIds = [];

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Conversation'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'private', child: Text('Private')),
                DropdownMenuItem(value: 'group', child: Text('Group')),
              ],
              onChanged: (v) => setState(() => _type = v!),
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            if (_type == 'group')
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Group Name'),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<UserProfile>>(
                future: auth.api.listUsers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final users = snapshot.data!.where((u) => u.id != auth.currentUser!.id).toList();
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (ctx, i) {
                      final user = users[i];
                      final isSelected = _selectedUserIds.contains(user.id);
                      return CheckboxListTile(
                        title: Text(user.fullName ?? user.username),
                        subtitle: Text(user.email),
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedUserIds.add(user.id);
                            } else {
                              _selectedUserIds.remove(user.id);
                            }
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: _selectedUserIds.isEmpty
                  ? null
                  : () async {
                      try {
                        final provider = Provider.of<ConversationsProvider>(context, listen: false);
                        await provider.createConversation(
                          _type,
                          _selectedUserIds,
                          name: _nameController.text.isNotEmpty ? _nameController.text : null,
                        );
                        Navigator.pop(context);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Hero(
              tag: 'avatar-${user.id}',
              child: CircleAvatar(
                radius: 50,
                backgroundImage: user.avatarUrl != null
                    ? CachedNetworkImageProvider(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null ? Text(user.username[0], style: const TextStyle(fontSize: 30)) : null,
              ),
            ),
            const SizedBox(height: 10),
            Text(user.fullName ?? user.username, style: const TextStyle(fontSize: 24)),
            Text(user.email),
            const SizedBox(height: 10),
            Text('Bio: ${user.bio ?? 'No bio'}'),
            const SizedBox(height: 10),
            Text('Last seen: ${DateFormat.yMMMd().add_jm().format(user.lastSeen)}'),
            const SizedBox(height: 10),
            Text('Member since: ${DateFormat.yMMMd().format(user.createdAt)}'),
          ],
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  File? _avatarFile;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser!;
    _fullNameController.text = user.fullName ?? '';
    _bioController.text = user.bio ?? '';
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _avatarFile = File(picked.path);
      });
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      try {
        if (_avatarFile != null) {
          await auth.uploadAvatar(_avatarFile!);
        }
        await auth.updateProfile(
          fullName: _fullNameController.text,
          bio: _bioController.text,
        );
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Hero(
                    tag: 'avatar-${user.id}',
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: _avatarFile != null
                          ? FileImage(_avatarFile!)
                          : (user.avatarUrl != null
                              ? CachedNetworkImageProvider(user.avatarUrl!)
                              : null),
                      child: (_avatarFile == null && user.avatarUrl == null)
                          ? Text(user.username[0], style: const TextStyle(fontSize: 30))
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(labelText: 'Bio'),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final ConversationOut conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late MessagesProvider _messagesProvider;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showEmoji = false;
  int? _replyToMessageId;
  int? _forwardFromMessageId;

  @override
  void initState() {
    super.initState();
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    _messagesProvider = MessagesProvider(
      api: api,
      conversationId: widget.conversation.id,
    );
    _messagesProvider.loadMessages();
  }

  void _sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      try {
        await _messagesProvider.sendMessage(
          _messageController.text,
          replyToMessageId: _replyToMessageId,
          forwardedFromMessageId: _forwardFromMessageId,
        );
        _messageController.clear();
        _replyToMessageId = null;
        _forwardFromMessageId = null;
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  void _toggleEmoji() {
    setState(() {
      _showEmoji = !_showEmoji;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final currentUserId = auth.currentUser!.id;

    return ChangeNotifierProvider.value(
      value: _messagesProvider,
      child: Consumer<MessagesProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.conversation.name ?? 'Chat'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info),
                  onPressed: () {
                    _showConversationInfo(context);
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          reverse: true,
                          controller: _scrollController,
                          itemCount: provider.messages.length,
                          itemBuilder: (ctx, i) {
                            final msg = provider.messages[i];
                            final isMe = msg.senderId == currentUserId;
                            return MessageBubble(
                              message: msg,
                              isMe: isMe,
                              onReply: () {
                                setState(() {
                                  _replyToMessageId = msg.id;
                                });
                              },
                              onForward: () {
                                setState(() {
                                  _forwardFromMessageId = msg.id;
                                });
                              },
                              onEdit: (newContent) async {
                                try {
                                  await provider.editMessage(msg.id, newContent);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Edit failed: $e')));
                                }
                              },
                              onDelete: () async {
                                try {
                                  await provider.deleteMessage(msg.id);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                                }
                              },
                              onReact: (emoji) async {
                                try {
                                  await provider.addReaction(msg.id, emoji);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reaction failed: $e')));
                                }
                              },
                            );
                          },
                        ),
                ),
                if (_replyToMessageId != null)
                  Container(
                    color: Colors.grey.shade200,
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Replying...',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _replyToMessageId = null),
                        ),
                      ],
                    ),
                  ),
                if (_forwardFromMessageId != null)
                  Container(
                    color: Colors.grey.shade200,
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Forwarding...',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _forwardFromMessageId = null),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.emoji_emotions),
                        onPressed: _toggleEmoji,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
                if (_showEmoji)
                  SizedBox(
                    height: 250,
                    child: emoji_picker.EmojiPicker(
                      onEmojiSelected: (category, emoji) {
                        _messageController.text += emoji.emoji;
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

  void _showConversationInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Conversation Info', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text('Type: ${widget.conversation.type}'),
              Text('Created by: ${widget.conversation.createdBy}'),
              Text('Participants:'),
              ...widget.conversation.participants.map((p) => Text('User ${p.userId} (${p.role})')),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  // Add participant
                },
                child: const Text('Add Participant'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------- Message Bubble Widget -------------------
class MessageBubble extends StatefulWidget {
  final MessageOut message;
  final bool isMe;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final Function(String) onEdit;
  final VoidCallback onDelete;
  final Function(String) onReact;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onReply,
    this.onForward,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with TickerProviderStateMixin {
  bool _showActions = false;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTap() {
    setState(() {
      _showActions = !_showActions;
    });
    if (_showActions) {
      _scaleController.forward();
    } else {
      _scaleController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!widget.isMe)
              CircleAvatar(
                radius: 16,
                // Could fetch sender avatar
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: widget.isMe ? Colors.blue : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.message.replyToMessageId != null)
                          Text('Replying to...', style: TextStyle(fontSize: 12, color: widget.isMe ? Colors.white70 : Colors.black54)),
                        if (widget.message.forwardedFromMessageId != null)
                          Text('Forwarded', style: TextStyle(fontSize: 12, color: widget.isMe ? Colors.white70 : Colors.black54)),
                        Text(
                          widget.message.content,
                          style: TextStyle(color: widget.isMe ? Colors.white : Colors.black),
                        ),
                        if (widget.message.fileUrl != null)
                          GestureDetector(
                            onTap: () {
                              // Open file
                            },
                            child: Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.attach_file, size: 16),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'File',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: widget.isMe ? Colors.white : Colors.black),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat.Hm().format(widget.message.createdAt),
                              style: TextStyle(fontSize: 10, color: widget.isMe ? Colors.white70 : Colors.black54),
                            ),
                            if (widget.isMe && widget.message.readBy.isNotEmpty)
                              const Icon(Icons.done_all, size: 12, color: Colors.blue),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.message.reactions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        children: widget.message.reactions.map((r) {
                          // r is a map? Actually reactions list is List<dynamic>, each might be an object.
                          // For simplicity, just show the first reaction string.
                          return Container(
                            margin: const EdgeInsets.only(right: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(r.toString()),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isMe)
              CircleAvatar(
                radius: 16,
                // Current user avatar
              ),
          ],
        ),
      ),
    );
  }
}