import 'package:flutter_test/flutter_test.dart';

import 'package:caspian_college_messenger/main.dart';
import 'package:caspian_college_messenger/services/chat_service.dart';
import 'package:caspian_college_messenger/services/auth_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final auth = AuthService();
    await tester.pumpWidget(MyApp(service: LocalChatService(), auth: auth));
  });
}
