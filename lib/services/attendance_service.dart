import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/sign_in_result.dart';
import '../models/student.dart';

/// Handles attendance sign-in via the APU Attendix GraphQL API.
class AttendanceService {
  static const String graphqlUrl = 'https://attendix.apu.edu.my/graphql';
  static const String apiKey = 'da2-npuptt5vqred3h4v35b2zk52zu';

  /// Default headers required by the Attendix API.
  static Map<String, String> _buildHeaders(String token) {
    return {
      'Accept': 'application/json,text/plain,*/*',
      'Content-Type': 'application/json',
      'Origin': 'https://apspace.apu.edu.my',
      'Referer': 'https://apspace.apu.edu.my/',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 12; HarmonyOS; NOH-AN00; HMSCore 6.16.2.342; GMSCore 0.3.15.250932) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.79 HuaweiBrowser/17.0.7.302 Mobile Safari/537.36',
      'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      'X-Amz-User-Agent': 'aws-amplify/2.0.7',
      'X-Api-Key': apiKey,
      'Authorization': 'Bearer $token',
    };
  }

  /// Sign in a single student with the given OTP.
  static Future<SignInResult> signIn(Student student, String otp) async {
    try {
      final payload = {
        'operationName': 'updateAttendance',
        'variables': {
          'otp': otp,
        },
        'query': r'''
mutation updateAttendance($otp: String!) {
  updateAttendance(otp: $otp) {
    id
    attendance
    classcode
    date
    startTime
    endTime
    classType
    __typename
  }
}
''',
      };

      final response = await http.post(
        Uri.parse(graphqlUrl),
        headers: _buildHeaders(student.token),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        return SignInResult(
          userId: student.userId,
          displayName: student.displayName,
          status: SignInStatus.tokenExpired,
          message: 'Token expired, please re-authorize this account.',
        );
      }

      if (response.statusCode != 200) {
        return SignInResult(
          userId: student.userId,
          displayName: student.displayName,
          status: SignInStatus.unknownError,
          message: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body);

      // Check for GraphQL errors
      if (data['errors'] != null) {
        final errors = data['errors'] as List;
        final firstError = errors.first;

        // NotFoundException means no class at this time or wrong OTP
        if (firstError['errorType'] == 'NotFoundException' ||
            (firstError['message'] as String?)?.contains('NotFoundException') == true) {
          return SignInResult(
            userId: student.userId,
            displayName: student.displayName,
            status: SignInStatus.noClass,
            message: 'No class found for this OTP at this time.',
          );
        }

        return SignInResult(
          userId: student.userId,
          displayName: student.displayName,
          status: SignInStatus.unknownError,
          message: firstError['message']?.toString() ?? 'Unknown GraphQL error',
        );
      }

      // Success - extract class info
      final attendanceData = data['data']?['updateAttendance'];
      return SignInResult(
        userId: student.userId,
        displayName: student.displayName,
        status: SignInStatus.success,
        message: 'Signed in successfully!',
        classInfo: attendanceData != null
            ? Map<String, dynamic>.from(attendanceData as Map)
            : null,
      );
    } catch (e) {
      if (e.toString().contains('Timeout') || e.toString().contains('SocketException')) {
        return SignInResult(
          userId: student.userId,
          displayName: student.displayName,
          status: SignInStatus.networkError,
          message: 'Network error: ${e.toString()}',
        );
      }
      return SignInResult(
        userId: student.userId,
        displayName: student.displayName,
        status: SignInStatus.unknownError,
        message: 'Error: ${e.toString()}',
      );
    }
  }

  /// Sign in multiple students with staggered (jittered) timing.
  ///
  /// Instead of firing every request at the exact same instant (which would
  /// burst all accounts from one IP at one timestamp), each account starts
  /// 500-2500 ms after the previous one. This avoids hammering the server and
  /// de-correlates the request timestamps. Results are returned in the same
  /// order as the input list.
  static final Random _jitter = Random();
  static Future<List<SignInResult>> batchSignIn(
    List<Student> students,
    String otp,
  ) async {
    final futures = <Future<SignInResult>>[];
    for (var i = 0; i < students.length; i++) {
      final startDelay = i == 0
          ? Duration.zero
          : Duration(milliseconds: 500 + _jitter.nextInt(2000));
      futures.add(
        Future.delayed(startDelay).then((_) => signIn(students[i], otp)),
      );
    }
    return Future.wait(futures);
  }
}
