import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Exception thrown when the API returns an error.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}

/// Exception thrown when WebSocket connection fails.
class SocketConnectionException implements Exception {
  final String message;
  SocketConnectionException(this.message);
  @override
  String toString() => 'SocketConnectionException: $message';
}

// ----------------------------------------------------------------------
// Models
// ----------------------------------------------------------------------

/// User model
class User {
  final int id;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? bio;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? phone; // only visible to self

  User({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    this.bio,
    this.avatarUrl,
    required this.isOnline,
    this.lastSeen,
    this.phone,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'bio': bio,
        'avatar': avatarUrl,
        'is_online': isOnline,
        'last_seen': lastSeen?.toIso8601String(),
        'phone': phone,
      };
}

/// Chat model
class Chat {
  final int id;
  final String type; // 'private', 'group', 'channel'
  final String? title;
  final String? description;
  final String? avatarUrl;
  final int createdBy;
  final DateTime createdAt;
  final List<User> participants;
  final Message? lastMessage;
  final bool isArchived;
  // extra for private chats
  final User? otherUser; // if type == 'private'

  Chat({
    required this.id,
    required this.type,
    this.title,
    this.description,
    this.avatarUrl,
    required this.createdBy,
    required this.createdAt,
    required this.participants,
    this.lastMessage,
    this.isArchived = false,
    this.otherUser,
  });

