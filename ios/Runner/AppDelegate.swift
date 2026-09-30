import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "InkDevice") {
      let channel = FlutterMethodChannel(name: "ink/device", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "deviceId" {
          result(DeviceKeychain.id())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

/// 기기 ID: 키체인에 한 번 만들어 두면 앱을 지웠다 다시 깔아도 남는다 (이 기기에서만, 백업으로 옮겨지지 않음).
/// 서버에는 해시로만 저장된다.
enum DeviceKeychain {
  private static let service = "com.isla0x.inkExe.device"
  private static let account = "device-id-v1"

  static func id() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: AnyObject?
    if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
       let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty {
      return value
    }
    let value = UUID().uuidString
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(add as CFDictionary, nil)
    return status == errSecSuccess || status == errSecDuplicateItem ? (status == errSecSuccess ? value : readAgain()) : value
  }

  private static func readAgain() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
