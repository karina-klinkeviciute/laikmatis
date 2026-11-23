import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'model.dart';
import 'platform_bridge.dart';

void main() => runApp(MassageApp(bridge: NativeTimerBridge()));

class MassageApp extends StatelessWidget {
  const MassageApp({super.key, required this.bridge});
  final TimerBridge bridge;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Masažo laikmatis',
    debugShowCheckedModeBanner: false,
    locale: const Locale('lt'),
    supportedLocales: const [Locale('lt')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: 'MassageSans',
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff244d43),
        brightness: Brightness.light,
        primary: const Color(0xff244d43),
      ),
      scaffoldBackgroundColor: const Color(0xfff5f3ed),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 18, height: 1.45),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 60),
          textStyle: const TextStyle(
            fontFamily: 'MassageSans',
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 60),
          textStyle: const TextStyle(fontFamily: 'MassageSans', fontSize: 18),
        ),
      ),
    ),
    home: TimerScreen(bridge: bridge),
  );
}

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key, required this.bridge});
  final TimerBridge bridge;
  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> with WidgetsBindingObserver {
  TimerSnapshot _snapshot = const TimerSnapshot();
  Massage _selected = massages.first;
  Timer? _poller;
  bool _busy = false;
  bool _polling = false;
  bool _listening = false;
  bool _available = true;
  String? _message;
  String? _dismissedError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_polling || !_available) return;
    _polling = true;
    try {
      final next = await widget.bridge.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = next;
        if (next.active || next.phase == TimerPhase.finished) {
          _selected = massages.firstWhere(
            (m) => m.id == next.id,
            orElse: () => massages.first,
          );
        }
        if (next.error != null && next.error != _dismissedError) {
          _message = next.error;
        }
      });
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _available = false;
          _message = 'Ši programėlė skirta „Android“ ir „iPhone“ telefonams.';
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message ?? 'Nepavyko nuskaityti laikmačio.';
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _run(String command, [Map<String, Object?>? arguments]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.bridge.command(command, arguments);
      await _refresh();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message ?? 'Veiksmas nepavyko. Bandykite dar kartą.';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _message = 'Paleiskite programėlę telefone.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _select(Massage massage) async {
    if (_snapshot.active || _busy) return;
    setState(() {
      _selected = massage;
    });
    // TalkBack / VoiceOver announces the selection; do not duplicate it with TTS.
  }

  Future<void> _start() => _run('start', {'id': _selected.id});

  Future<void> _listen() async {
    if (_busy || _listening) return;
    setState(() {
      _listening = true;
      _message = 'Klausau…';
    });
    try {
      final words = await widget.bridge.listen();
      if (!mounted) return;
      final command = parseVoiceCommand(words);
      setState(() {
        _message = words.isEmpty
            ? 'Komandos neišgirdau.'
            : 'Išgirdau: „$words“';
      });
      if (command == null) {
        await _run('speak', {
          'text':
              'Komandos nesupratau. Pasakykite, pavyzdžiui, pradėti arba kiek liko laiko.',
        });
        return;
      }
      switch (command.action) {
        case VoiceAction.select:
          if (_snapshot.active) {
            await _run('speak', {
              'text': 'Prieš keisdami masažą sustabdykite laikmatį.',
            });
          } else {
            await _select(command.massage!);
            await _run('speak', {
              'text':
                  'Pasirinkta. ${command.massage!.label}. Sakykite pradėti.',
            });
          }
        case VoiceAction.start:
          if (!_snapshot.active) await _start();
        case VoiceAction.pause:
          if (_snapshot.phase == TimerPhase.running) await _run('pause');
        case VoiceAction.resume:
          if (_snapshot.phase == TimerPhase.paused) await _run('resume');
        case VoiceAction.stop:
          if (_snapshot.active) await _run('stop');
        case VoiceAction.remaining:
          await _run('remaining');
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message ?? 'Balso atpažinimas nepasiekiamas.';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _message = 'Balso valdymą išbandykite telefone.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _listening = false;
        });
      }
    }
  }

  String get _status => switch (_snapshot.phase) {
    TimerPhase.idle => 'Pasirinkite masažą',
    TimerPhase.preparing => 'Ruošiami balsiniai pranešimai…',
    TimerPhase.running => 'Masažas vyksta',
    TimerPhase.paused => 'Pristabdyta',
    TimerPhase.finished => 'Masažas baigtas',
  };

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && !_listening && _available;
    final active = _snapshot.active;
    final remaining = active || _snapshot.phase == TimerPhase.finished
        ? _snapshot.remainingMs
        : _selected.minutes * 60000;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    const ExcludeSemantics(
                      child: Icon(Icons.spa_outlined, size: 30),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Masažo laikmatis',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Jūsų laikas ramybei',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xffe1e9df),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'Likęs laikas',
                        value: clockText(remaining),
                        child: ExcludeSemantics(
                          child: FittedBox(
                            child: Text(
                              clockText(remaining),
                              style: const TextStyle(
                                fontSize: 76,
                                fontWeight: FontWeight.w500,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '${_selected.side} pusė · ${_selected.name}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              !enabled ||
                                  _snapshot.phase == TimerPhase.preparing
                              ? null
                              : () {
                                  if (_snapshot.phase == TimerPhase.running) {
                                    _run('pause');
                                  } else if (_snapshot.phase ==
                                      TimerPhase.paused) {
                                    _run('resume');
                                  } else {
                                    _start();
                                  }
                                },
                          icon: Icon(
                            _snapshot.phase == TimerPhase.running
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            _snapshot.phase == TimerPhase.running
                                ? 'Pristabdyti'
                                : _snapshot.phase == TimerPhase.paused
                                ? 'Tęsti'
                                : 'Pradėti',
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: enabled ? () => _run('stop') : null,
                            child: Text(
                              _snapshot.phase == TimerPhase.preparing
                                  ? 'Atšaukti'
                                  : 'Sustabdyti',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: enabled ? () => _run('remaining') : null,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(64, 52),
                        ),
                        child: const Text(
                          'Pasakyti likusį laiką',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                for (final side in ['Kairė', 'Dešinė']) ...[
                  Semantics(
                    header: true,
                    child: Text(
                      '$side pusė',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final massage in massages.where((m) => m.side == side))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MassageCard(
                        key: ValueKey(massage.id),
                        massage: massage,
                        selected: _selected.id == massage.id,
                        onTap: !active && enabled
                            ? () => _select(massage)
                            : null,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: enabled ? _listen : null,
                  icon: Icon(_listening ? Icons.hearing : Icons.mic_none),
                  label: Text(_listening ? 'Klausau…' : 'Kalbėti'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paspauskite „Kalbėti“ ir sakykite: „Kairė pusė, masažas vienas“, '
                  '„Pradėti“, „Pristabdyti“, „Tęsti“, „Sustabdyti“ arba „Kiek liko laiko?“',
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xffffedc8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _message!,
                            style: const TextStyle(
                              fontSize: 17,
                              color: Color(0xff493300),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _dismissedError = _snapshot.error;
                              _message = null;
                            }),
                            child: const Text('Uždaryti pranešimą'),
                          ),
                          if (_message!.contains('bals') ||
                              _message!.contains('kalb'))
                            TextButton(
                              onPressed: () => _run('voiceSettings'),
                              child: const Text('Balso nustatymai'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Garsui patikrinti prieš masažą paspauskite „Pasakyti likusį laiką“. '
                  'Balso komandoms klausomasi tik paspaudus „Kalbėti“.',
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MassageCard extends StatelessWidget {
  const _MassageCard({
    super.key,
    required this.massage,
    required this.selected,
    this.onTap,
  });
  final Massage massage;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: massage.label,
    selected: selected,
    inMutuallyExclusiveGroup: true,
    button: true,
    enabled: onTap != null,
    onTap: onTap,
    child: ExcludeSemantics(
      child: Material(
        color: selected ? const Color(0xffe1e9df) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? const Color(0xff244d43) : const Color(0xffcbcfc8),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        massage.name,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${massage.minutes} min. · ${massage.interval} min. intervalas',
                        style: const TextStyle(fontSize: 17),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: const Color(0xff244d43),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