  factory Chat.fromJson(Map<String, dynamic> json, {int? currentUserId}) {
    final participants = (json['participants'] as List?)
            ?.map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    User? otherUser;
    if (json['type'] == 'private' && participants.length == 2 && currentUserId != null) {
      otherUser = participants.firstWhere((p) => p.id != currentUserId);
    }

    return Chat(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      avatarUrl: json['avatar'] as String?,
      createdBy: json['created_by'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      participants: participants,
      lastMessage: json['last_message'] != null
          ? Message.fromJson(json['last_message'] as Map<String, dynamic>)
          : null,
      isArchived: json['is_archived'] as bool? ?? false,
      otherUser: otherUser,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        'avatar': avatarUrl,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'participants': participants.map((u) => u.toJson()).toList(),
        'last_message': lastMessage?.toJson(),
        'is_archived': isArchived,
      };
}

/// Reaction model
class Reaction {
  final int userId;
  final String emoji;
  final DateTime createdAt;

  Reaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      userId: json['user_id'] as int,
      emoji: json['emoji'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'emoji': emoji,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Message model
class Message {
  final int id;
  final int chatId;
  final User sender;
  final int? replyToId;
  final String? text;
  final String? mediaUrl;
  final String? mediaType; // 'image', 'video', 'audio', 'file'
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isDeleted;
  final int? forwardFrom;
  final bool pinned;
  final List<Reaction> reactions;
  final List<int> readBy; // list of user ids

  Message({
    required this.id,
    required this.chatId,
    required this.sender,
    this.replyToId,
    this.text,
    this.mediaUrl,
    this.mediaType,
    required this.createdAt,
    this.editedAt,
    required this.isDeleted,
    this.forwardFrom,
    required this.pinned,
    required this.reactions,
    required this.readBy,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as int,
      chatId: json['chat_id'] as int,
      sender: User.fromJson(json['sender'] as Map<String, dynamic>),
      replyToId: json['reply_to'] as int?,
      text: json['text'] as String?,
      mediaUrl: json['media'] as String?,
      mediaType: json['media_type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at'] as String)
          : null,
      isDeleted: json['is_deleted'] as bool? ?? false,
      forwardFrom: json['forward_from'] as int?,
      pinned: json['pinned'] as bool? ?? false,
      reactions: (json['reactions'] as List?)
              ?.map((r) => Reaction.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      readBy: (json['read_by'] as List?)?.map((e) => e as int).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_id': chatId,
        'sender': sender.toJson(),
        'reply_to': replyToId,
        'text': text,
        'media': mediaUrl,
        'media_type': mediaType,
        'created_at': createdAt.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
        'is_deleted': isDeleted,
        'forward_from': forwardFrom,
        'pinned': pinned,
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'read_by': readBy,
      };
}

/// Type of socket events received from server
enum SocketEventType {
  newChat,
  chatUpdated,
  participantAdded,
  participantRemoved,
  removedFromChat,
  chatArchived,
  newMessage,
  messageUpdated,
  messageDeleted,
  readReceipt,
  reactionUpdated,
  messagePinned,
  messageUnpinned,
  userStatus,
  typing, // received typing indicator
}

/// Wrapper for socket events
class SocketEvent {
  final SocketEventType type;
  final Map<String, dynamic> rawData;
  SocketEvent(this.type, this.rawData);

  /// Convenience getters for each type
  Chat? get newChat => type == SocketEventType.newChat ? Chat.fromJson(rawData) : null;
  Chat? get chatUpdated => type == SocketEventType.chatUpdated ? Chat.fromJson(rawData) : null;
  Map<String, dynamic>? get participantAdded => type == SocketEventType.participantAdded ? rawData : null;
  Map<String, dynamic>? get participantRemoved => type == SocketEventType.participantRemoved ? rawData : null;
  Map<String, dynamic>? get removedFromChat => type == SocketEventType.removedFromChat ? rawData : null;
  int? get chatArchived => type == SocketEventType.chatArchived ? rawData['chat_id'] as int? : null;
  Message? get newMessage => type == SocketEventType.newMessage ? Message.fromJson(rawData['message'] as Map<String, dynamic>) : null;
  Message? get messageUpdated => type == SocketEventType.messageUpdated ? Message.fromJson(rawData['message'] as Map<String, dynamic>) : null;
  int? get messageDeleted => type == SocketEventType.messageDeleted ? rawData['message_id'] as int? : null;
  Map<String, dynamic>? get readReceipt => type == SocketEventType.readReceipt ? rawData : null;
  Map<String, dynamic>? get reactionUpdated => type == SocketEventType.reactionUpdated ? rawData : null;
  Message? get messagePinned => type == SocketEventType.messagePinned ? Message.fromJson(rawData['message'] as Map<String, dynamic>) : null;
  int? get messageUnpinned => type == SocketEventType.messageUnpinned ? rawData['message_id'] as int? : null;
  Map<String, dynamic>? get userStatus => type == SocketEventType.userStatus ? rawData : null;
  Map<String, dynamic>? get typingIndicator => type == SocketEventType.typing ? rawData : null;
}

// ----------------------------------------------------------------------
// Main Client
// ----------------------------------------------------------------------

/// A complete Dart client for the Telegram-like messaging API.
class MessagingClient {
  final String baseUrl; // e.g. "https://tweeter.runflare.run"
  String? _token;
  User? _currentUser;
  io.Socket? _socket;
  final _eventController = StreamController<SocketEvent>.broadcast();
  bool _autoReconnect = true;

  /// Creates a new client. Optionally provide an existing token.
  MessagingClient({required this.baseUrl, String? token}) : _token = token;

  /// The current authentication token (if any).
  String? get token => _token;

  /// The current authenticated user (populated after login/register).
  User? get currentUser => _currentUser;

  /// Stream of socket events.
  Stream<SocketEvent> get onSocketEvent => _eventController.stream;

  /// Whether the socket is connected.
  bool get isSocketConnected => _socket?.connected ?? false;

  // --------------------------------------------------------------------
  // Private HTTP helpers
  // --------------------------------------------------------------------
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool multipart = false,
    List<http.MultipartFile>? files,
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final requestHeaders = {
      'Content-Type': multipart ? 'multipart/form-data' : 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
      ...?headers,
    };

    http.Response response;
    if (multipart) {
      var request = http.MultipartRequest(method, url);
      request.headers.addAll(requestHeaders);
      if (body != null) {
        body.forEach((key, value) {
          if (value != null) request.fields[key] = value.toString();
        });
      }
      if (files != null) request.files.addAll(files);
      final streamedResponse = await request.send();
      response = await http.Response.fromStream(streamedResponse);
    } else {
      final client = http.Client();
      try {
        // ایجاد درخواست و اختصاص body فقط در صورت غیر null بودن
        final httpRequest = http.Request(method, url)
          ..headers.addAll(requestHeaders);
        if (body != null) {
          httpRequest.body = jsonEncode(body);
        }
        final streamedResponse = await client.send(httpRequest);
        response = await http.Response.fromStream(streamedResponse);
      } finally {
        client.close();
      }
    }

    final responseBody = response.body.isNotEmpty ? jsonDecode(response.body) : null;

    if (response.statusCode >= 400) {
      final errorMsg = responseBody is Map && responseBody.containsKey('error')
          ? responseBody['error'] as String
          : 'HTTP ${response.statusCode}';
      throw ApiException(errorMsg, response.statusCode);
    }

    return responseBody is Map<String, dynamic> ? responseBody : {};
  }

  // --------------------------------------------------------------------
  // Auth
  // --------------------------------------------------------------------

  /// Register a new user. Returns the created user and sets the token.
  Future<User> register({
    required String username,
    required String password,
    String? phone,
    String? firstName,
    String? lastName,
    String? bio,
  }) async {
    final data = await _request('POST', '/register', body: {
      'username': username,
      'password': password,
      if (phone != null) 'phone': phone,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (bio != null) 'bio': bio,
    });
    // Response: { "user": {...} }
    final userJson = data['user'] as Map<String, dynamic>;
    _currentUser = User.fromJson(userJson);
    // No token from register (should login after). So we don't set _token.
    return _currentUser!;
  }

  /// Login with username/password. Sets the token and current user.
  Future<User> login(String username, String password) async {
    final data = await _request('POST', '/login', body: {
      'username': username,
      'password': password,
    });
    _token = data['token'] as String;
    final userJson = data['user'] as Map<String, dynamic>;
    _currentUser = User.fromJson(userJson);
    return _currentUser!;
  }

  // --------------------------------------------------------------------
  // Users
  // --------------------------------------------------------------------

  /// Get all users (requires auth).
  Future<List<User>> getUsers() async {
    final data = await _request('GET', '/users');
    return (data as List).map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get a single user by id.
  Future<User> getUser(int userId) async {
    final data = await _request('GET', '/users/$userId');
    return User.fromJson(data);
  }

  /// Update current user's profile.
  Future<User> updateUser({
    String? firstName,
    String? lastName,
    String? bio,
    String? phone,
  }) async {
    if (_currentUser == null) throw ApiException('Not logged in');
    final data = await _request('PUT', '/users/${_currentUser!.id}', body: {
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (bio != null) 'bio': bio,
      if (phone != null) 'phone': phone,
    });
    _currentUser = User.fromJson(data);
    return _currentUser!;
  }

  /// Upload avatar for current user.
  Future<String> uploadAvatar(File imageFile) async {
    if (_currentUser == null) throw ApiException('Not logged in');
    final bytes = await imageFile.readAsBytes();
    final mimeType = lookupMimeType(imageFile.path) ?? 'application/octet-stream';
    final file = http.MultipartFile.fromBytes(
      'avatar',
      bytes,
      filename: imageFile.uri.pathSegments.last,
      contentType: MediaType.parse(mimeType),
    );
    final data = await _request(
      'POST',
      '/users/${_currentUser!.id}/avatar',
      multipart: true,
      files: [file],
    );
    // Response: { "avatar_url": "..." }
    final avatarUrl = data['avatar_url'] as String;
    // Update current user's avatar URL locally
    _currentUser = User(
      id: _currentUser!.id,
      username: _currentUser!.username,
      firstName: _currentUser!.firstName,
      lastName: _currentUser!.lastName,
      bio: _currentUser!.bio,
      avatarUrl: avatarUrl,
      isOnline: _currentUser!.isOnline,
      lastSeen: _currentUser!.lastSeen,
      phone: _currentUser!.phone,
    );
    return avatarUrl;
  }

  // --------------------------------------------------------------------
  // Chats
  // --------------------------------------------------------------------

  /// Get all chats for current user.
  Future<List<Chat>> getMyChats() async {
    final data = await _request('GET', '/chats');
    return (data as List)
        .map((e) => Chat.fromJson(e as Map<String, dynamic>, currentUserId: _currentUser?.id))
        .toList();
  }

  /// Create a new chat.
  /// For private chats, participantIds should contain exactly one other user.
  /// For groups/channels, provide title and optional participantIds.
  Future<Chat> createChat({
    required String type, // 'private', 'group', 'channel'
    String? title,
    String? description,
    List<int>? participantIds,
  }) async {
    final data = await _request('POST', '/chats', body: {
      'type': type,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (participantIds != null) 'participant_ids': participantIds,
    });
    return Chat.fromJson(data, currentUserId: _currentUser?.id);
  }

  /// Get a single chat by id.
  Future<Chat> getChat(int chatId) async {
    final data = await _request('GET', '/chats/$chatId');
    return Chat.fromJson(data, currentUserId: _currentUser?.id);
  }

  /// Update chat (title/description). Requires admin for groups/channels.
  Future<Chat> updateChat(int chatId, {String? title, String? description}) async {
    final data = await _request('PUT', '/chats/$chatId', body: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
    });
    return Chat.fromJson(data, currentUserId: _currentUser?.id);
  }

  /// Upload avatar for a chat (group/channel). Requires admin.
  Future<String> uploadChatAvatar(int chatId, File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final mimeType = lookupMimeType(imageFile.path) ?? 'application/octet-stream';
    final file = http.MultipartFile.fromBytes(
      'avatar',
      bytes,
      filename: imageFile.uri.pathSegments.last,
      contentType: MediaType.parse(mimeType),
    );
    final data = await _request(
      'POST',
      '/chats/$chatId/avatar',
      multipart: true,
      files: [file],
    );
    return data['avatar_url'] as String;
  }

  /// Add participant to a group/channel. Requires admin.
  Future<void> addParticipant(int chatId, int userId) async {
    await _request('POST', '/chats/$chatId/participants', body: {'user_id': userId});
  }

  /// Remove participant from a group/channel. Requires admin or self-removal.
  Future<void> removeParticipant(int chatId, int userId) async {
    await _request('DELETE', '/chats/$chatId/participants/$userId');
  }

  /// Archive a chat for current user.
  Future<void> archiveChat(int chatId) async {
    await _request('POST', '/chats/$chatId/archive');
  }

  // --------------------------------------------------------------------
  // Messages
  // --------------------------------------------------------------------

  /// Get messages from a chat (paginated).
  Future<List<Message>> getMessages(int chatId, {int limit = 50, int offset = 0}) async {
    final data = await _request('GET', '/chats/$chatId/messages?limit=$limit&offset=$offset');
    return (data as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Send a message (text + optional media).
  /// If mediaFile is provided, it will be uploaded as multipart.
  Future<Message> sendMessage(
    int chatId, {
    String? text,
    int? replyTo,
    File? mediaFile,
  }) async {
    if (text == null && mediaFile == null) {
      throw ArgumentError('Either text or mediaFile must be provided');
    }

    if (mediaFile != null) {
      final bytes = await mediaFile.readAsBytes();
      final mimeType = lookupMimeType(mediaFile.path) ?? 'application/octet-stream';
      final file = http.MultipartFile.fromBytes(
        'media',
        bytes,
        filename: mediaFile.uri.pathSegments.last,
        contentType: MediaType.parse(mimeType),
      );
      final data = await _request(
        'POST',
        '/chats/$chatId/messages',
        multipart: true,
        body: {
          if (text != null && text.isNotEmpty) 'text': text,
          if (replyTo != null) 'reply_to': replyTo.toString(),
        },
        files: [file],
      );
      return Message.fromJson(data);
    } else {
      final data = await _request('POST', '/chats/$chatId/messages', body: {
        if (text != null) 'text': text,
        if (replyTo != null) 'reply_to': replyTo,
      });
      return Message.fromJson(data);
    }
  }

  /// Edit a message (text only).
  Future<Message> editMessage(int messageId, String newText) async {
    final data = await _request('PUT', '/messages/$messageId', body: {'text': newText});
    return Message.fromJson(data);
  }

  /// Delete a message (soft delete).
  Future<void> deleteMessage(int messageId) async {
    await _request('DELETE', '/messages/$messageId');
  }

  /// Mark a message as read.
  Future<void> markAsRead(int messageId) async {
    await _request('POST', '/messages/$messageId/read');
  }

  /// Add or update a reaction to a message.
  Future<List<Reaction>> addReaction(int messageId, String emoji) async {
    final data = await _request('POST', '/messages/$messageId/reactions', body: {'emoji': emoji});
    // Response: { "reactions": [...] }
    return (data['reactions'] as List)
        .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Remove reaction from a message.
  Future<List<Reaction>> removeReaction(int messageId) async {
    final data = await _request('DELETE', '/messages/$messageId/reactions');
    return (data['reactions'] as List)
        .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Forward a message to other chats.
  Future<List<Message>> forwardMessage(int messageId, List<int> chatIds) async {
    final data = await _request('POST', '/messages/$messageId/forward', body: {'chat_ids': chatIds});
    // Response: { "forwarded": [...] }
    return (data['forwarded'] as List)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Pin a message in a chat. Only one pinned message per chat.
  Future<Message> pinMessage(int chatId, int messageId) async {
    final data = await _request('POST', '/chats/$chatId/pin/$messageId');
    return Message.fromJson(data);
  }

  /// Unpin the currently pinned message in a chat.
  Future<void> unpinMessage(int chatId) async {
    await _request('POST', '/chats/$chatId/unpin');
  }

  // --------------------------------------------------------------------
  // Search
  // --------------------------------------------------------------------

  /// Search messages across all chats (or optionally in a specific chat).
  Future<List<Message>> searchMessages(String query, {int? chatId}) async {
    final path = '/search/messages?q=${Uri.encodeQueryComponent(query)}${chatId != null ? '&chat_id=$chatId' : ''}';
    final data = await _request('GET', path);
    return (data as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --------------------------------------------------------------------
  // File download helpers
  // --------------------------------------------------------------------

  /// Download a file from a URL (e.g., mediaUrl, avatarUrl) and return bytes.
  Future<Uint8List> downloadFile(String url) async {
    final uri = Uri.parse(url);
    final request = http.Request('GET', uri);
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    final streamedResponse = await request.send();
    if (streamedResponse.statusCode >= 400) {
      throw ApiException('Failed to download file', streamedResponse.statusCode);
    }
    final response = await http.Response.fromStream(streamedResponse);
    return response.bodyBytes;
  }

  // --------------------------------------------------------------------
  // WebSocket (Socket.IO) management
  // --------------------------------------------------------------------

  /// Connect to the WebSocket server. Must be called after login (token is available).
  /// Automatically reconnects if connection drops.
  void connectSocket() {
    if (_token == null) {
      throw SocketConnectionException('Cannot connect socket without token. Login first.');
    }
    if (_socket != null && _socket!.connected) {
      return; // already connected
    }

    final socketUrl = baseUrl.replaceFirst(RegExp(r'^http'), 'ws'); // http->ws, https->wss
    _socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket']) // force websocket
          .setExtraHeaders({'Authorization': 'Bearer $_token'}) // not used by server? server uses query param
          .setQuery({'token': _token!}) // token as query parameter
          .enableReconnection() // auto reconnect (اصلاح شده)
          .build(),
    );

    _socket!.onConnect((_) {
      print('Socket connected');
      // Join user room automatically on server? server does that on connect.
    });

    _socket!.onDisconnect((_) => print('Socket disconnected'));
    _socket!.onError((err) => print('Socket error: $err'));

    // Register all event handlers
    _socket!.on('new_chat', _handleSocketEvent(SocketEventType.newChat));
    _socket!.on('chat_updated', _handleSocketEvent(SocketEventType.chatUpdated));
    _socket!.on('participant_added', _handleSocketEvent(SocketEventType.participantAdded));
    _socket!.on('participant_removed', _handleSocketEvent(SocketEventType.participantRemoved));
    _socket!.on('removed_from_chat', _handleSocketEvent(SocketEventType.removedFromChat));
    _socket!.on('chat_archived', _handleSocketEvent(SocketEventType.chatArchived));
    _socket!.on('new_message', _handleSocketEvent(SocketEventType.newMessage));
    _socket!.on('message_updated', _handleSocketEvent(SocketEventType.messageUpdated));
    _socket!.on('message_deleted', _handleSocketEvent(SocketEventType.messageDeleted));
    _socket!.on('read_receipt', _handleSocketEvent(SocketEventType.readReceipt));
    _socket!.on('reaction_updated', _handleSocketEvent(SocketEventType.reactionUpdated));
    _socket!.on('message_pinned', _handleSocketEvent(SocketEventType.messagePinned));
    _socket!.on('message_unpinned', _handleSocketEvent(SocketEventType.messageUnpinned));
    _socket!.on('user_status', _handleSocketEvent(SocketEventType.userStatus));
    _socket!.on('typing', _handleSocketEvent(SocketEventType.typing));
  }

  /// Disconnect WebSocket.
  void disconnectSocket() {
    _socket?.disconnect();
    _socket?.close();
    _socket = null;
  }

  /// Send typing indicator.
  void sendTyping(int chatId, {bool isTyping = true}) {
    if (!isSocketConnected) return;
    _socket!.emit('typing', {'chat_id': chatId, 'is_typing': isTyping});
  }

  /// Send read receipt for a message (via socket). Also can use markAsRead HTTP.
  void sendReadReceipt(int messageId) {
    if (!isSocketConnected) return;
    _socket!.emit('read', {'message_id': messageId});
  }

  // Helper to create a socket event handler
  Function(dynamic) _handleSocketEvent(SocketEventType type) {
    return (data) {
      if (data is Map) {
        _eventController.add(SocketEvent(type, Map<String, dynamic>.from(data)));
      }
    };
  }

  /// Dispose resources.
  void dispose() {
    disconnectSocket();
    _eventController.close();
  }
}