import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:team_wolves_controller/main.dart';

void main() {
  Future<void> setLandscape(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('splash advances automatically into the console',
      (WidgetTester tester) async {
    await setLandscape(tester);
    await tester.pumpWidget(const WolveBotApp());

    expect(find.text('TEAM WOLVES'), findsOneWidget);
    expect(find.text('ROBO RACE'), findsOneWidget);
    expect(find.text('STARTING WOLVE BOT'), findsOneWidget);
    expect(find.text('E-STOP'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.text('TEAM WOLVES'), findsNothing);
    expect(find.text('E-STOP'), findsOneWidget);
    expect(find.text('BOOST 100%'), findsOneWidget);
    expect(find.text('ZERO PIVOT'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);
    expect(find.text('65%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('TORQUE'), findsOneWidget);
    expect(find.text('SPEED'), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);
  });

  testWidgets('splash skips on tap', (WidgetTester tester) async {
    await setLandscape(tester);
    await tester.pumpWidget(const WolveBotApp());

    await tester.tap(find.text('STARTING WOLVE BOT'));
    await tester.pumpAndSettle();

    expect(find.text('E-STOP'), findsOneWidget);
  });

  testWidgets('console shows the live-link and telemetry diagnostics',
      (WidgetTester tester) async {
    await setLandscape(tester);
    await tester.pumpWidget(const WolveBotApp());
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('ESP32'), findsOneWidget);
    expect(find.text('PACK'), findsOneWidget);
    expect(find.text('DROPS'), findsOneWidget);
  });
}
