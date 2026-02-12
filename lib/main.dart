// ignore_for_file: unused_field, unused_element, prefer_const_constructors, duplicate_ignore, prefer_const_literals_to_create_immutables

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

// ------------------------------------------------------------
// Constants & API Service (pure Dart without http package)
// ------------------------------------------------------------
const String baseUrl = 'tweeter.runflare.run';  // Replace with your actual server if needed
const int basePort = 443; // HTTPS

class ApiService {
  final HttpClient _client = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) => true; // ← FIXED

  // Helper: make HTTPS request and parse JSON
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.https(baseUrl, path, queryParams);
      final request = await _client.openUrl(method, uri);
      request.headers.set('Content-Type', 'application/json');
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final statusCode = response.statusCode;

      // Debug: print raw response (optional, remove for production)
      // print('🌐 Status: $statusCode, Body: $responseBody');

      final dynamic data = jsonDecode(responseBody);
      if (statusCode >= 200 && statusCode < 300) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Unknown error'};
      }
    } catch (e) {
      // In case of non-JSON response or network error
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------- Users ----------
  Future<Map<String, dynamic>> register(String username, String name, String bio) =>
      _request('POST', '/register', body: {
        'username': username,
        'name': name,
        'bio': bio,
      });

  Future<Map<String, dynamic>> getUserProfile(String username) =>
      _request('GET', '/user/$username');

  // ---------- Tweets ----------
  Future<Map<String, dynamic>> postTweet({
    required String username,
    String subject = '',
    String content = '',
    int? parentId,
    int? retweetOf,
  }) =>
      _request('POST', '/tweet', body: {
        'username': username,
        'subject': subject,
        'content': content,
        'parent_id': parentId,
        'retweet_of': retweetOf,
      });

  Future<Map<String, dynamic>> getTweet(int tweetId) =>
      _request('GET', '/tweet/$tweetId');

  Future<Map<String, dynamic>> deleteTweet(int tweetId) =>
      _request('DELETE', '/tweet/$tweetId');

  // ---------- Likes ----------
  Future<Map<String, dynamic>> like(String username, int tweetId) =>
      _request('POST', '/like', body: {'username': username, 'tweet_id': tweetId});

  Future<Map<String, dynamic>> unlike(String username, int tweetId) =>
      _request('POST', '/unlike', body: {'username': username, 'tweet_id': tweetId});

  // ---------- Bookmarks ----------
  Future<Map<String, dynamic>> bookmark(String username, int tweetId) =>
      _request('POST', '/bookmark', body: {'username': username, 'tweet_id': tweetId});

  Future<Map<String, dynamic>> unbookmark(String username, int tweetId) =>
      _request('POST', '/unbookmark', body: {'username': username, 'tweet_id': tweetId});

  Future<Map<String, dynamic>> getBookmarks(String username) =>
      _request('GET', '/bookmarks/$username');

  // ---------- Follow ----------
  Future<Map<String, dynamic>> follow(String follower, String followee) =>
      _request('POST', '/follow', body: {'follower': follower, 'followee': followee});

  Future<Map<String, dynamic>> unfollow(String follower, String followee) =>
      _request('POST', '/unfollow', body: {'follower': follower, 'followee': followee});

  Future<Map<String, dynamic>> getFollowers(String username) =>
      _request('GET', '/followers/$username');

  Future<Map<String, dynamic>> getFollowing(String username) =>
      _request('GET', '/following/$username');

  // ---------- Feed ----------
  Future<Map<String, dynamic>> getFeed(String username,
          {int limit = 50, int offset = 0}) =>
      _request('GET', '/feed/$username',
          queryParams: {'limit': limit.toString(), 'offset': offset.toString()});

  // ---------- Hashtag ----------
  Future<Map<String, dynamic>> getHashtagFeed(String tag,
          {int limit = 50, int offset = 0}) =>
      _request('GET', '/hashtag/$tag',
          queryParams: {'limit': limit.toString(), 'offset': offset.toString()});

  Future<Map<String, dynamic>> getTrending() => _request('GET', '/trending');

  // ---------- Search ----------
  Future<Map<String, dynamic>> searchUsers(String query) =>
      _request('GET', '/search/users', queryParams: {'q': query});

  Future<Map<String, dynamic>> searchTweets(String query) =>
      _request('GET', '/search/tweets', queryParams: {'q': query});

  // ---------- Messages ----------
  Future<Map<String, dynamic>> sendMessage(
          String fromUser, String toUser, String content) =>
      _request('POST', '/message',
          body: {'from_user': fromUser, 'to_user': toUser, 'content': content});

  Future<Map<String, dynamic>> getConversation(String user, String other) =>
      _request('GET', '/messages/$user', queryParams: {'with': other});

  Future<Map<String, dynamic>> getInbox(String username) =>
      _request('GET', '/inbox/$username');
}

