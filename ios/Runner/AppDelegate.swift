import EventKit
import Flutter
import MessageUI
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  MFMessageComposeViewControllerDelegate
{
  private let calendarStore = EKEventStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.example.cameronMobile.briefing")
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(
      name: "cameron/calendar",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      self?.handleCalendar(call, result: result)
    }
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

  private var hasCalendarAccess: Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17, *) { return status == .fullAccess }
    return status == .authorized
  }

  private func handleCalendar(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasAccess":
      result(hasCalendarAccess)
    case "requestAccess":
      if hasCalendarAccess {
        result(true)
        return
      }
      let reply: (Bool, Error?) -> Void = { granted, error in
        DispatchQueue.main.async {
          if let error {
            result(FlutterError(code: "calendar_permission", message: error.localizedDescription, details: nil))
          } else {
            result(granted)
          }
        }
      }
      if #available(iOS 17, *) {
        calendarStore.requestFullAccessToEvents(completion: reply)
      } else {
        calendarStore.requestAccess(to: .event, completion: reply)
      }
    case "openSettings":
      guard let settings = URL(string: UIApplication.openSettingsURLString) else {
        result(FlutterError(code: "calendar_settings", message: nil, details: nil))
        return
      }
      UIApplication.shared.open(settings, options: [:]) { opened in
        result(opened ? nil : FlutterError(code: "calendar_settings", message: nil, details: nil))
      }
    case "events":
      guard hasCalendarAccess else {
        result(FlutterError(code: "calendar_permission", message: "Calendar access is off.", details: nil))
        return
      }
      guard let arguments = call.arguments as? [String: NSNumber],
        let begin = arguments["start"], let finish = arguments["end"]
      else {
        result(FlutterError(code: "calendar_date", message: "Invalid calendar date.", details: nil))
        return
      }
      let start = Date(timeIntervalSince1970: begin.doubleValue / 1000)
      let end = Date(timeIntervalSince1970: finish.doubleValue / 1000)
      guard end > start, end.timeIntervalSince(start) <= 26 * 60 * 60 else {
        result(FlutterError(code: "calendar_date", message: "Invalid calendar date.", details: nil))
        return
      }
      let predicate = calendarStore.predicateForEvents(withStart: start, end: end, calendars: nil)
      let events = calendarStore.events(matching: predicate)
        .filter { $0.status != .canceled && $0.startDate < end && $0.endDate > start }
        .sorted { $0.startDate < $1.startDate }
        .map { event -> [String: Any] in
          [
            "title": event.title ?? "",
            "start": Int64(event.startDate.timeIntervalSince1970 * 1000),
            "end": Int64(event.endDate.timeIntervalSince1970 * 1000),
            "allDay": event.isAllDay,
          ]
        }
      result(events)
    default:
      result(FlutterMethodNotImplemented)
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
