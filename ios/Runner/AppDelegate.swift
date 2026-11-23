import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let massageTimer = MassageTimer()
  private var timerChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MassageTimer") else { return }
    timerChannel = FlutterMethodChannel(name: "lt.masazas/timer", binaryMessenger: registrar.messenger())
    timerChannel?.setMethodCallHandler { [weak self] call, result in
      self?.massageTimer.handle(call, result: result)
    }
  }
}
