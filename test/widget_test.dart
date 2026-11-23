import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:masazo_laikmatis/main.dart';
import 'package:masazo_laikmatis/model.dart';
import 'package:masazo_laikmatis/platform_bridge.dart';

class FakeBridge implements TimerBridge {
  TimerSnapshot state = const TimerSnapshot();
  final commands = <String>[];
  String words = '';
  String id = 'left_one';
  @override
  Future<TimerSnapshot> snapshot() async => state;
  @override
  Future<String> listen() async => words;
  @override
  Future<void> command(String name, [Map<String, Object?>? arguments]) async {
    commands.add(name);
    if (name == 'start') id = arguments!['id']! as String;
    final phase = switch (name) {
      'start' || 'resume' => TimerPhase.running,
      'pause' => TimerPhase.paused,
      'stop' => TimerPhase.idle,
      _ => state.phase,
    };
    state = TimerSnapshot(
      phase: phase,
      id: id,
      remainingMs: id.startsWith('right') ? 3600000 : 1800000,
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final textFont = FontLoader('MassageSans')
      ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/roboto-medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf'));
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await textFont.load();
    await iconFont.load();
  });
  test(
    'Lithuanian voice commands accept inflections and reject ambiguous choices',
    () {
      expect(
        parseVoiceCommand('Dešinė pusė, masažas du')?.massage?.id,
        'right_two',
      );
      expect(
        parseVoiceCommand('Pasirink kairės pusės pirmą masažą')?.massage?.id,
        'left_one',
      );
      expect(parseVoiceCommand('Pradėti')?.action, VoiceAction.start);
      expect(parseVoiceCommand('Pristabdyti')?.action, VoiceAction.pause);
      expect(parseVoiceCommand('Tęsti')?.action, VoiceAction.resume);
      expect(parseVoiceCommand('Sustabdyti')?.action, VoiceAction.stop);
      expect(
        parseVoiceCommand('Kiek liko laiko?')?.action,
        VoiceAction.remaining,
      );
      expect(parseVoiceCommand('Kairė ir dešinė pusė, masažas du'), isNull);
      expect(parseVoiceCommand('Kairė pusė, masažas vienas arba du'), isNull);
      expect(parseVoiceCommand('Nepradėk'), isNull);
    },
  );
  test('Time rounding never shows zero before the actual end', () {
    expect(clockText(1), '00:01');
    expect(clockText(59999), '01:00');
    expect(clockText(3600000), '60:00');
    expect(clockText(-1), '00:00');
    expect(minutePhrase(11), 'Liko 11 minučių');
    expect(minutePhrase(21), 'Liko 21 minutė');
  });
  testWidgets(
    'Choose, start, pause, resume, stop and retain the selected preset',
    (tester) async {
      final bridge = FakeBridge();
      await tester.pumpWidget(MassageApp(bridge: bridge));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('right_two')),
        250,
      );
      await tester.tap(find.byKey(const ValueKey('right_two')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pradėti'));
      await tester.pumpAndSettle();
      expect(bridge.id, 'right_two');
      expect(find.text('60:00'), findsOneWidget);
      await tester.tap(find.text('Pristabdyti'));
      await tester.pumpAndSettle();
      expect(find.text('Pristabdyta'), findsOneWidget);
      await tester.tap(find.text('Tęsti'));
      await tester.pumpAndSettle();
      expect(find.text('Masažas vyksta'), findsOneWidget);
      await tester.tap(find.text('Sustabdyti'));
      await tester.pumpAndSettle();
      expect(find.text('Pradėti'), findsOneWidget);
      expect(bridge.commands, ['start', 'pause', 'resume', 'stop']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('All four choices have full accessible labels', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MassageApp(bridge: FakeBridge()));
    await tester.pumpAndSettle();
    for (final massage in massages) {
      final choice = find.bySemanticsLabel(massage.label);
      await tester.scrollUntilVisible(choice, 200);
      expect(choice, findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
  testWidgets('A narrow screen with large text has no layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MassageApp(bridge: FakeBridge()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Kalbėti'), 300);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Phone preview', (tester) async {
    tester.view.physicalSize = const Size(430, 1360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MassageApp(bridge: FakeBridge()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
