import Cocoa
import FlutterMacOS
import Vision

/// On-device text recognition via Apple Vision (macOS).
enum VisionOcrPlugin {
  static let channelName = "app.vitalog/vision_ocr"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Expected map", details: nil))
        return
      }

      let image: CGImage?
      if let typed = args["bytes"] as? FlutterStandardTypedData {
        image = cgImage(from: typed.data)
      } else if let path = args["path"] as? String {
        image = cgImage(fromPath: path)
      } else {
        result(FlutterError(code: "bad_args", message: "Need bytes or path", details: nil))
        return
      }

      guard let cgImage = image else {
        result(FlutterError(code: "decode", message: "Could not decode image", details: nil))
        return
      }

      recognize(cgImage: cgImage, result: result)
    }
  }

  private static func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    if Thread.isMainThread {
      result(value)
    } else {
      DispatchQueue.main.async { result(value) }
    }
  }

  private static func cgImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  private static func cgImage(fromPath path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  private static func recognize(cgImage: CGImage, result: @escaping FlutterResult) {
    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        reply(result, FlutterError(code: "process", message: error.localizedDescription, details: nil))
        return
      }
      guard let observations = request.results as? [VNRecognizedTextObservation] else {
        reply(result, "")
        return
      }

      // Vision does not guarantee reading order. Sort top→bottom, then left→right
      // so stacked lab pairing sees value/unit/range near the analyte name — not
      // Bilirubin’s 0.7 glued onto a later GGT observation.
      struct Item {
        let y: CGFloat
        let x: CGFloat
        let text: String
      }
      var items: [Item] = []
      items.reserveCapacity(observations.count)
      for observation in observations {
        guard let top = observation.topCandidates(1).first else { continue }
        let t = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { continue }
        let box = observation.boundingBox
        // Vision origin is bottom-left; flip Y so smaller = higher on page.
        let yTop = 1.0 - box.origin.y - box.height
        items.append(Item(y: yTop, x: box.origin.x, text: t))
      }
      items.sort { a, b in
        if abs(a.y - b.y) > 0.012 { return a.y < b.y }
        return a.x < b.x
      }
      reply(result, items.map(\.text).joined(separator: "\n"))
    }
    request.recognitionLevel = .accurate
    // Off: language correction invents spaces/words that break lab tokens.
    request.usesLanguageCorrection = false
    if #available(macOS 13.0, *) {
      request.automaticallyDetectsLanguage = true
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        reply(result, FlutterError(code: "process", message: error.localizedDescription, details: nil))
      }
    }
  }
}
