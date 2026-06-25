import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('shows all bundled book formats on the home page', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Arkivio Reader'), findsOneWidget);
    expect(find.text('EPUB 示例书籍'), findsOneWidget);
    expect(find.text('MOBI 示例书籍'), findsOneWidget);
    expect(find.text('AZW3 示例书籍'), findsOneWidget);
    expect(find.text('PDF 示例书籍'), findsOneWidget);
  });
}