// ------------------------------------------------------------
// Global App State (simple ChangeNotifier + InheritedWidget)
// ------------------------------------------------------------
class AppState extends ChangeNotifier {
  String? _currentUsername;
  String? get currentUsername => _currentUsername;

  void login(String username) {
    _currentUsername = username;
    notifyListeners();
  }

  void logout() {
    _currentUsername = null;
    notifyListeners();
  }
}

class AppStateProvider extends InheritedWidget {
  final AppState state;
  const AppStateProvider({
    Key? key,
    required this.state,
    required Widget child,
  }) : super(key: key, child: child);

  static AppState of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppStateProvider>();
    return provider!.state;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => true;
}

// ------------------------------------------------------------
// Main App & Entry Point (FIXED: rebuild on state change)
// ------------------------------------------------------------
void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ApiService api = ApiService();
  final AppState appState = AppState();

  @override
  void initState() {
    super.initState();
    // Rebuild the whole app when appState notifies listeners (login/logout)
    appState.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateProvider(
      state: appState,
      child: MaterialApp(
        title: 'Tweeter • Flutter',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.blue,
          colorScheme: ColorScheme.dark(
            primary: Colors.blue,
            secondary: Colors.blueAccent,
            surface: Color(0xFF1E1E1E),
            background: Color(0xFF121212),
          ),
          scaffoldBackgroundColor: Color(0xFF121212),
          cardColor: Color(0xFF1E1E1E),
          appBarTheme: AppBarTheme(
            backgroundColor: Color(0xFF1A1A1A),
            elevation: 0,
            titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            iconTheme: IconThemeData(color: Colors.white),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Color(0xFF1A1A1A),
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
          ),
        ),
        home: AuthGate(),
      ),
    );
  }
}

// ------------------------------------------------------------
// Auth Gate (decide which screen to show)
// ------------------------------------------------------------
class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentUser = AppStateProvider.of(context).currentUsername;
    if (currentUser != null) {
      return MainScreen();
    }
    return LoginRegisterScreen();
  }
}

