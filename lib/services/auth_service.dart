import 'dart:convert';
import 'package:flutter/services.dart';

/// APU authentication: builds the Microsoft OAuth URL and exchanges the
/// post-login "exchange code" (HS256 JWT) for the student's Bearer token.
///
/// Architecture (reverse-engineered from the real APSpace Ionic web app):
///   1) WebView navigates to login.microsoftonline.com -> user signs in ->
///      Microsoft redirects to https://auth.apu.edu.my/auth_token?code=...
///   2) auth_token validates the MS code, mints an HS256 JWT (the
///      "exchange code"), and 302-redirects to apspace.apu.edu.my.
///   3) On the apspace page, JS immediately POSTs
///      https://auth.apu.edu.my/token with {code: <JWT>} and
///      credentials:'include' so the session cookie travels cross-origin.
///      The server (CORS-allowing apspace.apu.edu.my) returns
///      {token, user_id, data}. The token is a gzip+base64 blob used
///      verbatim as `Authorization: Bearer <token>` on GraphQL calls.
///
/// The /token POST only works from a page whose Origin is
/// apspace.apu.edu.my AND while the auth.apu.edu.my session cookie is
/// still fresh (very short TTL -- must be fired on the first onPageFinished
/// of the apspace page, no delays).
class AuthService {
  // APU Microsoft OAuth configuration
  static const String tenantId = '0fed03a3-402d-4633-a8cd-8b308822253e';
  static const String clientId = 'e96b418c-3f97-4b0f-b124-1cb3b347a06e';
  static const String redirectUri = 'https://auth.apu.edu.my/auth_token';
  static const String scopes =
      'Group.Read.All GroupMember.Read.All User.Read offline_access openid profile';
  static const String tokenExchangeUrl = 'https://auth.apu.edu.my/token';

  // Channel to the native android.webkit.CookieManager. Cookies live in a
  // singleton shared across every WebView in the app, so we must wipe them
  // between Add Student attempts -- otherwise the second student's auth
  // reuses the first student's expired auth.apu.edu.my session cookie and
  // /token returns 40143.
  static const MethodChannel _cookieChannel =
      MethodChannel('apu_auto_signer/cookies');

  /// Wipe the WebView's native cookie jar. Safe to call before the WebView
  /// is attached (CookieManager is a process-wide singleton).
  static Future<void> clearWebViewCookies() async {
    try {
      await _cookieChannel.invokeMethod('clearCookies');
    } on PlatformException {
      // Non-Android or channel not wired up -- nothing to do.
    } on MissingPluginException {
      // Same.
    } catch (_) {
      // Best-effort.
    }
  }

  /// Build the Microsoft OAuth authorization URL the WebView navigates to.
  static String buildOAuthUrl() {
    final state = jsonEncode({
      'origin': 'https://apspace.apu.edu.my',
      'endpoint': '/login',
      'app_id': 'apspace',
    });
    final encodedState = Uri.encodeComponent(state);
    final encodedRedirect = Uri.encodeComponent(redirectUri);

    return 'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize'
        '?client_id=$clientId'
        '&response_type=code'
        '&redirect_uri=$encodedRedirect'
        '&scope=${scopes.replaceAll(' ', '+')}'
        '&state=$encodedState';
  }

  /// JS that runs on the apspace.apu.edu.my page. It locates the exchange
  /// code (HS256 JWT) from the page URL or cookies, falls back to
  /// [fallbackCode] (the MS code captured from the auth_token redirect),
  /// then POSTs to /token with credentials:'include' so the
  /// auth.apu.edu.my session cookie travels cross-origin. The result is
  /// posted to the AuthBridge JavaScript channel as JSON.
  static String buildTokenExchangeJs(String? fallbackCode) {
    final fb = jsonEncode(fallbackCode ?? '');
    return '''
(function() {
  var fallback = $fb;
  var code = null;
  try {
    var u = new URL(location.href);
    code = u.searchParams.get('code') ||
           u.searchParams.get('jwt') ||
           u.searchParams.get('token');
  } catch(e) {}
  if (!code) {
    try {
      var parts = document.cookie.split(';');
      for (var i = 0; i < parts.length; i++) {
        var c = parts[i].trim();
        var eq = c.indexOf('=');
        if (eq < 0) continue;
        var name = c.substring(0, eq);
        if (name === 'code' || name === 'jwt' ||
            name === 'token' || name === 'exchange_code') {
          code = decodeURIComponent(c.substring(eq + 1));
          break;
        }
      }
    } catch(e) {}
  }
  if (!code && fallback) code = fallback;
  if (!code) {
    AuthBridge.postMessage(JSON.stringify({
      error: 'no_code',
      href: location.href,
      cookies: document.cookie
    }));
    return;
  }
  fetch('https://auth.apu.edu.my/token', {
    method: 'POST',
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*'
    },
    body: JSON.stringify({code: code})
  })
  .then(function(resp) {
    return resp.text().then(function(text) {
      AuthBridge.postMessage(JSON.stringify({
        status: resp.status,
        ok: resp.ok,
        body: text
      }));
    });
  })
  .catch(function(e) {
    AuthBridge.postMessage(JSON.stringify({
      error: 'fetch',
      message: String(e)
    }));
  });
})();
''';
  }

  /// Parse the /token response body. Returns the student record or null
  /// if the body is not a successful token response.
  static ({String userId, String displayName, String token})?
      parseTokenResponse(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final token = j['token'];
      final userId = j['user_id'];
      if (token is String &&
          userId is String &&
          token.isNotEmpty &&
          userId.isNotEmpty) {
        return (userId: userId, displayName: userId, token: token);
      }
    } catch (_) {}
    return null;
  }
}