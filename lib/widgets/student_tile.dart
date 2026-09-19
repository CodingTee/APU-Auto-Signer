import 'package:flutter/material.dart';
import '../models/student.dart';

/// A selectable student list item with checkbox-style selection.
class StudentTile extends StatelessWidget {
  final Student student;
  final bool isSelected;
  final VoidCallback onTap;

  const StudentTile({
    super.key,
    required this.student,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          child: Text(
            student.userId.substring(0, 2).toUpperCase(),
            style: TextStyle(
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          student.displayName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          student.userId,
          style: theme.textTheme.bodySmall,
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (_) => onTap(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        dense: true,
      ),
    );
  }
}
