import Flutter
import MessageUI
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  MFMessageComposeViewControllerDelegate
{
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.example.cameronMobile.briefing")
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(
      name: "cameron/communication",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      guard let self, let arguments = call.arguments as? [String: String] else {
        result(false)
        return
      }
      switch call.method {
      case "prepare_call":
        guard let phone = self.phoneNumber(arguments),
          let url = URL(string: "tel:\(phone)")
        else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: { result($0) })
      case "draft_message":
        guard let phone = self.phoneNumber(arguments),
          MFMessageComposeViewController.canSendText(),
          let presenter = self.messagePresenter()
        else {
          result(false)
          return
        }
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.recipients = [phone]
        composer.body = arguments["body"]
        presenter.present(composer, animated: true) {
          result(true)
        }
      case "draft_email":
        guard let url = self.emailURL(arguments) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: { result($0) })
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func phoneNumber(_ arguments: [String: String]) -> String? {
    guard let phone = arguments["phone"],
      phone.range(of: #"^\+?[0-9]{3,15}$"#, options: .regularExpression) != nil
    else { return nil }
    return phone
  }

  private func emailURL(_ arguments: [String: String]) -> URL? {
    let recipientCharacters = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@"
    )
    guard let recipient = arguments["email"]?.addingPercentEncoding(
      withAllowedCharacters: recipientCharacters
    ), let body = arguments["body"] else { return nil }

    var components = URLComponents()
    components.scheme = "mailto"
    components.percentEncodedPath = recipient
    components.queryItems = [URLQueryItem(name: "body", value: body)]
    if let subject = arguments["subject"] {
      components.queryItems?.append(URLQueryItem(name: "subject", value: subject))
    }
    components.percentEncodedQuery = components.percentEncodedQuery?
      .replacingOccurrences(of: "+", with: "%2B")
    return components.url
  }

  private func messagePresenter() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?.keyWindow
    guard var presenter = window?.rootViewController else { return nil }
    while let presented = presenter.presentedViewController { presenter = presented }
    return presenter
  }

  func messageComposeViewController(
    _ controller: MFMessageComposeViewController,
    didFinishWith result: MessageComposeResult
  ) {
    controller.dismiss(animated: true)
  }
}
