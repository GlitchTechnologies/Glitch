import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/widgets/glitch_plus_badge.dart';
import 'package:glitch/widgets/glitch_pressable.dart';

void main() {
  testWidgets('selectable text keeps the cursor of its action', (tester) async {
    final controls = <Widget Function(Widget)>[
      (child) => ClickableCursor(child: child),
      (child) => GlitchPressable(onTap: () {}, child: child),
      (child) => GlitchHoverArea(onTap: () {}, builder: (_, __) => child),
    ];
    for (final control in controls) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          textSelectionTheme: const TextSelectionThemeData(selectionColor: Colors.purple),
        ),
        home: Scaffold(
          body: SelectionArea(
            child: Center(child: control(const Text('Name'))),
          ),
        ),
      ));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.text('Name')));
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(mouse.device),
          SystemMouseCursors.click);
      final textContext = tester.element(find.text('Name'));
      expect(SelectionContainer.maybeOf(textContext), isNotNull);
      expect(DefaultSelectionStyle.of(textContext).selectionColor, Colors.purple);
      await mouse.removePointer();
    }
  });

  testWidgets('profile display name has an arrow and remains selectable', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          child: Center(
            child: UserDisplayName(
              displayName: 'Profile name',
              isGlitchPlus: false,
              style: const TextStyle(),
            ),
          ),
        ),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Profile name')));
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(mouse.device),
        SystemMouseCursors.basic);
    expect(SelectionContainer.maybeOf(tester.element(find.text('Profile name'))), isNotNull);
    await mouse.removePointer();
  });
}
