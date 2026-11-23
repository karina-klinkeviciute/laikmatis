import 'package:flutter/services.dart';
import 'model.dart';

abstract class TimerBridge {
  Future<TimerSnapshot> snapshot();
  Future<void> command(String name, [Map<String, Object?>? arguments]);
  Future<String> listen();
}

class NativeTimerBridge implements TimerBridge {
  static const channel = MethodChannel('lt.masazas/timer');
  @override
  Future<TimerSnapshot> snapshot() async => TimerSnapshot.fromMap(
    await channel.invokeMapMethod<Object?, Object?>('snapshot') ?? {},
  );
  @override
  Future<void> command(String name, [Map<String, Object?>? arguments]) async {
    await channel.invokeMethod<void>(name, arguments);
  }

  @override
  Future<String> listen() async =>
      await channel.invokeMethod<String>('listen') ?? '';
}
