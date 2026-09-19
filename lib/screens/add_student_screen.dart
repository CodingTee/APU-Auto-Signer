import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/student.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

/// Add a student by signing them in with their Microsoft account inside a
/// WebView. The flow:
///   1) WebView loads Microsoft OAuth (Chrome mobile User-Agent).
///   2) After login, auth.apu.edu.my/auth_token redirects to
///      apspace.apu.edu.my with an HS256 "exchange code".
///   3) On the FIRST onPageFinished of an apspace page, we inject JS that
///      fetches https://auth.apu.edu.my/token (credentials:'include' so the
///      session cookie travels) and returns {token, user_id}.
///   4) The token is persisted and used as `Authorization: Bearer` for
///      subsequent GraphQL attendance calls.
class AddStudentScreen extends StatefulWidget {
  final DatabaseService dbService;

  const AddStudentScreen({super.key, required this.dbService});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  late final WebViewController _controller;

  // MS authorization code captured from the auth_token redirect URL.
  String? _msCode;

  bool _exchanging = false;
  bool _completed = false;
  String _statusMessage = 'Loading login page...';
  Timer? _pendingFailTimer;
  bool _webViewError = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Use a real Chrome mobile User-Agent; Microsoft blocks embedded
      // WebView logins on the default Android WebView UA.
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'AuthBridge',
        onMessageReceived: (m) => _onExchangeResult(m.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            // Capture the MS code from the auth_token redirect so we can
            // use it as a fallback if the apspace page doesn't expose the
            // exchange code in its URL or cookies.
            try {
              final uri = Uri.parse(req.url);
              if (uri.host == 'auth.apu.edu.my' &&
                  uri.path == '/auth_token') {
                final code = uri.queryParameters['code'];
                if (code != null && code.isNotEmpty) {
                  _msCode = code;
                }
              }
            } catch (_) {}
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (_completed) return;
            if (url.contains('apspace.apu.edu.my')) {
              if (mounted) {
                setState(() => _statusMessage =
                    'Login complete, exchanging token...');
              }
            }
          },
          onPageFinished: (url) {
            if (_completed) return;
            // Fire /token exchange IMMEDIATELY on first apspace load --
            // the auth.apu.edu.my session cookie has a very short TTL.
            if (!url.contains('login.microsoftonline.com') &&
                url.contains('apspace.apu.edu.my')) {
              _exchange();
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (_completed) return;
            if (error.isForMainFrame != true) return;
            debugPrint(
                'APU WebView error: ${error.errorCode} ${error.description}');
            if (mounted) {
              setState(() {
                _webViewError = true;
                _statusMessage =
                    'Network error. Please reconnect and try again.';
              });
            }
          },
        ),
      );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Fresh attempt: clear prior WebView error state.
    _webViewError = false;
    // Wipe the native cookie jar first. Android's CookieManager is a
    // process-wide singleton, so cookies from a previous Add Student
    // attempt would otherwise be reused and cause 40143 on the new flow.
    await AuthService.clearWebViewCookies();
    if (!mounted) return;
    // Also nuke localStorage / sessionStorage of any leftover page.
    try {
      await _controller.loadRequest(Uri.parse('about:blank'));
      await _controller.runJavaScript(
        'try{localStorage.clear();sessionStorage.clear();}catch(e){}',
      );
    } catch (_) {}
    if (!mounted) return;
    await _controller
        .loadRequest(Uri.parse(AuthService.buildOAuthUrl()));
  }

  Future<void> _exchange() async {
    if (_completed || _exchanging || _webViewError) return;
    if (mounted) {
      setState(() {
        _exchanging = true;
        _statusMessage = 'Requesting token from server...';
      });
    }
    try {
      await _controller
          .runJavaScript(AuthService.buildTokenExchangeJs(_msCode));
    } catch (e) {
      _exchanging = false;
      _fail('Exchange script failed to run: $e');
    }
  }

  void _onExchangeResult(String message) {
    if (_completed) return;

    Map<String, dynamic> r;
    try {
      r = jsonDecode(message) as Map<String, dynamic>;
    } catch (e) {
      _fail('Parse result failed: $e\n$message');
      return;
    }

    if (r['error'] == 'no_code') {
      _fail(
        'No exchange code found in apspace URL or cookies.\n'
        'href=${r['href']}\n'
        'cookies=${r['cookies']}',
      );
      return;
    }
    if (r['error'] == 'fetch') {
      _fail('Fetch error: ${r['message']}');
      return;
    }

    final body = r['body'];
    final status = r['status'];
    if (body is! String) {
      _fail('Empty body (status=$status).');
      return;
    }

    // The body is the source of truth: if APU returned a usable
    // token+user_id pair, treat the exchange as a success even when
    // the HTTP status is 4xx (APU's /token endpoint commonly does
    // this for legitimate sessions). Only fall back to _fail when
    // the body carries no recognizable token/user_id.
    final info = AuthService.parseTokenResponse(body);
    if (info != null) {
      _save(info);
      return;
    }

    final preview = body.length > 500
        ? '${body.substring(0, 500)}...'
        : body;
    _fail('Token exchange failed (status=$status).\n$preview');
  }

  Future<void> _save(
      ({String userId, String displayName, String token}) info) async {
    try {
      final student = Student(
        userId: info.userId,
        token: info.token,
        displayName: info.displayName,
        createdAt: DateTime.now(),
      );
      final existing = await widget.dbService.getStudentByUserId(student.userId);
      if (existing != null) {
        await widget.dbService.updateToken(student.userId, student.token);
      } else {
        await widget.dbService.insertStudent(student);
      }
      if (!mounted) return;
      // Lock the success path BEFORE the nickname dialog so that no
      // subsequent /token exchanges (e.g. apspace reloading on a
      // stale session cookie) can fire _fail while the user is
      // still picking a nickname.
      _completed = true;
      _pendingFailTimer?.cancel();
      ScaffoldMessenger.of(context).clearSnackBars();
      if (mounted) {
        setState(() {
          _exchanging = false;
          _statusMessage = '';
        });
      }
      // Clear the apspace page so its own "Login Error" overlay (it
      // paints this whenever /token returns anything other than 200,
      // even when we have a perfectly good token) does not visually
      // clash with the success dialog we're about to show.
      try {
        await _controller.loadRequest(Uri.parse('about:blank'));
      } catch (_) {}
      // Ask for an optional nickname now that the account is saved.
      // Skipping keeps the default TP number (the user id).
      final nickname = await _promptNickname(info.userId);
      if (!mounted) return;
      if (nickname != null && nickname.isNotEmpty) {
        await widget.dbService.updateDisplayName(info.userId, nickname);
        if (!mounted) return;
      }
      final finalName =
          (nickname != null && nickname.isNotEmpty) ? nickname : info.userId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Student $finalName added!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      _fail('Save failed: $e');
    }
  }

  /// Ask the user for an optional nickname. Returns the trimmed name,
  /// or null if the user chose to skip (keep the default TP number).
  Future<String?> _promptNickname(String defaultName) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nickname',
            hintText: defaultName,
            hintStyle: const TextStyle(
              fontWeight: FontWeight.w300,
              color: Colors.black38,
            ),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _fail(String message) {
    if (!mounted) return;
    // Technical detail: visible in `adb logcat` for the developer.
    debugPrint('APU auth error: $message');
    setState(() {
      _exchanging = false;
      _statusMessage = _webViewError
          ? 'Network error. Please reconnect and try again.'
          : 'Could not sign in. Tap Retry.';
    });
    // If the WebView itself errored (e.g. ERR_INTERNET_DISCONNECTED),
    // the orange SnackBar would be redundant on top of the WebView's
    // built-in error page; the top status bar speaks instead.
    if (_webViewError) {
      _pendingFailTimer?.cancel();
      return;
    }
    // Delay the user-visible SnackBar so a transient failure that gets
    // auto-recovered (the next apspace onPageFinished re-fires
    // _exchange and succeeds) does not pop up unnecessarily.
    _pendingFailTimer?.cancel();
    _pendingFailTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _completed || _webViewError) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not sign in. Please try again.'),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              if (!_completed) _bootstrap();
            },
          ),
        ),
      );
    });
  }

  // Clear any visible SnackBars before popping so a failure notice from
  // this screen doesn't leak onto the home screen.
  void _close([bool result = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Student'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_statusMessage.isNotEmpty || _exchanging)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  child: Row(
                    children: [
                      if (_exchanging)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}