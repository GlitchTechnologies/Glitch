import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/widgets/selection_contrast_text.dart';

void main() {
  testWidgets('mouse selection shows contrast and keeps the original text',
      (tester) async {
    const label = 'Gray label';
    final labelKey = UniqueKey();
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectionContrastText(
                const Text(label, style: TextStyle(color: Colors.grey)),
                key: labelKey,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(labelKey));
    final beforeText = rect.centerLeft - const Offset(8, 0);
    final afterText = rect.centerRight + const Offset(8, 0);
    expect(find.byType(ColorFiltered), findsNothing);

    final mouse = await tester.startGesture(afterText, kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(rect.center);
    await tester.pump();
    await mouse.moveTo(beforeText);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(selected, label);
    expect(find.byType(ColorFiltered), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('extending selection backwards over an inline name keeps contrast',
      (tester) async {
    final name = UniqueKey();
    final message = UniqueKey();
    String? selected;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        textSelectionTheme: const TextSelectionThemeData(selectionColor: Colors.purple),
      ),
      home: Scaffold(
        body: SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectionContrastText(
                Text.rich(
                  TextSpan(
                    style: const TextStyle(color: Colors.grey),
                    children: [
                      TextSpan(text: 'Joined by '),
                      WidgetSpan(child: Text('Alice', key: name, style: const TextStyle(color: Colors.white))),
                      TextSpan(text: ' yesterday'),
                    ],
                  ),
                ),
                key: message,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final nameBounds = tester.getRect(find.byKey(name));
    final messageBounds = tester.getRect(find.byKey(message));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(message), matching: find.byType(RichText)).first,
    );
    expect(paragraph.selectionColor, Colors.purple);
    final mouse = await tester.startGesture(
      messageBounds.centerRight + const Offset(8, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(nameBounds.right + 8, nameBounds.center.dy));
    await tester.pump();
    expect(find.byType(ColorFiltered), findsOneWidget);

    await mouse.moveTo(Offset(nameBounds.left - 8, nameBounds.center.dy));
    await tester.pump();
    expect(find.byType(ColorFiltered), findsOneWidget);
    final clip = tester.widget<ClipPath>(find.byType(ClipPath)).clipper!;
    final painted = clip.getClip(messageBounds.size).getBounds();
    expect(painted.left, lessThan(nameBounds.left - messageBounds.left));
    expect(painted.right, greaterThan(nameBounds.right - messageBounds.left));
    expect(selected, contains('Alice'));
    expect(selected, contains('yesterday'));
    await mouse.up();
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));
}
