import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:animations/animations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// -------------------- Import MessagingClient --------------------
// فرض می‌کنیم فایل MessagingClient.dart در کنار main.dart قرار دارد
import 'MessagingClient.dart';

// -------------------- انیمیشن‌های سفارشی --------------------
class CustomPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  CustomPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);
            return SlideTransition(position: offsetAnimation, child: child);
          },
        );
}

// -------------------- مدیریت وضعیت برنامه با Provider --------------------
class AppState extends ChangeNotifier {
  MessagingClient? _client;
  User? _currentUser;
  List<Chat> _chats = [];
  List<User> _users = [];
  Chat? _selectedChat;
  List<Message> _messages = [];
  bool _isLoading = false;
  String? _error;
  bool _isSocketConnected = false;
  Map<int, bool> _typingUsers = {}; // chatId -> true if someone typing

  // Getters
  MessagingClient? get client => _client;
  User? get currentUser => _currentUser;
  List<Chat> get chats => _chats;
  List<User> get users => _users;
  Chat? get selectedChat => _selectedChat;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSocketConnected => _isSocketConnected;
  Map<int, bool> get typingUsers => _typingUsers;

  // Setters with notify
  void setClient(MessagingClient client) {
    _client = client;
    _setupSocketListeners();
    notifyListeners();
  }

  void setCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  void setChats(List<Chat> chats) {
    _chats = chats;
    notifyListeners();
  }

  void setUsers(List<User> users) {
    _users = users;
    notifyListeners();
  }

  void setSelectedChat(Chat? chat) {
    _selectedChat = chat;
    if (chat != null) {
      _loadMessages(chat.id);
    } else {
      _messages = [];
    }
    notifyListeners();
  }

