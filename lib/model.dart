class Massage {
  const Massage(this.id, this.side, this.name, this.minutes, this.interval);
  final String id;
  final String side;
  final String name;
  final int minutes;
  final int interval;
  String get label =>
      '$side pusė, $name, $minutes minučių, '
      '${interval == 1 ? 'pranešimai kas minutę' : 'pranešimai kas 5 minutes'}';
}

const massages = [
  Massage('left_one', 'Kairė', 'Masažas vienas', 30, 1),
  Massage('left_two', 'Kairė', 'Masažas du', 30, 5),
  Massage('right_one', 'Dešinė', 'Masažas vienas', 60, 1),
  Massage('right_two', 'Dešinė', 'Masažas du', 60, 5),
];

enum TimerPhase { idle, preparing, running, paused, finished }

class TimerSnapshot {
  const TimerSnapshot({
    this.phase = TimerPhase.idle,
    this.id = 'left_one',
    this.remainingMs = 1800000,
    this.error,
  });
  final TimerPhase phase;
  final String id;
  final int remainingMs;
  final String? error;
  bool get active =>
      phase == TimerPhase.running ||
      phase == TimerPhase.paused ||
      phase == TimerPhase.preparing;
  factory TimerSnapshot.fromMap(Map<Object?, Object?> map) => TimerSnapshot(
    phase: TimerPhase.values.firstWhere(
      (p) => p.name == map['phase'],
      orElse: () => TimerPhase.idle,
    ),
    id: map['id'] as String? ?? 'left_one',
    remainingMs: (map['remainingMs'] as num?)?.toInt() ?? 1800000,
    error: map['error'] as String?,
  );
}

enum VoiceAction { start, pause, resume, stop, remaining, select }

class VoiceCommand {
  const VoiceCommand(this.action, [this.massage]);
  final VoiceAction action;
  final Massage? massage;
}

VoiceCommand? parseVoiceCommand(String input) {
  var text = input.toLowerCase();
  const replacements = {
    'ą': 'a',
    'č': 'c',
    'ę': 'e',
    'ė': 'e',
    'į': 'i',
    'š': 's',
    'ų': 'u',
    'ū': 'u',
    'ž': 'z',
  };
  replacements.forEach((key, value) {
    text = text.replaceAll(key, value);
  });
  text = text
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (RegExp(r'\b(liko|liko laiko|kiek)\b').hasMatch(text)) {
    return const VoiceCommand(VoiceAction.remaining);
  }
  if (RegExp(r'\b(sustabdyk|sustabdyti|baik|baigti)\b').hasMatch(text)) {
    return const VoiceCommand(VoiceAction.stop);
  }
  if (RegExp(r'\b(pristabdyk|pristabdyti|pauze)\b').hasMatch(text)) {
    return const VoiceCommand(VoiceAction.pause);
  }
  if (RegExp(r'\b(tesk|testi)\b').hasMatch(text)) {
    return const VoiceCommand(VoiceAction.resume);
  }
  final left = text.contains('kaire');
  final right = text.contains('desine');
  final one = RegExp(r'\b(vienas|pirma|pirmas|pirmaji|1)\b').hasMatch(text);
  final two = RegExp(r'\b(du|antra|antras|antraji|2)\b').hasMatch(text);
  if (left != right && one != two) {
    final massage = massages[(left ? 0 : 2) + (two ? 1 : 0)];
    return VoiceCommand(VoiceAction.select, massage);
  }
  if (RegExp(r'^(pradeti|pradek)( masaza| laikmati)?$').hasMatch(text)) {
    return const VoiceCommand(VoiceAction.start);
  }
  return null;
}

String minutePhrase(int minutes) {
  final mod100 = minutes % 100;
  final mod10 = minutes % 10;
  final noun = mod100 >= 11 && mod100 <= 19 || mod10 == 0
      ? 'minučių'
      : mod10 == 1
      ? 'minutė'
      : 'minutės';
  return 'Liko $minutes $noun';
}

String clockText(int milliseconds) {
  final seconds = (milliseconds.clamp(0, 3600000) / 1000).ceil();
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}
