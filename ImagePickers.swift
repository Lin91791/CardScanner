import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

// MARK: - 相册选图(PHPicker,不需要相册权限弹窗)

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { self.parent.onPick(image) }
                }
            }
        }
    }
}

// MARK: - 自定义拍卡相机(卡片取景框引导,快门后只裁剪框内区域)

final class CardCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "card.camera.session")
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    @Published var isDenied = false

    private var onCapture: ((UIImage?) -> Void)?
    private var metaCropRect: CGRect?   // 快门时刻换算好的归一化裁剪区域

    func configure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setup()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.setup() }
                else { DispatchQueue.main.async { self.isDenied = true } }
            }
        default:
            isDenied = true
        }
    }

    private func setup() {
        sessionQueue.async {
            guard self.session.inputs.isEmpty else {
                if !self.session.isRunning { self.session.startRunning() }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.isDenied = true }
                return
            }
            self.session.addInput(input)
            self.session.addOutput(self.output)
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// guideRect 为屏幕坐标里的取景框;在主线程先换算成归一化区域,拍完在回调里裁剪
    /// 失败时回调 nil,便于界面恢复快门按钮
    func capture(guideRect: CGRect, onCapture: @escaping (UIImage?) -> Void) {
        self.onCapture = onCapture
        metaCropRect = previewLayer?.metadataOutputRectConverted(fromLayerRect: guideRect)
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let cg = photo.cgImageRepresentation() else {
            DispatchQueue.main.async { self.onCapture?(nil) }
            return
        }
        // 后摄竖屏拍摄,传感器原始方向为横向,用 .right 转正
        var image = UIImage(cgImage: cg, scale: 1, orientation: .right)
        if let meta = metaCropRect {
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            let cropRect = CGRect(x: meta.origin.x * w, y: meta.origin.y * h,
                                  width: meta.width * w, height: meta.height * h).integral
            if let cut = cg.cropping(to: cropRect) {
                image = UIImage(cgImage: cut, scale: 1, orientation: .right)
            }
        }
        let result = image
        DispatchQueue.main.async { self.onCapture?(result) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let controller: CardCameraController

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        controller.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// 遮罩:全屏半透明黑,中间挖出圆角卡框
struct CutoutMask: Shape {
    let hole: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return p
    }
}

/// 取景框四角
struct CameraCorners: Shape {
    var length: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

extension CardCameraController {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}