// ------------------------------------------------------------
// Login / Register Screen (with animations)
// ------------------------------------------------------------
class LoginRegisterScreen extends StatefulWidget {
  @override
  _LoginRegisterScreenState createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginUsernameController = TextEditingController();
  final _regUsernameController = TextEditingController();
  final _regNameController = TextEditingController();
  final _regBioController = TextEditingController();
  final ApiService _api = ApiService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsernameController.dispose();
    _regUsernameController.dispose();
    _regNameController.dispose();
    _regBioController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _loginUsernameController.text.trim();
    if (username.isEmpty) return;
    setState(() => _isLoading = true);
    final res = await _api.getUserProfile(username);
    setState(() => _isLoading = false);
    if (res['success'] == true) {
      AppStateProvider.of(context).login(username);
    } else {
      _showError('User not found');
    }
  }

  Future<void> _register() async {
    final username = _regUsernameController.text.trim();
    final name = _regNameController.text.trim();
    final bio = _regBioController.text.trim();
    if (username.isEmpty || name.isEmpty) {
      _showError('Username and name required');
      return;
    }
    setState(() => _isLoading = true);
    final res = await _api.register(username, name, bio);
    setState(() => _isLoading = false);
    if (res['success'] == true) {
      AppStateProvider.of(context).login(username);
    } else {
      _showError(res['error'] ?? 'Registration failed');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'app_logo',
                  child: Icon(
                    Icons.flutter_dash,
                    size: 80,
                    color: Colors.blueAccent,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Tweeter • Flutter',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                SizedBox(height: 40),
                Container(
                  decoration: BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.blue.withOpacity(0.3),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey,
                        tabs: [
                          Tab(text: 'Login'),
                          Tab(text: 'Register'),
                        ],
                      ),
                      SizedBox(
                        height: 300,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Login Tab
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _loginUsernameController,
                                    style: TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Username',
                                      prefixIcon: Icon(Icons.person),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                  ElevatedButton(
                                    onPressed: _isLoading ? null : _login,
                                    child: _isLoading
                                        ? CircularProgressIndicator(color: Colors.white)
                                        : Text('Login'),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: Size(double.infinity, 50),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Register Tab
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    TextField(
                                      controller: _regUsernameController,
                                      style: TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Username',
                                        prefixIcon: Icon(Icons.person),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    TextField(
                                      controller: _regNameController,
                                      style: TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Name',
                                        prefixIcon: Icon(Icons.badge),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    TextField(
                                      controller: _regBioController,
                                      style: TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Bio (optional)',
                                        prefixIcon: Icon(Icons.info),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    SizedBox(height: 20),
                                    ElevatedButton(
                                      onPressed: _isLoading ? null : _register,
                                      child: _isLoading
                                          ? CircularProgressIndicator(color: Colors.white)
                                          : Text('Register'),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(double.infinity, 50),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Main Screen (Bottom Navigation)
// ------------------------------------------------------------
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _selectedIndex = index),
        children: [
          FeedScreen(),
          ExploreScreen(),
          ComposeScreen(),
          ProfileScreen(username: AppStateProvider.of(context).currentUsername!),
          MessagesScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Compose'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.mail), label: 'Messages'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Feed Screen (with pull‑to‑refresh)
// ------------------------------------------------------------
class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService();
  late Future _feedFuture;
  String? currentUser;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    currentUser = AppStateProvider.of(context).currentUsername!;
    _refreshFeed();
  }

  void _refreshFeed() {
    setState(() {
      _feedFuture = _api.getFeed(currentUser!);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Home'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              AppStateProvider.of(context).logout();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshFeed(),
        child: FutureBuilder(
          future: _feedFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data['success'] != true) {
              return Center(child: Text('Could not load feed'));
            }
            final tweets = snapshot.data['data']['feed'] as List? ?? [];
            if (tweets.isEmpty) {
              return Center(child: Text('No tweets yet. Follow someone!'));
            }
            return ListView.builder(
              padding: EdgeInsets.all(8),
              itemCount: tweets.length,
              itemBuilder: (ctx, i) {
                return TweetCard(tweet: tweets[i]);
              },
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Tweet Card (with like, bookmark, retweet animations)
// ------------------------------------------------------------
class TweetCard extends StatefulWidget {
  final Map<String, dynamic> tweet;
  const TweetCard({Key? key, required this.tweet}) : super(key: key);

  @override
  _TweetCardState createState() => _TweetCardState();
}

class _TweetCardState extends State<TweetCard> {
  final ApiService _api = ApiService();
  late int likesCount;
  late int bookmarksCount;
  late int retweetsCount;
  bool _isLiking = false;
  bool _isBookmarking = false;
  String? currentUser;

  @override
  void initState() {
    super.initState();
    currentUser = AppStateProvider.of(context).currentUsername;
    likesCount = widget.tweet['likes_count'] ?? 0;
    bookmarksCount = widget.tweet['bookmarks_count'] ?? 0;
    retweetsCount = widget.tweet['retweets_count'] ?? 0;
  }

  Future<void> _toggleLike() async {
    if (_isLiking) return;
    setState(() => _isLiking = true);
    final res = await _api.like(currentUser!, widget.tweet['id']);
    setState(() => _isLiking = false);
    if (res['success'] == true) {
      setState(() => likesCount++);
    } else {
      // Already liked? try unlike
      final unlikeRes = await _api.unlike(currentUser!, widget.tweet['id']);
      if (unlikeRes['success'] == true) {
        setState(() => likesCount--);
      }
    }
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarking) return;
    setState(() => _isBookmarking = true);
    final res = await _api.bookmark(currentUser!, widget.tweet['id']);
    setState(() => _isBookmarking = false);
    if (res['success'] == true) {
      setState(() => bookmarksCount++);
    } else {
      final unbookmarkRes = await _api.unbookmark(currentUser!, widget.tweet['id']);
      if (unbookmarkRes['success'] == true) {
        setState(() => bookmarksCount--);
      }
    }
  }

  Future<void> _retweet() async {
    final res = await _api.postTweet(
      username: currentUser!,
      retweetOf: widget.tweet['id'],
    );
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retweeted!')),
      );
      setState(() => retweetsCount++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tweet = widget.tweet;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TweetDetailScreen(tweetId: tweet['id']),
          ),
        );
      },
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(tweet['username'][0].toUpperCase()),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tweet['username'],
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 4),
                            Text(
                              '@${tweet['username']}',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                        if (tweet['subject']?.isNotEmpty ?? false)
                          Text(
                            tweet['subject'],
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(tweet['content'] ?? ''),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildActionButton(
                    icon: Icons.favorite,
                    color: Colors.red,
                    count: likesCount,
                    onPressed: _toggleLike,
                    isLoading: _isLiking,
                  ),
                  _buildActionButton(
                    icon: Icons.repeat,
                    color: Colors.green,
                    count: retweetsCount,
                    onPressed: _retweet,
                    isLoading: false,
                  ),
                  _buildActionButton(
                    icon: Icons.bookmark,
                    color: Colors.blue,
                    count: bookmarksCount,
                    onPressed: _toggleBookmark,
                    isLoading: _isBookmarking,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required int count,
    required VoidCallback onPressed,
    required bool isLoading,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isLoading ? color.withOpacity(0.2) : Colors.transparent,
        ),
        child: Row(
          children: [
            isLoading
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, color: color, size: 20),
            SizedBox(width: 4),
            Text('$count', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Tweet Detail Screen (each tweet has its own page)
// ------------------------------------------------------------
class TweetDetailScreen extends StatefulWidget {
  final int tweetId;
  const TweetDetailScreen({Key? key, required this.tweetId}) : super(key: key);

  @override
  _TweetDetailScreenState createState() => _TweetDetailScreenState();
}

class _TweetDetailScreenState extends State<TweetDetailScreen> {
  final ApiService _api = ApiService();
  late Future _tweetFuture;
  String? currentUser;

  @override
  void initState() {
    super.initState();
    currentUser = AppStateProvider.of(context).currentUsername;
    _tweetFuture = _api.getTweet(widget.tweetId);
  }

  Future<void> _reply() async {
    final tweet = await _tweetFuture;
    if (tweet['success'] != true) return;
    final original = tweet['data'];
    // Navigate to ComposeScreen with parentId
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          parentId: widget.tweetId,
          initialContent: '@${original['username']} ',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tweet'),
      ),
      body: FutureBuilder(
        future: _tweetFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data['success'] != true) {
            return Center(child: Text('Tweet not found'));
          }
          final tweet = snapshot.data['data'];
          return SingleChildScrollView(
            child: Column(
              children: [
                TweetCard(tweet: tweet),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: _reply,
                    icon: Icon(Icons.reply),
                    label: Text('Reply'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ),
                // You could also load replies here using parent_id endpoint, but not implemented in API
              ],
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------
// Explore Screen (Search + Trending)
// ------------------------------------------------------------
class ExploreScreen extends StatefulWidget {
  @override
  _ExploreScreenState createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedTab = 0; // 0: Users, 1: Tweets, 2: Trending
  late Future _trendingFuture;
  Future? _searchFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _trendingFuture = _api.getTrending();
  }

  void _performSearch() {
    setState(() {
      _searchQuery = _searchController.text.trim();
      if (_searchQuery.isNotEmpty) {
        if (_selectedTab == 0) {
          _searchFuture = _api.searchUsers(_searchQuery);
        } else if (_selectedTab == 1) {
          _searchFuture = _api.searchTweets(_searchQuery);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Explore'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      filled: true,
                      fillColor: Color(0xFF2A2A2A),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                SizedBox(width: 8),
                ToggleButtons(
                  isSelected: [_selectedTab == 0, _selectedTab == 1, _selectedTab == 2],
                  onPressed: (index) {
                    setState(() => _selectedTab = index);
                    if (index == 2) {
                      _trendingFuture = _api.getTrending();
                    } else {
                      _performSearch();
                    }
                  },
                  children: [Icon(Icons.people), Icon(Icons.topic), Icon(Icons.trending_up)],
                  color: Colors.grey,
                  selectedColor: Colors.blue,
                  fillColor: Colors.blue.withOpacity(0.2),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _selectedTab == 2
          ? FutureBuilder(
              future: _trendingFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                final trending = snapshot.data?['data']?['trending'] as List? ?? [];
                return ListView.builder(
                  itemCount: trending.length,
                  itemBuilder: (ctx, i) {
                    final tag = trending[i];
                    return ListTile(
                      leading: Icon(Icons.tag, color: Colors.blue),
                      title: Text(tag['hashtag']),
                      trailing: Text('${tag['count']} tweets'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HashtagFeedScreen(tag: tag['hashtag']),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            )
          : _buildSearchResults(),
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return Center(child: Text('Enter a search term'));
    }
    return FutureBuilder(
      future: _searchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data['success'] != true) {
          return Center(child: Text('No results'));
        }
        if (_selectedTab == 0) {
          final users = snapshot.data['data']['users'] as List? ?? [];
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final u = users[i];
              return ListTile(
                leading: CircleAvatar(child: Text(u['name'][0])),
                title: Text(u['name']),
                subtitle: Text('@${u['username']}'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(username: u['username']),
                    ),
                  );
                },
              );
            },
          );
        } else {
          final tweets = snapshot.data['data']['tweets'] as List? ?? [];
          return ListView.builder(
            itemCount: tweets.length,
            itemBuilder: (ctx, i) => TweetCard(tweet: tweets[i]),
          );
        }
      },
    );
  }
}

// ------------------------------------------------------------
// Hashtag Feed
// ------------------------------------------------------------
class HashtagFeedScreen extends StatelessWidget {
  final String tag;
  const HashtagFeedScreen({Key? key, required this.tag}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ApiService _api = ApiService();
    return Scaffold(
      appBar: AppBar(title: Text(tag)),
      body: FutureBuilder(
        future: _api.getHashtagFeed(tag),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          final tweets = snapshot.data?['data']?['tweets'] as List? ?? [];
          return ListView.builder(
            itemCount: tweets.length,
            itemBuilder: (ctx, i) => TweetCard(tweet: tweets[i]),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------
// Compose Tweet Screen (with slide animation, now supports replies)
// ------------------------------------------------------------
class ComposeScreen extends StatefulWidget {
  final int? parentId;
  final String? initialSubject;
  final String? initialContent;

  const ComposeScreen({
    Key? key,
    this.parentId,
    this.initialSubject,
    this.initialContent,
  }) : super(key: key);

  @override
  _ComposeScreenState createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> with AutomaticKeepAliveClientMixin {
  late TextEditingController _subjectController;
  late TextEditingController _contentController;
  final ApiService _api = ApiService();
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _subjectController = TextEditingController(text: widget.initialSubject ?? '');
    _contentController = TextEditingController(text: widget.initialContent ?? '');
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _subjectController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _postTweet() async {
    if (_subjectController.text.isEmpty && _contentController.text.isEmpty) return;
    setState(() => _isPosting = true);
    final res = await _api.postTweet(
      username: AppStateProvider.of(context).currentUsername!,
      subject: _subjectController.text,
      content: _contentController.text,
      parentId: widget.parentId,
    );
    setState(() => _isPosting = false);
    if (res['success'] == true) {
      _subjectController.clear();
      _contentController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tweet posted!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.parentId != null ? 'Reply' : 'Compose Tweet')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (widget.parentId == null)
              TextField(
                controller: _subjectController,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                ),
              ),
            if (widget.parentId == null) SizedBox(height: 16),
            TextField(
              controller: _contentController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: widget.parentId != null ? 'Your reply' : 'What\'s happening?',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isPosting ? null : _postTweet,
              child: _isPosting
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text(widget.parentId != null ? 'Reply' : 'Tweet', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Profile Screen (with tabs: tweets, followers, following, bookmarks)
// ------------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  final String username;
  const ProfileScreen({Key? key, required this.username}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _api = ApiService();
  late Future _profileFuture;
  late Future _followersFuture;
  late Future _followingFuture;
  late Future _bookmarksFuture;
  String? currentUser;

  @override
  void initState() {
    super.initState();
    currentUser = AppStateProvider.of(context).currentUsername;
    _tabController = TabController(length: 4, vsync: this);
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _profileFuture = _api.getUserProfile(widget.username);
      _followersFuture = _api.getFollowers(widget.username);
      _followingFuture = _api.getFollowing(widget.username);
      if (widget.username == currentUser) {
        _bookmarksFuture = _api.getBookmarks(widget.username);
      }
    });
  }

  Future<void> _toggleFollow() async {
    if (currentUser == null || currentUser == widget.username) return;
    final res = await _api.follow(currentUser!, widget.username);
    if (res['success'] == true) {
      _refreshData();
    } else {
      // try unfollow
      final unfollowRes = await _api.unfollow(currentUser!, widget.username);
      if (unfollowRes['success'] == true) {
        _refreshData();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.username}'),
        actions: [
          if (currentUser != widget.username)
            FutureBuilder(
              future: _followersFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return SizedBox();
                final followers = snapshot.data?['data']?['followers'] as List? ?? [];
                final isFollowing = followers.contains(currentUser);
                return TextButton(
                  onPressed: _toggleFollow,
                  child: Text(isFollowing ? 'Unfollow' : 'Follow'),
                  style: TextButton.styleFrom(
                    foregroundColor: isFollowing ? Colors.red : Colors.blue,
                  ),
                );
              },
            ),
        ],
      ),
      body: FutureBuilder(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          final userData = snapshot.data?['data']?['user'] as Map? ?? {};
          final tweets = snapshot.data?['data']?['tweets'] as List? ?? [];
          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: Container(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.blue,
                              child: Text(
                                userData['name']?[0] ?? '?',
                                style: TextStyle(fontSize: 32),
                              ),
                            ),
                            SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userData['name'] ?? '',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  Text('@${widget.username}'),
                                  if (userData['bio'] != null && userData['bio'].isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(userData['bio']),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatColumn('Tweets', userData['tweets_count'] ?? tweets.length),
                            _buildStatColumn('Followers', userData['followers_count'] ?? 0),
                            _buildStatColumn('Following', userData['following_count'] ?? 0),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.blue,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.blue,
                      tabs: [
                        Tab(text: 'Tweets'),
                        Tab(text: 'Followers'),
                        Tab(text: 'Following'),
                        if (widget.username == currentUser) Tab(text: 'Bookmarks'),
                      ],
                    ),
                  ),
                  pinned: true,
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                // Tweets
                ListView.builder(
                  itemCount: tweets.length,
                  itemBuilder: (ctx, i) => TweetCard(tweet: tweets[i]),
                ),
                // Followers
                FutureBuilder(
                  future: _followersFuture,
                  builder: (context, snapshot) {
                    final followers = snapshot.data?['data']?['followers'] as List? ?? [];
                    return ListView.builder(
                      itemCount: followers.length,
                      itemBuilder: (ctx, i) => ListTile(
                        leading: CircleAvatar(child: Text(followers[i][0])),
                        title: Text('@${followers[i]}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(username: followers[i]),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                // Following
                FutureBuilder(
                  future: _followingFuture,
                  builder: (context, snapshot) {
                    final following = snapshot.data?['data']?['following'] as List? ?? [];
                    return ListView.builder(
                      itemCount: following.length,
                      itemBuilder: (ctx, i) => ListTile(
                        leading: CircleAvatar(child: Text(following[i][0])),
                        title: Text('@${following[i]}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(username: following[i]),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                // Bookmarks
                if (widget.username == currentUser)
                  FutureBuilder(
                    future: _bookmarksFuture,
                    builder: (context, snapshot) {
                      final bookmarks = snapshot.data?['data']?['bookmarks'] as List? ?? [];
                      return ListView.builder(
                        itemCount: bookmarks.length,
                        itemBuilder: (ctx, i) => TweetCard(tweet: bookmarks[i]),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatColumn(String label, int count) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey)),
      ],
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _SliverAppBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Theme.of(context).scaffoldBackgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _SliverAppBarDelegate old) => false;
}

// ------------------------------------------------------------
// Messages Screen (Inbox & Conversations)
// ------------------------------------------------------------
class MessagesScreen extends StatefulWidget {
  @override
  _MessagesScreenState createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService();
  late Future _inboxFuture;
  String? currentUser;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    currentUser = AppStateProvider.of(context).currentUsername!;
    _refreshInbox();
  }

  void _refreshInbox() {
    setState(() {
      _inboxFuture = _api.getInbox(currentUser!);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Messages'),
        actions: [
          IconButton(
            icon: Icon(Icons.create),
            onPressed: () => _showComposeDialog(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshInbox(),
        child: FutureBuilder(
          future: _inboxFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
            final messages = snapshot.data?['data']?['inbox'] as List? ?? [];
            if (messages.isEmpty) {
              return Center(child: Text('No messages yet'));
            }
            // Group by sender
            final Map<String, List<dynamic>> grouped = {};
            for (var msg in messages) {
              final sender = msg['from_user'];
              grouped.putIfAbsent(sender, () => []).add(msg);
            }
            final senders = grouped.keys.toList();
            return ListView.builder(
              itemCount: senders.length,
              itemBuilder: (ctx, i) {
                final sender = senders[i];
                final lastMsg = grouped[sender]!.first;
                return ListTile(
                  leading: CircleAvatar(child: Text(sender[0])),
                  title: Text('@$sender'),
                  subtitle: Text(lastMsg['content'], maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(
                    lastMsg['timestamp'].toString().substring(0, 10),
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConversationScreen(user: currentUser!, other: sender),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showComposeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: 'Recipient username'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final to = controller.text.trim();
              if (to.isEmpty) return;
              Navigator.pop(ctx);
              _showSendMessageDialog(to);
            },
            child: Text('Next'),
          ),
        ],
      ),
    );
  }

  void _showSendMessageDialog(String toUser) {
    final contentController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Message to @$toUser'),
        content: TextField(
          controller: contentController,
          maxLines: 3,
          decoration: InputDecoration(labelText: 'Content'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final content = contentController.text.trim();
              if (content.isEmpty) return;
              Navigator.pop(ctx);
              final res = await _api.sendMessage(currentUser!, toUser, content);
              if (res['success'] == true) {
                _refreshInbox();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Message sent'), backgroundColor: Colors.green),
                );
              }
            },
            child: Text('Send'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Conversation Screen
// ------------------------------------------------------------
class ConversationScreen extends StatefulWidget {
  final String user;
  final String other;
  const ConversationScreen({Key? key, required this.user, required this.other}) : super(key: key);

  @override
  _ConversationScreenState createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _msgController = TextEditingController();
  late Future _convoFuture;

  @override
  void initState() {
    super.initState();
    _refreshConvo();
  }

  void _refreshConvo() {
    setState(() {
      _convoFuture = _api.getConversation(widget.user, widget.other);
    });
  }

  Future<void> _sendMessage() async {
    final content = _msgController.text.trim();
    if (content.isEmpty) return;
    _msgController.clear();
    await _api.sendMessage(widget.user, widget.other, content);
    _refreshConvo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.other}')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder(
              future: _convoFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                final messages = snapshot.data?['data']?['messages'] as List? ?? [];
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) {
                    final msg = messages[messages.length - 1 - i];
                    final isMe = msg['from_user'] == widget.user;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue : Colors.grey[800],
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isMe ? Radius.zero : null,
                            bottomLeft: !isMe ? Radius.zero : null,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['content'],
                              style: TextStyle(color: Colors.white),
                            ),
                            SizedBox(height: 4),
                            Text(
                              msg['timestamp'].toString().substring(11, 16),
                              style: TextStyle(fontSize: 10, color: Colors.white70),
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
          Container(
            color: Color(0xFF1E1E1E),
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: 'Write a message...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      filled: true,
                      fillColor: Color(0xFF2A2A2A),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  mini: true,
                  child: Icon(Icons.send),
                  backgroundColor: Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}