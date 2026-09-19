/// Result of a sign-in attempt for a single student.
class SignInResult {
  final String userId;
  final String displayName;
  final SignInStatus status;
  final String message;
  final Map<String, dynamic>? classInfo;

  SignInResult({
    required this.userId,
    required this.displayName,
    required this.status,
    required this.message,
    this.classInfo,
  });

  bool get isSuccess => status == SignInStatus.success;
}

enum SignInStatus {
  success,
  noClass,        // NotFoundException - no class at this time or wrong OTP
  tokenExpired,   // 401 Unauthorized
  networkError,   // Connection failed
  unknownError,   // Any other error
}
