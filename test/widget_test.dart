// This is a basic Flutter widget test for the APU Auto Signer app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values shown match the expected values.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apu_auto_signer/screens/home_screen.dart';
import 'package:apu_auto_signer/services/database_service.dart';

void main() {
  testWidgets('HomeScreen renders empty state', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(dbService: DatabaseService()),
    ));

    // Verify that the empty state message is shown.
    expect(find.text('No Students Yet'), findsOneWidget);
  });
}
