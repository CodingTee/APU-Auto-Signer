import 'package:flutter/material.dart';
import '../models/sign_in_result.dart';

/// Dialog widget for displaying batch sign-in results.
class ResultDialog extends StatelessWidget {
  final List<SignInResult> results;

  const ResultDialog({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    final successCount = results.where((r) => r.isSuccess).length;
    final totalCount = results.length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            successCount == totalCount
                ? Icons.check_circle
                : successCount > 0
                    ? Icons.info
                    : Icons.error,
            color: successCount == totalCount
                ? Colors.green
                : successCount > 0
                    ? Colors.orange
                    : Colors.red,
          ),
          const SizedBox(width: 8),
          Text('$successCount/$totalCount Success'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, index) {
            final r = results[index];
            final color = r.isSuccess
                ? Colors.green
                : r.status == SignInStatus.tokenExpired
                    ? Colors.red
                    : Colors.orange;

            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: Icon(
                r.isSuccess ? Icons.check_circle : Icons.error_outline,
                color: color,
                size: 20,
              ),
              title: Text(
                r.displayName,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                r.message,
                style: TextStyle(fontSize: 12, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                if (r.classInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 36, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow('Class', r.classInfo!['classcode']),
                          _buildInfoRow('Date', r.classInfo!['date']),
                          _buildInfoRow('Start', r.classInfo!['startTime']),
                          _buildInfoRow('End', r.classInfo!['endTime']),
                          _buildInfoRow('Type', r.classInfo!['classType']),
                        ],
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(left: 36, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No class details available',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            TextSpan(text: '$value', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
