import Flutter
import UIKit
import Vision

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "recordo.SignOcr") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "recordo/sign_ocr",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      Self.recognizeSign(path: path, result: result)
    }
  }

  private static func recognizeSign(path: String, result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      result(FlutterError(code: "no_image", message: "讀唔到相", details: nil))
      return
    }
    let request = VNRecognizeTextRequest { request, error in
      if let error {
        result(FlutterError(code: "vision", message: error.localizedDescription, details: nil))
        return
      }
      let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
      result(lines.joined(separator: "\n"))
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hant", "en-US"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        result(FlutterError(code: "vision", message: error.localizedDescription, details: nil))
      }
    }
  }
}