  void setMessages(List<Message> messages) {
    _messages = messages;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void setSocketConnected(bool connected) {
    _isSocketConnected = connected;
    notifyListeners();
  }

  void updateTyping(int chatId, bool isTyping) {
    _typingUsers[chatId] = isTyping;
    notifyListeners();
  }

  // متدهای عملیاتی با کلاینت
  Future<bool> login(String username, String password) async {
    setLoading(true);
    setError(null);
    try {
      final user = await _client!.login(username, password);
      _currentUser = user;
      _client!.connectSocket();
      await loadMyChats();
      await loadUsers();
      setLoading(false);
      return true;
    } catch (e) {
      setError(e.toString());
      setLoading(false);
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String password,
    String? firstName,
    String? lastName,
    String? phone,
    String? bio,
  }) async {
    setLoading(true);
    setError(null);
    try {
      final user = await _client!.register(
        username: username,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        bio: bio,
      );
      // بعد از ثبت‌نام باید لاگین کنیم
      return await login(username, password);
    } catch (e) {
      setError(e.toString());
      setLoading(false);
      return false;
    }
  }

  Future<void> loadMyChats() async {
    try {
      final chats = await _client!.getMyChats();
      _chats = chats;
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> loadUsers() async {
    try {
      final users = await _client!.getUsers();
      _users = users.where((u) => u.id != _currentUser?.id).toList();
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> _loadMessages(int chatId) async {
    try {
      final msgs = await _client!.getMessages(chatId, limit: 100);
      _messages = msgs;
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> sendMessage(int chatId, {String? text, File? mediaFile, int? replyTo}) async {
    try {
      final msg = await _client!.sendMessage(chatId, text: text, mediaFile: mediaFile, replyTo: replyTo);
      _messages.insert(0, msg); // آخرین پیام‌ها در بالای لیست (با توجه به sort)
      // اگر آخرین پیام چت مربوطه را به‌روز کنیم
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        _chats[chatIndex] = Chat(
          id: _chats[chatIndex].id,
          type: _chats[chatIndex].type,
          title: _chats[chatIndex].title,
          description: _chats[chatIndex].description,
          avatarUrl: _chats[chatIndex].avatarUrl,
          createdBy: _chats[chatIndex].createdBy,
          createdAt: _chats[chatIndex].createdAt,
          participants: _chats[chatIndex].participants,
          lastMessage: msg,
          isArchived: _chats[chatIndex].isArchived,
          otherUser: _chats[chatIndex].otherUser,
        );
        // مرتب‌سازی چت‌ها بر اساس آخرین پیام
        _chats.sort((a, b) {
          if (a.lastMessage == null) return 1;
          if (b.lastMessage == null) return -1;
          return b.lastMessage!.createdAt.compareTo(a.lastMessage!.createdAt);
        });
      }
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> editMessage(int messageId, String newText) async {
    try {
      final updated = await _client!.editMessage(messageId, newText);
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> deleteMessage(int messageId) async {
    try {
      await _client!.deleteMessage(messageId);
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> addReaction(int messageId, String emoji) async {
    try {
      final reactions = await _client!.addReaction(messageId, emoji);
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = Message(
          id: _messages[index].id,
          chatId: _messages[index].chatId,
          sender: _messages[index].sender,
          replyToId: _messages[index].replyToId,
          text: _messages[index].text,
          mediaUrl: _messages[index].mediaUrl,
          mediaType: _messages[index].mediaType,
          createdAt: _messages[index].createdAt,
          editedAt: _messages[index].editedAt,
          isDeleted: _messages[index].isDeleted,
          forwardFrom: _messages[index].forwardFrom,
          pinned: _messages[index].pinned,
          reactions: reactions,
          readBy: _messages[index].readBy,
        );
        notifyListeners();
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> removeReaction(int messageId) async {
    try {
      final reactions = await _client!.removeReaction(messageId);
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = Message(
          id: _messages[index].id,
          chatId: _messages[index].chatId,
          sender: _messages[index].sender,
          replyToId: _messages[index].replyToId,
          text: _messages[index].text,
          mediaUrl: _messages[index].mediaUrl,
          mediaType: _messages[index].mediaType,
          createdAt: _messages[index].createdAt,
          editedAt: _messages[index].editedAt,
          isDeleted: _messages[index].isDeleted,
          forwardFrom: _messages[index].forwardFrom,
          pinned: _messages[index].pinned,
          reactions: reactions,
          readBy: _messages[index].readBy,
        );
        notifyListeners();
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> pinMessage(int chatId, int messageId) async {
    try {
      final pinnedMsg = await _client!.pinMessage(chatId, messageId);
      // بروزرسانی وضعیت pinned در لیست پیام‌ها
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].id == messageId) {
          _messages[i] = pinnedMsg;
        } else if (_messages[i].pinned) {
          // اگر پیام قبلی pinned بوده، unpin می‌شود
          _messages[i] = Message(
            id: _messages[i].id,
            chatId: _messages[i].chatId,
            sender: _messages[i].sender,
            replyToId: _messages[i].replyToId,
            text: _messages[i].text,
            mediaUrl: _messages[i].mediaUrl,
            mediaType: _messages[i].mediaType,
            createdAt: _messages[i].createdAt,
            editedAt: _messages[i].editedAt,
            isDeleted: _messages[i].isDeleted,
            forwardFrom: _messages[i].forwardFrom,
            pinned: false,
            reactions: _messages[i].reactions,
            readBy: _messages[i].readBy,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> unpinMessage(int chatId) async {
    try {
      await _client!.unpinMessage(chatId);
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].pinned) {
          _messages[i] = Message(
            id: _messages[i].id,
            chatId: _messages[i].chatId,
            sender: _messages[i].sender,
            replyToId: _messages[i].replyToId,
            text: _messages[i].text,
            mediaUrl: _messages[i].mediaUrl,
            mediaType: _messages[i].mediaType,
            createdAt: _messages[i].createdAt,
            editedAt: _messages[i].editedAt,
            isDeleted: _messages[i].isDeleted,
            forwardFrom: _messages[i].forwardFrom,
            pinned: false,
            reactions: _messages[i].reactions,
            readBy: _messages[i].readBy,
          );
          break;
        }
      }
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> forwardMessage(int messageId, List<int> chatIds) async {
    try {
      final forwarded = await _client!.forwardMessage(messageId, chatIds);
      // اگر در چت فعلی هستیم، پیام‌های فوروارد شده را نمایش ندهیم (ممکن است به چت‌های دیگر باشند)
      // برای سادگی، پیام‌های چت فعلی را دوباره بارگذاری می‌کنیم
      if (_selectedChat != null) {
        _loadMessages(_selectedChat!.id);
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> markAsRead(int messageId) async {
    try {
      await _client!.markAsRead(messageId);
    } catch (e) {
      // ignore
    }
  }

  void sendTyping(int chatId) {
    _client?.sendTyping(chatId);
  }

  void _setupSocketListeners() {
    _client!.onSocketEvent.listen((event) {
      switch (event.type) {
        case SocketEventType.newMessage:
          final msg = event.newMessage;
          if (msg != null) {
            _handleNewMessage(msg);
          }
          break;
        case SocketEventType.messageUpdated:
          final msg = event.messageUpdated;
          if (msg != null) {
            _handleMessageUpdated(msg);
          }
          break;
        case SocketEventType.messageDeleted:
          final msgId = event.messageDeleted;
          if (msgId != null) {
            _handleMessageDeleted(msgId);
          }
          break;
        case SocketEventType.reactionUpdated:
          final data = event.reactionUpdated;
          if (data != null) {
            _handleReactionUpdated(data);
          }
          break;
        case SocketEventType.messagePinned:
          final msg = event.messagePinned;
          if (msg != null) {
            _handleMessagePinned(msg);
          }
          break;
        case SocketEventType.messageUnpinned:
          final msgId = event.messageUnpinned;
          if (msgId != null) {
            _handleMessageUnpinned(msgId);
          }
          break;
        case SocketEventType.typing:
          final typing = event.typingIndicator;
          if (typing != null) {
            final chatId = typing['chat_id'] as int?;
            final isTyping = typing['is_typing'] as bool? ?? false;
            if (chatId != null) {
              updateTyping(chatId, isTyping);
            }
          }
          break;
        case SocketEventType.chatUpdated:
          // می‌توانید چت را به‌روز کنید
          break;
        default:
          break;
      }
    });

    _client!.onSocketEvent.listen((event) {
      // برای اتصال/قطع اتصال می‌توان از وضعیت خود سوکت استفاده کرد
    });
  }

  void _handleNewMessage(Message msg) {
    // اگر در همان چتی هستیم که پیام جدید آمده، به لیست اضافه کن
    if (_selectedChat != null && _selectedChat!.id == msg.chatId) {
      _messages.insert(0, msg);
      // علامت خواندن خودکار
      _client?.markAsRead(msg.id);
    }
    // به‌روزرسانی آخرین پیام در لیست چت‌ها
    final chatIndex = _chats.indexWhere((c) => c.id == msg.chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = Chat(
        id: _chats[chatIndex].id,
        type: _chats[chatIndex].type,
        title: _chats[chatIndex].title,
        description: _chats[chatIndex].description,
        avatarUrl: _chats[chatIndex].avatarUrl,
        createdBy: _chats[chatIndex].createdBy,
        createdAt: _chats[chatIndex].createdAt,
        participants: _chats[chatIndex].participants,
        lastMessage: msg,
        isArchived: _chats[chatIndex].isArchived,
        otherUser: _chats[chatIndex].otherUser,
      );
      _chats.sort((a, b) {
        if (a.lastMessage == null) return 1;
        if (b.lastMessage == null) return -1;
        return b.lastMessage!.createdAt.compareTo(a.lastMessage!.createdAt);
      });
    }
    notifyListeners();
  }

  void _handleMessageUpdated(Message msg) {
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index != -1) {
      _messages[index] = msg;
      notifyListeners();
    }
    // به‌روزرسانی آخرین پیام در چت‌ها (اگر آخرین پیام باشد)
    for (int i = 0; i < _chats.length; i++) {
      if (_chats[i].lastMessage?.id == msg.id) {
        _chats[i] = Chat(
          id: _chats[i].id,
          type: _chats[i].type,
          title: _chats[i].title,
          description: _chats[i].description,
          avatarUrl: _chats[i].avatarUrl,
          createdBy: _chats[i].createdBy,
          createdAt: _chats[i].createdAt,
          participants: _chats[i].participants,
          lastMessage: msg,
          isArchived: _chats[i].isArchived,
          otherUser: _chats[i].otherUser,
        );
        notifyListeners();
        break;
      }
    }
  }

  void _handleMessageDeleted(int msgId) {
    _messages.removeWhere((m) => m.id == msgId);
    notifyListeners();
    // در صورت نیاز آخرین پیام چت را به‌روزرسانی کنید
  }

  void _handleReactionUpdated(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    final reactions = (data['reactions'] as List?)?.map((e) => Reaction.fromJson(e as Map<String, dynamic>)).toList();
    if (messageId != null && reactions != null) {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = Message(
          id: _messages[index].id,
          chatId: _messages[index].chatId,
          sender: _messages[index].sender,
          replyToId: _messages[index].replyToId,
          text: _messages[index].text,
          mediaUrl: _messages[index].mediaUrl,
          mediaType: _messages[index].mediaType,
          createdAt: _messages[index].createdAt,
          editedAt: _messages[index].editedAt,
          isDeleted: _messages[index].isDeleted,
          forwardFrom: _messages[index].forwardFrom,
          pinned: _messages[index].pinned,
          reactions: reactions,
          readBy: _messages[index].readBy,
        );
        notifyListeners();
      }
    }
  }

  void _handleMessagePinned(Message msg) {
    // مشابه pinMessage
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].id == msg.id) {
        _messages[i] = msg;
      } else if (_messages[i].pinned) {
        _messages[i] = Message(
          id: _messages[i].id,
          chatId: _messages[i].chatId,
          sender: _messages[i].sender,
          replyToId: _messages[i].replyToId,
          text: _messages[i].text,
          mediaUrl: _messages[i].mediaUrl,
          mediaType: _messages[i].mediaType,
          createdAt: _messages[i].createdAt,
          editedAt: _messages[i].editedAt,
          isDeleted: _messages[i].isDeleted,
          forwardFrom: _messages[i].forwardFrom,
          pinned: false,
          reactions: _messages[i].reactions,
          readBy: _messages[i].readBy,
        );
      }
    }
    notifyListeners();
  }

  void _handleMessageUnpinned(int msgId) {
    final index = _messages.indexWhere((m) => m.id == msgId);
    if (index != -1) {
      _messages[index] = Message(
        id: _messages[index].id,
        chatId: _messages[index].chatId,
        sender: _messages[index].sender,
        replyToId: _messages[index].replyToId,
        text: _messages[index].text,
        mediaUrl: _messages[index].mediaUrl,
        mediaType: _messages[index].mediaType,
        createdAt: _messages[index].createdAt,
        editedAt: _messages[index].editedAt,
        isDeleted: _messages[index].isDeleted,
        forwardFrom: _messages[index].forwardFrom,
        pinned: false,
        reactions: _messages[index].reactions,
        readBy: _messages[index].readBy,
      );
      notifyListeners();
    }
  }

  void logout() {
    _client?.disconnectSocket();
    _client = null;
    _currentUser = null;
    _chats = [];
    _selectedChat = null;
    _messages = [];
    notifyListeners();
  }
}

// -------------------- صفحه ورود / ثبت‌نام --------------------
class AuthPage extends StatefulWidget {
  @override
  _AuthPageState createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeIn));
    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade800, Colors.purple.shade800],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Card(
                    elevation: 20,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: Image.asset(
                                'assets/logo.png', // در صورت نداشتن، می‌توان از Icon استفاده کرد
                                height: 100,
                                errorBuilder: (_, __, ___) => Icon(Icons.chat, size: 80, color: Colors.blue),
                              ),
                            ).animate().scale(delay: 100.ms).then().shake(),
                            SizedBox(height: 20),
                            Text(
                              _isLogin ? 'ورود' : 'ثبت‌نام',
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                            ).animate().fadeIn().slideX(),
                            SizedBox(height: 20),
                            TextFormField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: 'نام کاربری',
                                prefixIcon: Icon(Icons.person),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'لطفا نام کاربری را وارد کنید' : null,
                            ).animate().fadeIn(delay: 100.ms).slideX(),
                            SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'رمز عبور',
                                prefixIcon: Icon(Icons.lock),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'لطفا رمز عبور را وارد کنید' : null,
                            ).animate().fadeIn(delay: 200.ms).slideX(),
                            if (!_isLogin) ...[
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _firstNameController,
                                decoration: InputDecoration(
                                  labelText: 'نام',
                                  prefixIcon: Icon(Icons.badge),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                              ).animate().fadeIn(delay: 300.ms).slideX(),
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _lastNameController,
                                decoration: InputDecoration(
                                  labelText: 'نام خانوادگی',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                              ).animate().fadeIn(delay: 400.ms).slideX(),
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: 'تلفن',
                                  prefixIcon: Icon(Icons.phone),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                              ).animate().fadeIn(delay: 500.ms).slideX(),
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _bioController,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: 'بیوگرافی',
                                  prefixIcon: Icon(Icons.info),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                              ).animate().fadeIn(delay: 600.ms).slideX(),
                            ],
                            SizedBox(height: 24),
                            if (appState.isLoading)
                              CircularProgressIndicator()
                            else
                              ElevatedButton(
                                onPressed: () async {
                                  if (_formKey.currentState!.validate()) {
                                    bool success;
                                    if (_isLogin) {
                                      success = await appState.login(
                                        _usernameController.text,
                                        _passwordController.text,
                                      );
                                    } else {
                                      success = await appState.register(
                                        username: _usernameController.text,
                                        password: _passwordController.text,
                                        firstName: _firstNameController.text.isNotEmpty ? _firstNameController.text : null,
                                        lastName: _lastNameController.text.isNotEmpty ? _lastNameController.text : null,
                                        phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
                                        bio: _bioController.text.isNotEmpty ? _bioController.text : null,
                                      );
                                    }
                                    if (success && mounted) {
                                      // انتقال به صفحه اصلی
                                      Navigator.pushReplacement(
                                        context,
                                        CustomPageRoute(page: MainPage()),
                                      );
                                    } else if (appState.error != null && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(appState.error!), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  backgroundColor: Colors.blue.shade700,
                                ),
                                child: Text(_isLogin ? 'ورود' : 'ثبت‌نام', style: TextStyle(fontSize: 18)),
                              ).animate().fadeIn(delay: 700.ms).slideY(),
                            SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                });
                              },
                              child: Text(_isLogin ? 'ثبت‌نام نکرده‌اید؟ کلیک کنید' : 'قبلاً ثبت‌نام کرده‌اید؟ وارد شوید'),
                            ).animate().fadeIn(delay: 800.ms),
                          ],
                        ),
                      ),
                    ),
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

// -------------------- صفحه اصلی (لیست چت‌ها) --------------------
class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<Chat> _filteredChats = [];
  List<User> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _filteredChats = context.read<AppState>().chats;
    _filteredUsers = context.read<AppState>().users;
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filter() {
    final query = _searchController.text.toLowerCase();
    final appState = context.read<AppState>();
    setState(() {
      if (query.isEmpty) {
        _filteredChats = appState.chats;
        _filteredUsers = appState.users;
      } else {
        _filteredChats = appState.chats.where((c) {
          final title = c.title ?? c.otherUser?.username ?? '';
          return title.toLowerCase().contains(query);
        }).toList();
        _filteredUsers = appState.users.where((u) {
          return u.username.toLowerCase().contains(query) ||
              (u.firstName?.toLowerCase().contains(query) ?? false) ||
              (u.lastName?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    // به‌روزرسانی فیلترها در صورت تغییر لیست
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filter();
    });

    return Scaffold(
      drawer: _buildDrawer(context, appState),
      appBar: AppBar(
        title: Text('پیام‌رسان'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'چت‌ها', icon: Icon(Icons.chat)),
            Tab(text: 'کاربران', icon: Icon(Icons.people)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              // فوکوس روی سرچ
            },
          ),
          IconButton(
            icon: Icon(Icons.add_comment),
            onPressed: () {
              _showNewChatDialog(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'جستجو...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // لیست چت‌ها
                _buildChatsList(appState),
                // لیست کاربران
                _buildUsersList(appState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AppState appState) {
    return Drawer(
      child: Container(
        color: Colors.blue.shade50,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(appState.currentUser?.firstName ?? appState.currentUser?.username ?? 'کاربر'),
              accountEmail: Text(appState.currentUser?.phone ?? ''),
              currentAccountPicture: GestureDetector(
                onTap: () {
                  Navigator.push(context, CustomPageRoute(page: ProfilePage()));
                },
                child: CircleAvatar(
                  backgroundImage: appState.currentUser?.avatarUrl != null
                      ? CachedNetworkImageProvider(appState.currentUser!.avatarUrl!)
                      : null,
                  child: appState.currentUser?.avatarUrl == null ? Icon(Icons.person, size: 40) : null,
                ),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.blue, Colors.purple]),
              ),
            ),
            ListTile(
              leading: Icon(Icons.person),
              title: Text('پروفایل'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, CustomPageRoute(page: ProfilePage()));
              },
            ),
            ListTile(
              leading: Icon(Icons.chat),
              title: Text('چت‌های جدید'),
              onTap: () {
                Navigator.pop(context);
                _showNewChatDialog(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.archive),
              title: Text('آرشیو'),
              onTap: () {
                // TODO: نمایش چت‌های آرشیو شده
                Navigator.pop(context);
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('تنظیمات'),
              onTap: () {
                Navigator.pop(context);
                // TODO: صفحه تنظیمات
              },
            ),
            ListTile(
              leading: Icon(Icons.exit_to_app),
              title: Text('خروج'),
              onTap: () {
                appState.logout();
                Navigator.pushReplacement(context, CustomPageRoute(page: AuthPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsList(AppState appState) {
    if (_filteredChats.isEmpty) {
      return Center(child: Text('چتی وجود ندارد'));
    }
    return AnimationLimiter(
      child: ListView.builder(
        reverse: true,
        itemCount: _filteredChats.length,
        itemBuilder: (context, index) {
          final chat = _filteredChats[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: _buildChatTile(context, chat, appState),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatTile(BuildContext context, Chat chat, AppState appState) {
    final isTyping = appState.typingUsers[chat.id] ?? false;
    final title = chat.type == 'private'
        ? (chat.otherUser?.firstName != null ? '${chat.otherUser!.firstName} ${chat.otherUser!.lastName ?? ''}' : chat.otherUser?.username ?? '')
        : (chat.title ?? 'گروه');
    final avatarUrl = chat.type == 'private' ? chat.otherUser?.avatarUrl : chat.avatarUrl;
    final lastMsg = chat.lastMessage;
    String lastMsgText = '';
    if (lastMsg != null) {
      if (lastMsg.isDeleted) {
        lastMsgText = 'این پیام حذف شده است';
      } else if (lastMsg.mediaUrl != null) {
        lastMsgText = '📷 ${lastMsg.mediaType ?? 'رسانه'}';
      } else {
        lastMsgText = lastMsg.text ?? '';
      }
    }
    final timeStr = lastMsg != null ? DateFormat.Hm().format(lastMsg.createdAt.toLocal()) : '';

    return ListTile(
      leading: Stack(
        children: [
          Hero(
            tag: 'avatar_${chat.id}',
            child: CircleAvatar(
              backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
              child: avatarUrl == null ? Icon(Icons.group, size: 30) : null,
            ),
          ),
          if (chat.type == 'private' && (chat.otherUser?.isOnline ?? false))
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: isTyping
          ? Text('در حال تایپ...', style: TextStyle(color: Colors.green, fontStyle: FontStyle.italic))
          : Text(lastMsgText, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(timeStr, style: TextStyle(fontSize: 12, color: Colors.grey)),
          if (lastMsg != null && lastMsg.sender.id != appState.currentUser?.id && !lastMsg.readBy.contains(appState.currentUser?.id))
            Container(
              margin: EdgeInsets.only(top: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
            ),
        ],
      ),
      onTap: () async {
        appState.setSelectedChat(chat);
        await Navigator.push(context, CustomPageRoute(page: ChatPage(chat: chat)));
        appState.setSelectedChat(null);
        // بعد از بازگشت، لیست چت‌ها را به‌روزرسانی کن
        appState.loadMyChats();
      },
    );
  }

  Widget _buildUsersList(AppState appState) {
    if (_filteredUsers.isEmpty) {
      return Center(child: Text('کاربری یافت نشد'));
    }
    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: user.avatarUrl != null ? CachedNetworkImageProvider(user.avatarUrl!) : null,
            child: user.avatarUrl == null ? Icon(Icons.person) : null,
          ),
          title: Text(user.firstName != null ? '${user.firstName} ${user.lastName ?? ''}' : user.username),
          subtitle: Text(user.bio ?? ''),
          trailing: user.isOnline
              ? Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle))
              : null,
          onTap: () {
            _startPrivateChat(user.id);
          },
        );
      },
    );
  }

  void _showNewChatDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('شروع چت جدید'),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: Consumer<AppState>(
              builder: (context, appState, child) {
                return ListView.builder(
                  itemCount: appState.users.length,
                  itemBuilder: (context, index) {
                    final user = appState.users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user.avatarUrl != null ? CachedNetworkImageProvider(user.avatarUrl!) : null,
                      ),
                      title: Text(user.username),
                      subtitle: Text(user.firstName ?? ''),
                      onTap: () {
                        Navigator.pop(ctx);
                        _startPrivateChat(user.id);
                      },
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _startPrivateChat(int userId) async {
    final appState = context.read<AppState>();
    // چک کن آیا چت خصوصی وجود دارد؟
    final existingChat = appState.chats.firstWhere(
      (c) => c.type == 'private' && c.participants.any((p) => p.id == userId) && c.participants.any((p) => p.id == appState.currentUser?.id),
      orElse: () => null as Chat,
    );
    if (existingChat != null) {
      appState.setSelectedChat(existingChat);
      Navigator.push(context, CustomPageRoute(page: ChatPage(chat: existingChat)));
    } else {
      // ایجاد چت جدید
      try {
        final newChat = await appState.client!.createChat(
          type: 'private',
          participantIds: [userId],
        );
        await appState.loadMyChats();
        appState.setSelectedChat(newChat);
        Navigator.push(context, CustomPageRoute(page: ChatPage(chat: newChat)));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    }
  }
}

// -------------------- صفحه چت --------------------
class ChatPage extends StatefulWidget {
  final Chat chat;
  ChatPage({required this.chat});

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;
  File? _selectedMedia;
  int? _replyToId;
  Timer? _typingTimer;
  static const int typingDelay = 1000; // ms

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final appState = Provider.of<AppState>(context, listen: false);
    if (_messageController.text.isNotEmpty) {
      appState.sendTyping(widget.chat.id);
      _typingTimer?.cancel();
      _typingTimer = Timer(Duration(milliseconds: typingDelay), () {
        // بعد از تایپ نکردن، می‌توان ایندیکیتور را خاموش کرد (سرور خودکار هندل می‌کند)
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final messages = appState.messages;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Hero(
              tag: 'avatar_${widget.chat.id}',
              child: CircleAvatar(
                backgroundImage: widget.chat.type == 'private'
                    ? (widget.chat.otherUser?.avatarUrl != null ? CachedNetworkImageProvider(widget.chat.otherUser!.avatarUrl!) : null)
                    : (widget.chat.avatarUrl != null ? CachedNetworkImageProvider(widget.chat.avatarUrl!) : null),
                child: (widget.chat.type == 'private' && widget.chat.otherUser?.avatarUrl == null)
                    ? Icon(Icons.person)
                    : (widget.chat.avatarUrl == null ? Icon(Icons.group) : null),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.chat.type == 'private'
                        ? (widget.chat.otherUser?.firstName ?? widget.chat.otherUser?.username ?? '')
                        : (widget.chat.title ?? 'گروه'),
                    style: TextStyle(fontSize: 16),
                  ),
                  if (appState.typingUsers[widget.chat.id] == true)
                    Text('در حال تایپ...', style: TextStyle(fontSize: 12, color: Colors.green)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'search') {
                _showSearchDialog(context);
              } else if (value == 'info') {
                _showChatInfo(context);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'search', child: Text('جستجو در چت')),
              PopupMenuItem(value: 'info', child: Text('اطلاعات چت')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(child: Text('هنوز پیامی وجود ندارد'))
                : GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: AnimationLimiter(
                      child: ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          return AnimationConfiguration.staggeredList(
                            position: index,
                            duration: Duration(milliseconds: 400),
                            child: SlideAnimation(
                              verticalOffset: 30,
                              child: FadeInAnimation(
                                child: _buildMessageItem(context, msg, appState),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          if (_selectedMedia != null)
            Container(
              height: 80,
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: EdgeInsets.all(4),
                    child: Image.file(_selectedMedia!, width: 70, height: 70, fit: BoxFit.cover),
                  ),
                  Expanded(child: Text('فایل انتخاب شده')),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _selectedMedia = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          if (_replyToId != null)
            Container(
              padding: EdgeInsets.all(8),
              color: Colors.grey.shade200,
              child: Row(
                children: [
                  Icon(Icons.reply, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'پاسخ به پیام ${_replyToId}',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _replyToId = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          _buildMessageInput(appState),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BuildContext context, Message msg, AppState appState) {
    final isMe = msg.sender.id == appState.currentUser?.id;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe)
            CircleAvatar(
              radius: 16,
              backgroundImage: msg.sender.avatarUrl != null ? CachedNetworkImageProvider(msg.sender.avatarUrl!) : null,
              child: msg.sender.avatarUrl == null ? Icon(Icons.person, size: 16) : null,
            ),
          SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: isMe ? Radius.circular(16) : Radius.circular(4),
                  bottomRight: isMe ? Radius.circular(4) : Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      msg.sender.firstName ?? msg.sender.username,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  if (msg.replyToId != null)
                    Container(
                      margin: EdgeInsets.only(bottom: 4),
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('پاسخ به پیام', style: TextStyle(fontSize: 11)),
                    ),
                  if (msg.forwardFrom != null)
                    Text('فوروارد شده', style: TextStyle(fontSize: 11, color: Colors.purple)),
                  if (msg.mediaUrl != null)
                    GestureDetector(
                      onTap: () {
                        _showMediaDialog(msg.mediaUrl!);
                      },
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                            image: CachedNetworkImageProvider(msg.mediaUrl!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  if (msg.text != null && msg.text!.isNotEmpty)
                    Text(msg.text!),
                  if (msg.editedAt != null)
                    Text('ویرایش شده', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat.Hm().format(msg.createdAt.toLocal()),
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      if (msg.pinned)
                        Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.push_pin, size: 12, color: Colors.blue),
                        ),
                    ],
                  ),
                  if (msg.reactions.isNotEmpty)
                    Wrap(
                      children: msg.reactions.map((r) {
                        return Container(
                          margin: EdgeInsets.only(right: 4, top: 4),
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white70,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(r.emoji),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 8),
          if (isMe)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  _showEditDialog(msg);
                } else if (value == 'delete') {
                  await appState.deleteMessage(msg.id);
                } else if (value == 'pin') {
                  if (msg.pinned) {
                    await appState.unpinMessage(widget.chat.id);
                  } else {
                    await appState.pinMessage(widget.chat.id, msg.id);
                  }
                } else if (value == 'reply') {
                  setState(() {
                    _replyToId = msg.id;
                  });
                } else if (value == 'forward') {
                  _showForwardDialog(msg.id);
                }
              },
              icon: Icon(Icons.more_vert, size: 16),
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'reply', child: Text('پاسخ')),
                PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                PopupMenuItem(value: 'delete', child: Text('حذف')),
                PopupMenuItem(value: 'pin', child: Text(msg.pinned ? 'لغو پین' : 'پین')),
                PopupMenuItem(value: 'forward', child: Text('فوروارد')),
              ],
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'reply') {
                  setState(() {
                    _replyToId = msg.id;
                  });
                } else if (value == 'react') {
                  _showEmojiPicker(msg.id);
                }
              },
              icon: Icon(Icons.more_vert, size: 16),
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'reply', child: Text('پاسخ')),
                PopupMenuItem(value: 'react', child: Text('واکنش')),
              ],
            ),
        ],
      ),
    );
  }

  void _showEditDialog(Message msg) {
    final controller = TextEditingController(text: msg.text);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('ویرایش پیام'),
          content: TextField(controller: controller, maxLines: 3),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
            ElevatedButton(
              onPressed: () async {
                final appState = Provider.of<AppState>(context, listen: false);
                await appState.editMessage(msg.id, controller.text);
                Navigator.pop(ctx);
              },
              child: Text('ذخیره'),
            ),
          ],
        );
      },
    );
  }

  void _showEmojiPicker(int messageId) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          height: 300,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) {
              Navigator.pop(ctx);
              Provider.of<AppState>(context, listen: false).addReaction(messageId, emoji.emoji);
            },
          ),
        );
      },
    );
  }

  void _showForwardDialog(int messageId) {
    final appState = Provider.of<AppState>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('انتخاب چت برای فوروارد'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: appState.chats.length,
              itemBuilder: (context, index) {
                final chat = appState.chats[index];
                return ListTile(
                  title: Text(chat.title ?? 'چت'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await appState.forwardMessage(messageId, [chat.id]);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فوروارد شد')));
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showMediaDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: url),
          ),
        );
      },
    );
  }

  void _showSearchDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('جستجو در چت'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: 'عبارت مورد نظر'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
            ElevatedButton(
              onPressed: () async {
                final query = controller.text;
                Navigator.pop(ctx);
                final appState = Provider.of<AppState>(context, listen: false);
                try {
                  final results = await appState.client!.searchMessages(query, chatId: widget.chat.id);
                  _showSearchResults(results);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
                }
              },
              child: Text('جستجو'),
            ),
          ],
        );
      },
    );
  }

  void _showSearchResults(List<Message> results) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('نتایج جستجو'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final msg = results[index];
                return ListTile(
                  title: Text(msg.text ?? 'رسانه'),
                  subtitle: Text(DateFormat.yMd().add_jm().format(msg.createdAt.toLocal())),
                  onTap: () {
                    Navigator.pop(ctx);
                    // اسکرول به آن پیام (اینجا فقط نمایش)
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showChatInfo(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('اطلاعات چت', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Divider(),
              ListTile(
                leading: Icon(Icons.group),
                title: Text('تعداد شرکت‌کنندگان: ${widget.chat.participants.length}'),
              ),
              if (widget.chat.type != 'private')
                ListTile(
                  leading: Icon(Icons.admin_panel_settings),
                  title: Text('ساخته شده توسط: ${widget.chat.createdBy}'),
                ),
              // می‌توان لیست شرکت‌کنندگان را نمایش داد
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageInput(AppState appState) {
    return Container(
      padding: EdgeInsets.all(8),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file, color: Colors.blue),
            onPressed: _pickMedia,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'پیام خود را بنویسید...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send, color: Colors.blue),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  Future<void> _pickMedia() async {
    try {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('دسترسی به گالری داده نشد')));
        return;
      }
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _selectedMedia = File(picked.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در انتخاب تصویر')));
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedMedia == null) return;

    final appState = Provider.of<AppState>(context, listen: false);
    setState(() {
      _isSending = true;
    });

    try {
      await appState.sendMessage(
        widget.chat.id,
        text: text.isNotEmpty ? text : null,
        mediaFile: _selectedMedia,
        replyTo: _replyToId,
      );
      _messageController.clear();
      setState(() {
        _selectedMedia = null;
        _replyToId = null;
      });
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ارسال: $e')));
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }
}

// -------------------- صفحه پروفایل --------------------
class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _firstNameController.text = user?.firstName ?? '';
    _lastNameController.text = user?.lastName ?? '';
    _bioController.text = user?.bio ?? '';
    _phoneController.text = user?.phone ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text('پروفایل')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: user?.avatarUrl != null ? CachedNetworkImageProvider(user!.avatarUrl!) : null,
                    child: user?.avatarUrl == null ? Icon(Icons.person, size: 60) : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: IconButton(
                        icon: Icon(Icons.camera_alt, color: Colors.white),
                        onPressed: _pickAndUploadAvatar,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              TextFormField(
                controller: _firstNameController,
                decoration: InputDecoration(labelText: 'نام', border: OutlineInputBorder()),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: InputDecoration(labelText: 'نام خانوادگی', border: OutlineInputBorder()),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                maxLines: 3,
                decoration: InputDecoration(labelText: 'بیوگرافی', border: OutlineInputBorder()),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: 'تلفن', border: OutlineInputBorder()),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _updateProfile,
                child: Text('ذخیره تغییرات'),
                style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    final appState = Provider.of<AppState>(context, listen: false);
    try {
      final status = await Permission.photos.request();
      if (!status.isGranted) return;
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        appState.setLoading(true);
        final file = File(picked.path);
        final newUrl = await appState.client!.uploadAvatar(file);
        // به‌روزرسانی کاربر فعلی
        final updatedUser = User(
          id: appState.currentUser!.id,
          username: appState.currentUser!.username,
          firstName: appState.currentUser!.firstName,
          lastName: appState.currentUser!.lastName,
          bio: appState.currentUser!.bio,
          avatarUrl: newUrl,
          isOnline: appState.currentUser!.isOnline,
          lastSeen: appState.currentUser!.lastSeen,
          phone: appState.currentUser!.phone,
        );
        appState.setCurrentUser(updatedUser);
        appState.setLoading(false);
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  void _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      final appState = Provider.of<AppState>(context, listen: false);
      try {
        await appState.client!.updateUser(
          firstName: _firstNameController.text.isNotEmpty ? _firstNameController.text : null,
          lastName: _lastNameController.text.isNotEmpty ? _lastNameController.text : null,
          bio: _bioController.text.isNotEmpty ? _bioController.text : null,
          phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
        );
        // بارگذاری مجدد اطلاعات کاربر
        final updated = await appState.client!.getUser(appState.currentUser!.id);
        appState.setCurrentUser(updated);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('پروفایل به‌روزرسانی شد')));
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    }
  }
}

// -------------------- صفحه اصلی برنامه --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // درخواست دسترسی‌ها در ابتدا
  await Permission.notification.request();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final client = MessagingClient(baseUrl: 'https://tweeter.runflare.run');
        final state = AppState();
        state.setClient(client);
        // اگر توکن قبلی دارید می‌توانید از shared_preferences بازیابی کنید
        return state;
      },
      child: MaterialApp(
        title: 'پیام‌رسان',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Vazir', // در صورت تمایل فونت فارسی اضافه کنید
        ),
        home: Consumer<AppState>(
          builder: (context, appState, child) {
            if (appState.currentUser != null) {
              return MainPage();
            }
            return AuthPage();
          },
        ),
      ),
    );
  }
}