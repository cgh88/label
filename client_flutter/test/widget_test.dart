import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_flutter/views/login_view.dart';

void main() {
  testWidgets('LoginView renders title and login form elements', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginView(
          onLoginSuccess: (username, role) {},
          toggleTheme: () {},
          themeMode: ThemeMode.light,
        ),
      ),
    );

    expect(find.text('SHELFLIFE LABEL SYSTEM'), findsOneWidget);
    expect(find.text('사용자 ID'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
  });
}
