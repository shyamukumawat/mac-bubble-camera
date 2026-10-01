import Cocoa
import AVFoundation
import Vision
import CoreImage
import UniformTypeIdentifiers

/// Custom borderless, floating window that stays on top across all Spaces & Full-screen apps.
class BubbleWindow: NSWindow {
    weak var bubbleView: BubbleView?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false // Managed in BubbleView to support edge/corner resizing
        self.hasShadow = true
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        bubbleView?.handleKey(event)
    }
}

/// Available shapes for the camera overlay.
enum BubbleShape: String, CaseIterable {
    case circle = "Circle"
    case rectangle16_9 = "Rectangle (16:9 Landscape)"
    case portrait9_16 = "Portrait (9:16 Shorts/Reels)"
    case rectangle4_3 = "Rectangle (4:3)"
    case roundedSquare = "Rounded Square"
    case freeform = "Freeform (Custom)"

    var displayName: String {
        return self.rawValue
    }

    var aspectRatio: CGFloat {
        switch self {
        case .circle, .roundedSquare, .freeform:
            return 1.0
        case .rectangle16_9:
            return 16.0 / 9.0
        case .portrait9_16:
            return 9.0 / 16.0
        case .rectangle4_3:
            return 4.0 / 3.0
        }
    }

    func cornerRadius(for bounds: NSRect) -> CGFloat {
        switch self {
        case .circle:
            return min(bounds.width, bounds.height) / 2.0
        case .rectangle16_9, .portrait9_16, .rectangle4_3, .freeform:
            return 18.0
        case .roundedSquare:
            return 28.0
        }
    }

    func presetWidth(for level: Int) -> CGFloat {
        switch self {
        case .circle, .roundedSquare, .freeform:
            switch level {
            case 1: return 170
            case 2: return 280
            case 3: return 420
            default: return 280
            }
        case .rectangle16_9:
            switch level {
            case 1: return 260
            case 2: return 380
            case 3: return 520
            default: return 380
            }
        case .portrait9_16:
            switch level {
            case 1: return 170
            case 2: return 240
            case 3: return 320
            default: return 240
            }
        case .rectangle4_3:
            switch level {
            case 1: return 240
            case 2: return 340
            case 3: return 460
            default: return 340
            }
        }
    }
}

/// Identifies which edge or corner is being resized by mouse drag.
enum ResizeEdge {
    case none
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// How the background is applied.
enum CameraBackgroundStyle: String, CaseIterable {
    case backdropFrame = "Backdrop Frame (Keeps Chair & Head Intact)"
    case aiCutout = "AI Person Cutout (Virtual Green Screen)"
}

/// Available background presets.
enum BackgroundPreset: String, CaseIterable {
    case none = "None (Raw Camera)"
    case blur = "Blur Background"
    case studioDark = "Studio Dark (Gradient)"
    case sunsetWarm = "Sunset Warm (Gradient)"
    case cyberBlue = "Cyber Blue (Gradient)"
    case custom = "Custom Image"
}

/// The main content view managing camera capture session, background frame/cutout, shape masking, and interactions.
class BubbleView: NSView, AVCaptureVideoDataOutputSampleBufferDelegate {
    var session: AVCaptureSession?
    var currentDevice: AVCaptureDevice?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureVideoDataOutput?

    // Layers
    let backdropLayer = CALayer()
    let cameraShadowLayer = CALayer()
    let cameraClipLayer = CALayer()
    let processedLayer = CALayer()

    var currentShape: BubbleShape = .circle
    var hasWhiteBorder = true
    var isFullScreen = false
    var savedBubbleFrame: NSRect?

    // Background Management (100% dynamic, user configurable)
    var backgroundStyle: CameraBackgroundStyle = .backdropFrame
    var currentBackgroundPreset: BackgroundPreset = .none
    var framePadding: CGFloat = 18.0
    var customBackgroundImage: NSImage?
    var customBackgroundName: String?
    var cachedCustomCIImage: CIImage?

    // AI Segmentation Pipeline (used only in AI Cutout mode)
    let segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        return req
    }()
    let sequenceHandler = VNSequenceRequestHandler()
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    let processingQueue = DispatchQueue(label: "com.camerabubble.videoprocessing", qos: .userInteractive)
    var isProcessingFrame = false

    var isBackgroundActive: Bool {
        return currentBackgroundPreset != .none
    }

    // Interactive Dragging & Edge Resizing State
    var trackingArea: NSTrackingArea?
    var activeResizeEdge: ResizeEdge = .none
    var isDraggingWindow = false
    var initialMouseLocation: NSPoint = .zero
    var initialWindowFrame: NSRect = .zero
    var initialWindowOrigin: NSPoint = .zero

    static let diagonalNESWCursor: NSCursor = {
        let sel = Selector(("_windowResizeNorthEastSouthWestCursor"))
        if NSCursor.responds(to: sel), let obj = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return obj
        }
        return .crosshair
    }()

    static let diagonalNWSECursor: NSCursor = {
        let sel = Selector(("_windowResizeNorthWestSouthEastCursor"))
        if NSCursor.responds(to: sel), let obj = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return obj
        }
        return .crosshair
    }()

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        loadSavedCustomBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        loadSavedCustomBackground()
    }

    func setupLayers() {
        self.wantsLayer = true

        // Backdrop layer (shows user-chosen background image or gradient)
        backdropLayer.contentsGravity = .resizeAspectFill
        backdropLayer.masksToBounds = true
        self.layer?.addSublayer(backdropLayer)

        // Camera shadow container (casts soft drop shadow in frame mode)
        cameraShadowLayer.masksToBounds = false
        self.layer?.addSublayer(cameraShadowLayer)

        // Camera clip layer (clips camera feed to rounded corners & renders border)
        cameraClipLayer.masksToBounds = true
        cameraShadowLayer.addSublayer(cameraClipLayer)

        // Processed layer (for AI virtual background cutout mode)
        processedLayer.contentsGravity = .resizeAspectFill
        processedLayer.isHidden = true
        cameraClipLayer.addSublayer(processedLayer)

        updateAppearance()
    }

    func loadSavedCustomBackground() {
        if let path = UserDefaults.standard.string(forKey: "CustomBackgroundImagePath"),
           FileManager.default.fileExists(atPath: path),
           let img = NSImage(contentsOfFile: path) {
            self.customBackgroundImage = img
            self.customBackgroundName = URL(fileURLWithPath: path).lastPathComponent
            self.cachedCustomCIImage = ciImage(from: img)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    func updateAppearance() {
        guard let layer = self.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let outerRadius = isFullScreen ? 0 : currentShape.cornerRadius(for: bounds)
        layer.cornerRadius = outerRadius
        layer.masksToBounds = true

        if isFullScreen {
            layer.borderWidth = 0
            backdropLayer.isHidden = true
            cameraShadowLayer.frame = bounds
            cameraShadowLayer.shadowOpacity = 0
            cameraClipLayer.frame = bounds
            cameraClipLayer.cornerRadius = 0
            cameraClipLayer.borderWidth = 0
            previewLayer?.frame = bounds
            processedLayer.frame = bounds
        } else if !isBackgroundActive {
            // Raw camera mode: camera fills the window exactly
            layer.borderColor = hasWhiteBorder ? NSColor.white.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
            layer.borderWidth = hasWhiteBorder ? 3.5 : 0

            backdropLayer.isHidden = true
            cameraShadowLayer.frame = bounds
            cameraShadowLayer.shadowOpacity = 0
            cameraClipLayer.frame = bounds
            cameraClipLayer.cornerRadius = outerRadius
            cameraClipLayer.borderWidth = 0
            previewLayer?.frame = bounds
            processedLayer.frame = bounds
            previewLayer?.isHidden = false
            processedLayer.isHidden = true
        } else if backgroundStyle == .backdropFrame {
            // Backdrop Frame Mode: Chosen background image frames the camera, chair & head 100% intact!
            layer.borderWidth = 0

            backdropLayer.isHidden = false
            backdropLayer.frame = bounds
            backdropLayer.cornerRadius = outerRadius
            backdropLayer.contents = getBackgroundImageCG(for: currentBackgroundPreset, targetSize: bounds.size)

            let pad = framePadding
            let innerRect = bounds.insetBy(dx: pad, dy: pad)
            cameraShadowLayer.frame = innerRect
            cameraShadowLayer.shadowColor = NSColor.black.cgColor
            cameraShadowLayer.shadowOpacity = 0.50
            cameraShadowLayer.shadowRadius = 8
            cameraShadowLayer.shadowOffset = CGSize(width: 0, height: -3)

            let innerCorner = max(4, outerRadius - pad / 2.0)
            cameraClipLayer.frame = cameraShadowLayer.bounds
            cameraClipLayer.cornerRadius = innerCorner
            cameraClipLayer.borderColor = hasWhiteBorder ? NSColor.white.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
            cameraClipLayer.borderWidth = hasWhiteBorder ? 2.5 : 0

            previewLayer?.frame = cameraClipLayer.bounds
            processedLayer.frame = cameraClipLayer.bounds
            previewLayer?.isHidden = false
            processedLayer.isHidden = true
        } else {
            // AI Cutout Mode: Isolates person via Vision framework
            layer.borderColor = hasWhiteBorder ? NSColor.white.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
            layer.borderWidth = hasWhiteBorder ? 3.5 : 0

            backdropLayer.isHidden = true
            cameraShadowLayer.frame = bounds
            cameraShadowLayer.shadowOpacity = 0
            cameraClipLayer.frame = bounds
            cameraClipLayer.cornerRadius = outerRadius
            cameraClipLayer.borderWidth = 0
            previewLayer?.frame = bounds
            processedLayer.frame = bounds
            previewLayer?.isHidden = true
            processedLayer.isHidden = false
        }

        CATransaction.commit()
        window?.invalidateShadow()
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    // MARK: - Camera & Video Session

    func startCamera(preferredDevice: AVCaptureDevice? = nil) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                print("Camera access denied.")
                return
            }
            DispatchQueue.main.async {
                self?.configureSession(preferredDevice: preferredDevice)
            }
        }
    }

    func configureSession(preferredDevice: AVCaptureDevice? = nil) {
        session?.stopRunning()
        previewLayer?.removeFromSuperlayer()

        let newSession = AVCaptureSession()
        newSession.sessionPreset = .high

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        // Prioritize iPhone Continuity Camera if available
        let target: AVCaptureDevice? = preferredDevice ?? {
            if let iphone = discovery.devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains("iPhone") }) {
                return iphone
            }
            return discovery.devices.first
        }()

        guard let device = target else {
            print("No camera device found.")
            return
        }
        self.currentDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if newSession.canAddInput(input) {
                newSession.addInput(input)
            }

            // Video data output for AI background segmentation (used in AI Cutout mode)
            let vOutput = AVCaptureVideoDataOutput()
            vOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            vOutput.alwaysDiscardsLateVideoFrames = true
            vOutput.setSampleBufferDelegate(self, queue: processingQueue)
            if newSession.canAddOutput(vOutput) {
                newSession.addOutput(vOutput)
            }
            let isAiActive = isBackgroundActive && backgroundStyle == .aiCutout
            vOutput.connection(with: .video)?.isEnabled = isAiActive
            self.videoOutput = vOutput

            // Preview layer for standard / framed camera feed
            let pLayer = AVCaptureVideoPreviewLayer(session: newSession)
            pLayer.videoGravity = .resizeAspectFill
            pLayer.frame = cameraClipLayer.bounds
            pLayer.isHidden = isAiActive
            self.previewLayer = pLayer
            cameraClipLayer.insertSublayer(pLayer, at: 0)

            self.session = newSession

            DispatchQueue.global(qos: .userInitiated).async {
                newSession.startRunning()
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }

    // MARK: - Virtual Background AI Processing (AI Cutout Mode)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isBackgroundActive && backgroundStyle == .aiCutout else { return }
        guard !isProcessingFrame else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        isProcessingFrame = true
        processingQueue.async { [weak self] in
            defer { self?.isProcessingFrame = false }
            self?.processFrameWithVirtualBackground(pixelBuffer)
        }
    }

    func processFrameWithVirtualBackground(_ pixelBuffer: CVPixelBuffer) {
        var camImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Mirror horizontally if front-facing camera
        if currentDevice?.position != .back {
            camImage = camImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -camImage.extent.width, y: 0))
        }

        // Run person segmentation
        do {
            try sequenceHandler.perform([segmentationRequest], on: pixelBuffer)
        } catch {
            return
        }

        guard let maskObservation = segmentationRequest.results?.first as? VNPixelBufferObservation else {
            return
        }

        var maskImage = CIImage(cvPixelBuffer: maskObservation.pixelBuffer)
        if currentDevice?.position != .back {
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -maskImage.extent.width, y: 0))
        }

        // Scale mask to camera frame
        let scaleX = camImage.extent.width / maskImage.extent.width
        let scaleY = camImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Prepare background image
        let targetSize = camImage.extent.size
        let bgImage: CIImage

        if currentBackgroundPreset == .blur {
            bgImage = camImage.clampedToExtent().applyingGaussianBlur(sigma: 24.0).cropped(to: camImage.extent)
        } else if let ci = getBackgroundImageCI(for: currentBackgroundPreset, targetSize: targetSize) {
            bgImage = fitAndCrop(image: ci, targetSize: targetSize)
        } else {
            bgImage = CIImage(color: CIColor.black).cropped(to: camImage.extent)
        }

        // Blend person foreground with virtual background using segmentation mask
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return }
        blendFilter.setValue(camImage, forKey: kCIInputImageKey)
        blendFilter.setValue(bgImage, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        guard let outputImage = blendFilter.outputImage,
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isBackgroundActive && self.backgroundStyle == .aiCutout else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.processedLayer.contents = cgImage
            CATransaction.commit()
        }
    }

    func updateBackgroundState() {
        let isAiActive = isBackgroundActive && backgroundStyle == .aiCutout
        videoOutput?.connection(with: .video)?.isEnabled = isAiActive
        updateAppearance()
    }

    func setBackgroundPreset(_ preset: BackgroundPreset) {
        self.currentBackgroundPreset = preset
        updateBackgroundState()
    }

    func setCameraBackgroundStyle(_ style: CameraBackgroundStyle) {
        self.backgroundStyle = style
        updateBackgroundState()
    }

    func setFramePadding(_ padding: CGFloat) {
        self.framePadding = padding
        updateAppearance()
    }

    func setCustomBackgroundImage(_ image: NSImage, name: String) {
        self.customBackgroundImage = image
        self.customBackgroundName = name
        self.cachedCustomCIImage = ciImage(from: image)
        self.setBackgroundPreset(.custom)
    }

    @objc func selectCustomBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Set Background"
        panel.message = "Choose any image for your camera background"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                UserDefaults.standard.set(url.path, forKey: "CustomBackgroundImagePath")
                self.setCustomBackgroundImage(image, name: url.lastPathComponent)
            }
        }
    }

    @objc func clearCustomBackgroundImage() {
        UserDefaults.standard.removeObject(forKey: "CustomBackgroundImagePath")
        self.customBackgroundImage = nil
        self.customBackgroundName = nil
        self.cachedCustomCIImage = nil
        if currentBackgroundPreset == .custom {
            setBackgroundPreset(.none)
        } else {
            updateAppearance()
        }
    }

    @objc func cycleBackgroundPreset() {
        var presets: [BackgroundPreset] = [
            .none,
            .blur,
            .studioDark,
            .sunsetWarm,
            .cyberBlue
        ]
        if customBackgroundImage != nil {
            presets.append(.custom)
        }
        if let idx = presets.firstIndex(of: currentBackgroundPreset) {
            let next = presets[(idx + 1) % presets.count]
            setBackgroundPreset(next)
        } else {
            setBackgroundPreset(.none)
        }
    }

    @objc func toggleCameraBackgroundStyle() {
        setCameraBackgroundStyle(backgroundStyle == .backdropFrame ? .aiCutout : .backdropFrame)
    }

    // MARK: - Image Conversion Helpers

    func cgImage(from nsImage: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: nsImage.size)
        if let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }

    func ciImage(from nsImage: NSImage) -> CIImage? {
        guard let cg = cgImage(from: nsImage) else { return nil }
        return CIImage(cgImage: cg)
    }

    func getBackgroundImageCG(for preset: BackgroundPreset, targetSize: CGSize) -> CGImage? {
        switch preset {
        case .none, .blur:
            return nil
        case .studioDark:
            return createGradientCGImage(
                startColor: NSColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
                endColor: NSColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1.0),
                size: targetSize
            )
        case .sunsetWarm:
            return createGradientCGImage(
                startColor: NSColor(red: 0.85, green: 0.35, blue: 0.35, alpha: 1.0),
                endColor: NSColor(red: 0.25, green: 0.10, blue: 0.35, alpha: 1.0),
                size: targetSize
            )
        case .cyberBlue:
            return createGradientCGImage(
                startColor: NSColor(red: 0.08, green: 0.45, blue: 0.75, alpha: 1.0),
                endColor: NSColor(red: 0.03, green: 0.08, blue: 0.20, alpha: 1.0),
                size: targetSize
            )
        case .custom:
            if let custom = customBackgroundImage {
                return cgImage(from: custom)
            }
            return nil
        }
    }

    func getBackgroundImageCI(for preset: BackgroundPreset, targetSize: CGSize) -> CIImage? {
        switch preset {
        case .none, .blur:
            return nil
        case .studioDark:
            return createGradientCIImage(
                startColor: NSColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
                endColor: NSColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1.0),
                size: targetSize
            )
        case .sunsetWarm:
            return createGradientCIImage(
                startColor: NSColor(red: 0.85, green: 0.35, blue: 0.35, alpha: 1.0),
                endColor: NSColor(red: 0.25, green: 0.10, blue: 0.35, alpha: 1.0),
                size: targetSize
            )
        case .cyberBlue:
            return createGradientCIImage(
                startColor: NSColor(red: 0.08, green: 0.45, blue: 0.75, alpha: 1.0),
                endColor: NSColor(red: 0.03, green: 0.08, blue: 0.20, alpha: 1.0),
                size: targetSize
            )
        case .custom:
            return cachedCustomCIImage
        }
    }

    func fitAndCrop(image: CIImage, targetSize: CGSize) -> CIImage {
        let scaleX = targetSize.width / max(1, image.extent.width)
        let scaleY = targetSize.height / max(1, image.extent.height)
        let scale = max(scaleX, scaleY)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let cropRect = CGRect(
            x: scaled.extent.minX + (scaled.extent.width - targetSize.width) / 2.0,
            y: scaled.extent.minY + (scaled.extent.height - targetSize.height) / 2.0,
            width: targetSize.width,
            height: targetSize.height
        )
        let cropped = scaled.cropped(to: cropRect)
        return cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY))
    }

    func createGradientCGImage(startColor: NSColor, endColor: NSColor, size: CGSize) -> CGImage? {
        let safeSize = CGSize(width: max(100, size.width), height: max(100, size.height))
        let img = NSImage(size: safeSize)
        img.lockFocus()
        let grad = NSGradient(starting: startColor, ending: endColor)
        grad?.draw(in: NSRect(origin: .zero, size: safeSize), angle: 90)
        img.unlockFocus()
        return cgImage(from: img)
    }

    func createGradientCIImage(startColor: NSColor, endColor: NSColor, size: CGSize) -> CIImage? {
        guard let cg = createGradientCGImage(startColor: startColor, endColor: endColor, size: size) else { return nil }
        return CIImage(cgImage: cg)
    }

    // MARK: - Edge Detection and Cursor Handling

    func resizeEdge(for location: NSPoint) -> ResizeEdge {
        if isFullScreen { return .none }
        let pt = convert(location, from: nil)
        let w = bounds.width
        let h = bounds.height

        guard pt.x >= 0 && pt.x <= w && pt.y >= 0 && pt.y <= h else { return .none }

        let cornerZone: CGFloat = 20.0
        let edgeZone: CGFloat = 12.0

        let isLeftEdge = pt.x <= edgeZone
        let isRightEdge = pt.x >= w - edgeZone
        let isBottomEdge = pt.y <= edgeZone
        let isTopEdge = pt.y >= h - edgeZone

        let isCornerLeft = pt.x <= cornerZone
        let isCornerRight = pt.x >= w - cornerZone
        let isCornerBottom = pt.y <= cornerZone
        let isCornerTop = pt.y >= h - cornerZone

        // Check corners first
        if isCornerTop && isCornerRight { return .topRight }
        if isCornerTop && isCornerLeft { return .topLeft }
        if isCornerBottom && isCornerRight { return .bottomRight }
        if isCornerBottom && isCornerLeft { return .bottomLeft }

        // Check edges
        if isRightEdge { return .right }
        if isLeftEdge { return .left }
        if isTopEdge { return .top }
        if isBottomEdge { return .bottom }

        return .none
    }

    func cursor(for edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topRight, .bottomLeft:
            return BubbleView.diagonalNESWCursor
        case .topLeft, .bottomRight:
            return BubbleView.diagonalNWSECursor
        case .none:
            return .arrow
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if isFullScreen {
            NSCursor.arrow.set()
            return
        }
        let edge = resizeEdge(for: event.locationInWindow)
        cursor(for: edge).set()
    }

    override func mouseExited(with event: NSEvent) {
        if activeResizeEdge == .none {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Mouse Events (Dragging & Resizing)

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)

        // Double-click: Toggle Full Screen / Bubble
        if event.clickCount == 2 {
            toggleFullScreen()
            return
        }

        if isFullScreen {
            super.mouseDown(with: event)
            return
        }

        let edge = resizeEdge(for: event.locationInWindow)
        if edge != .none {
            activeResizeEdge = edge
            isDraggingWindow = false
            initialWindowFrame = window?.frame ?? .zero
            initialMouseLocation = NSEvent.mouseLocation
            cursor(for: edge).set()
        } else {
            activeResizeEdge = .none
            isDraggingWindow = true
            initialWindowOrigin = window?.frame.origin ?? .zero
            initialMouseLocation = NSEvent.mouseLocation
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isFullScreen {
            super.mouseDragged(with: event)
            return
        }

        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - initialMouseLocation.x
        let dy = currentMouse.y - initialMouseLocation.y

        if activeResizeEdge != .none, let window = self.window {
            let minW: CGFloat = 100
            let minH: CGFloat = 100
            let maxW: CGFloat = 1600
            let maxH: CGFloat = 1400

            let orig = initialWindowFrame
            var newOrigin = orig.origin
            var newSize = orig.size

            switch activeResizeEdge {
            case .right:
                newSize.width = max(minW, min(maxW, orig.size.width + dx))
            case .left:
                let targetW = max(minW, min(maxW, orig.size.width - dx))
                newOrigin.x = orig.origin.x + (orig.size.width - targetW)
                newSize.width = targetW
            case .top:
                newSize.height = max(minH, min(maxH, orig.size.height + dy))
            case .bottom:
                let targetH = max(minH, min(maxH, orig.size.height - dy))
                newOrigin.y = orig.origin.y + (orig.size.height - targetH)
                newSize.height = targetH
            case .topRight:
                newSize.width = max(minW, min(maxW, orig.size.width + dx))
                newSize.height = max(minH, min(maxH, orig.size.height + dy))
            case .topLeft:
                let targetW = max(minW, min(maxW, orig.size.width - dx))
                newOrigin.x = orig.origin.x + (orig.size.width - targetW)
                newSize.width = targetW
                newSize.height = max(minH, min(maxH, orig.size.height + dy))
            case .bottomRight:
                newSize.width = max(minW, min(maxW, orig.size.width + dx))
                let targetH = max(minH, min(maxH, orig.size.height - dy))
                newOrigin.y = orig.origin.y + (orig.size.height - targetH)
                newSize.height = targetH
            case .bottomLeft:
                let targetW = max(minW, min(maxW, orig.size.width - dx))
                newOrigin.x = orig.origin.x + (orig.size.width - targetW)
                newSize.width = targetW
                let targetH = max(minH, min(maxH, orig.size.height - dy))
                newOrigin.y = orig.origin.y + (orig.size.height - targetH)
                newSize.height = targetH
            case .none:
                return
            }

            // If Shift is pressed, lock to initial aspect ratio
            if event.modifierFlags.contains(.shift) && orig.size.height > 0 {
                let ratio = orig.size.width / orig.size.height
                if activeResizeEdge == .left || activeResizeEdge == .right {
                    let targetH = max(minH, round(newSize.width / ratio))
                    newOrigin.y -= (targetH - newSize.height) / 2
                    newSize.height = targetH
                } else if activeResizeEdge == .top || activeResizeEdge == .bottom {
                    let targetW = max(minW, round(newSize.height * ratio))
                    newOrigin.x -= (targetW - newSize.width) / 2
                    newSize.width = targetW
                } else {
                    let targetH = max(minH, round(newSize.width / ratio))
                    if activeResizeEdge == .bottomLeft || activeResizeEdge == .bottomRight {
                        newOrigin.y -= (targetH - newSize.height)
                    }
                    newSize.height = targetH
                }
            }

            currentShape = .freeform
            window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)
        } else if isDraggingWindow, let window = self.window {
            window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + dx, y: initialWindowOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        activeResizeEdge = .none
        isDraggingWindow = false
        if !isFullScreen {
            let edge = resizeEdge(for: event.locationInWindow)
            cursor(for: edge).set()
        }
        super.mouseUp(with: event)
    }

    // MARK: - Shape & Resizing Helpers

    func resizeBubble(toWidth newWidth: CGFloat) {
        if isFullScreen {
            toggleFullScreen()
        }
        let minWidth: CGFloat = 120
        let maxWidth: CGFloat = 900
        let clampedWidth = max(minWidth, min(maxWidth, newWidth))
        let clampedHeight: CGFloat
        if currentShape == .freeform, let window = self.window {
            let currentRatio = window.frame.width / max(1, window.frame.height)
            clampedHeight = round(clampedWidth / currentRatio)
        } else {
            clampedHeight = round(clampedWidth / currentShape.aspectRatio)
        }

        guard let window = self.window else { return }
        let oldFrame = window.frame
        let diffW = clampedWidth - oldFrame.width
        let diffH = clampedHeight - oldFrame.height
        let newOrigin = NSPoint(x: oldFrame.origin.x - diffW / 2, y: oldFrame.origin.y - diffH / 2)
        window.setFrame(NSRect(origin: newOrigin, size: CGSize(width: clampedWidth, height: clampedHeight)), display: true, animate: false)
    }

    func setShape(_ shape: BubbleShape) {
        self.currentShape = shape
        if !isFullScreen, let window = self.window {
            let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
            let targetWidth: CGFloat
            switch shape {
            case .rectangle16_9:
                targetWidth = max(window.frame.width, 360)
            case .portrait9_16:
                targetWidth = min(max(window.frame.width, 180), 240)
            case .rectangle4_3:
                targetWidth = max(window.frame.width, 300)
            case .circle, .roundedSquare:
                targetWidth = min(window.frame.width, 300)
            case .freeform:
                targetWidth = window.frame.width
            }
            let targetHeight = (shape == .freeform) ? window.frame.height : round(targetWidth / shape.aspectRatio)
            let newOrigin = NSPoint(x: center.x - targetWidth / 2, y: center.y - targetHeight / 2)
            window.setFrame(NSRect(origin: newOrigin, size: CGSize(width: targetWidth, height: targetHeight)), display: true, animate: true)
        }
        updateAppearance()
    }

    @objc func cycleShape() {
        let presets: [BubbleShape] = [.circle, .rectangle16_9, .portrait9_16, .roundedSquare, .rectangle4_3]
        if let idx = presets.firstIndex(of: currentShape) {
            let next = presets[(idx + 1) % presets.count]
            setShape(next)
        } else {
            setShape(.circle)
        }
    }

    @objc func toggleFullScreen() {
        guard let window = self.window, let screen = window.screen ?? NSScreen.main else { return }
        if isFullScreen {
            // Restore to floating corner bubble
            isFullScreen = false
            let restoreWidth: CGFloat = currentShape.presetWidth(for: 2)
            let restoreHeight = round(restoreWidth / currentShape.aspectRatio)
            var restoreFrame = savedBubbleFrame ?? NSRect(
                x: screen.visibleFrame.maxX - restoreWidth - 40,
                y: screen.visibleFrame.minY + 40,
                width: restoreWidth,
                height: restoreHeight
            )
            if currentShape != .freeform {
                restoreFrame.size.height = round(restoreFrame.size.width / currentShape.aspectRatio)
            }
            window.setFrame(restoreFrame, display: true, animate: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.updateAppearance()
            }
        } else {
            // Expand to Full Screen (for Intro / Outro)
            savedBubbleFrame = window.frame
            isFullScreen = true
            window.setFrame(screen.frame, display: true, animate: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.updateAppearance()
            }
        }
    }

    func handleKey(_ event: NSEvent) {
        let char = event.charactersIgnoringModifiers?.lowercased()
        if char == "f" || event.keyCode == 49 /* Space */ || event.keyCode == 53 /* Esc */ {
            toggleFullScreen()
        } else if char == "s" {
            cycleShape()
        } else if char == "v" {
            cycleBackgroundPreset()
        } else if char == "g" {
            toggleCameraBackgroundStyle()
        } else if char == "b" {
            toggleBorder()
        } else if char == "1" {
            setSmall()
        } else if char == "2" {
            setMedium()
        } else if char == "3" {
            setLarge()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if isFullScreen { return }
        let delta = event.deltaY + event.scrollingDeltaY
        if abs(delta) > 0.3 {
            let current = window?.frame.width ?? currentShape.presetWidth(for: 2)
            resizeBubble(toWidth: current + delta * 3.0)
        }
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let fsTitle = isFullScreen ? "Exit Full Screen (Double Click / F / Esc)" : "Enter Full Screen [Intro] (Double Click / F)"
        let fsItem = NSMenuItem(title: fsTitle, action: #selector(toggleFullScreen), keyEquivalent: "f")
        fsItem.target = self
        menu.addItem(fsItem)

        menu.addItem(NSMenuItem.separator())

        // Shape submenu
        let shapeSubmenu = NSMenu()
        for shape in BubbleShape.allCases {
            let item = NSMenuItem(title: shape.displayName, action: #selector(changeShapeMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shape
            if shape == currentShape {
                item.state = .on
            }
            shapeSubmenu.addItem(item)
        }
        let shapeItem = NSMenuItem(title: "Shape (S to cycle)", action: nil, keyEquivalent: "s")
        shapeItem.submenu = shapeSubmenu
        menu.addItem(shapeItem)

        // Background submenu
        let bgSubmenu = NSMenu()

        // Background Style Submenu
        let styleSubmenu = NSMenu()
        for style in CameraBackgroundStyle.allCases {
            let item = NSMenuItem(title: style.rawValue, action: #selector(changeCameraBackgroundStyleMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            if style == backgroundStyle {
                item.state = .on
            }
            styleSubmenu.addItem(item)
        }
        let styleItem = NSMenuItem(title: "Background Style (G to toggle)", action: nil, keyEquivalent: "g")
        styleItem.submenu = styleSubmenu
        bgSubmenu.addItem(styleItem)

        bgSubmenu.addItem(NSMenuItem.separator())

        for preset in BackgroundPreset.allCases {
            if preset == .custom && customBackgroundImage == nil {
                continue
            }
            let title: String
            if preset == .custom, let name = customBackgroundName {
                title = "Custom: \(name)"
            } else {
                title = preset.rawValue
            }
            let item = NSMenuItem(title: title, action: #selector(changeBackgroundPresetMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if preset == currentBackgroundPreset {
                item.state = .on
            }
            bgSubmenu.addItem(item)
        }

        bgSubmenu.addItem(NSMenuItem.separator())

        // Frame padding options
        let padSubmenu = NSMenu()
        let padOptions: [(String, CGFloat)] = [("Flush (0px)", 0), ("Compact (10px)", 10), ("Normal (18px)", 18), ("Wide (28px)", 28)]
        for (name, val) in padOptions {
            let item = NSMenuItem(title: name, action: #selector(changePaddingMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            if framePadding == val {
                item.state = .on
            }
            padSubmenu.addItem(item)
        }
        let padItem = NSMenuItem(title: "Frame Padding", action: nil, keyEquivalent: "")
        padItem.submenu = padSubmenu
        bgSubmenu.addItem(padItem)

        bgSubmenu.addItem(NSMenuItem.separator())
        let chooseItem = NSMenuItem(title: "Choose Custom Image...", action: #selector(selectCustomBackgroundImage), keyEquivalent: "")
        chooseItem.target = self
        bgSubmenu.addItem(chooseItem)

        if customBackgroundImage != nil {
            let clearItem = NSMenuItem(title: "Remove Custom Image", action: #selector(clearCustomBackgroundImage), keyEquivalent: "")
            clearItem.target = self
            bgSubmenu.addItem(clearItem)
        }

        let bgItem = NSMenuItem(title: "Background (V to cycle)", action: nil, keyEquivalent: "v")
        bgItem.submenu = bgSubmenu
        menu.addItem(bgItem)

        menu.addItem(NSMenuItem.separator())

        let w1 = Int(currentShape.presetWidth(for: 1))
        let h1 = Int(round(CGFloat(w1) / currentShape.aspectRatio))
        let small = NSMenuItem(title: "Small (\(w1)x\(h1))", action: #selector(setSmall), keyEquivalent: "1")
        small.target = self
        menu.addItem(small)

        let w2 = Int(currentShape.presetWidth(for: 2))
        let h2 = Int(round(CGFloat(w2) / currentShape.aspectRatio))
        let med = NSMenuItem(title: "Medium (\(w2)x\(h2))", action: #selector(setMedium), keyEquivalent: "2")
        med.target = self
        menu.addItem(med)

        let w3 = Int(currentShape.presetWidth(for: 3))
        let h3 = Int(round(CGFloat(w3) / currentShape.aspectRatio))
        let large = NSMenuItem(title: "Large (\(w3)x\(h3))", action: #selector(setLarge), keyEquivalent: "3")
        large.target = self
        menu.addItem(large)

        menu.addItem(NSMenuItem.separator())

        let camSubmenu = NSMenu()
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        for dev in discovery.devices {
            let item = NSMenuItem(title: dev.localizedName, action: #selector(switchCameraDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = dev
            if dev.uniqueID == currentDevice?.uniqueID {
                item.state = .on
            }
            camSubmenu.addItem(item)
        }
        let camItem = NSMenuItem(title: "Select Camera", action: nil, keyEquivalent: "")
        camItem.submenu = camSubmenu
        menu.addItem(camItem)

        menu.addItem(NSMenuItem.separator())

        let borderItem = NSMenuItem(title: hasWhiteBorder ? "Hide White Border" : "Show White Border", action: #selector(toggleBorder), keyEquivalent: "b")
        borderItem.target = self
        menu.addItem(borderItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Camera Bubble", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc func changeShapeMenuItem(_ sender: NSMenuItem) {
        if let shape = sender.representedObject as? BubbleShape {
            setShape(shape)
        }
    }

    @objc func changeBackgroundPresetMenuItem(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? BackgroundPreset {
            setBackgroundPreset(preset)
        }
    }

    @objc func changeCameraBackgroundStyleMenuItem(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? CameraBackgroundStyle {
            setCameraBackgroundStyle(style)
        }
    }

    @objc func changePaddingMenuItem(_ sender: NSMenuItem) {
        if let pad = sender.representedObject as? CGFloat {
            setFramePadding(pad)
        }
    }

    @objc func setSmall() {
        if isFullScreen { toggleFullScreen() }
        resizeBubble(toWidth: currentShape.presetWidth(for: 1))
    }

    @objc func setMedium() {
        if isFullScreen { toggleFullScreen() }
        resizeBubble(toWidth: currentShape.presetWidth(for: 2))
    }

    @objc func setLarge() {
        if isFullScreen { toggleFullScreen() }
        resizeBubble(toWidth: currentShape.presetWidth(for: 3))
    }

    @objc func toggleBorder() {
        hasWhiteBorder.toggle()
        updateAppearance()
    }

    @objc func switchCameraDevice(_ sender: NSMenuItem) {
        if let dev = sender.representedObject as? AVCaptureDevice {
            configureSession(preferredDevice: dev)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window: BubbleWindow!
    var bubbleView: BubbleView!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size: CGFloat = 220
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(
            x: screenFrame.maxX - size - 40,
            y: screenFrame.minY + 40,
            width: size,
            height: size
        )

        window = BubbleWindow(contentRect: rect)
        bubbleView = BubbleView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        window.bubbleView = bubbleView
        window.contentView = bubbleView
        window.makeKeyAndOrderFront(nil)

        bubbleView.startCamera()

        setupMenuBar()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let img = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "CameraBubble") {
                btn.image = img
            } else {
                btn.title = "Cam"
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let fsTitle = bubbleView.isFullScreen ? "Exit Full Screen (Double Click / F / Esc)" : "Enter Full Screen [Intro] (Double Click / F)"
        let fs = NSMenuItem(title: fsTitle, action: #selector(menuToggleFS), keyEquivalent: "f")
        fs.target = self
        menu.addItem(fs)

        menu.addItem(NSMenuItem.separator())

        // Shape submenu
        let shapeSubmenu = NSMenu()
        for shape in BubbleShape.allCases {
            let item = NSMenuItem(title: shape.displayName, action: #selector(menuSelectShape(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shape
            if shape == bubbleView.currentShape {
                item.state = .on
            }
            shapeSubmenu.addItem(item)
        }
        let shapeItem = NSMenuItem(title: "Shape", action: nil, keyEquivalent: "")
        shapeItem.submenu = shapeSubmenu
        menu.addItem(shapeItem)

        // Background submenu
        let bgSubmenu = NSMenu()

        let styleSubmenu = NSMenu()
        for style in CameraBackgroundStyle.allCases {
            let item = NSMenuItem(title: style.rawValue, action: #selector(menuSelectCameraBackgroundStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            if style == bubbleView.backgroundStyle {
                item.state = .on
            }
            styleSubmenu.addItem(item)
        }
        let styleItem = NSMenuItem(title: "Background Style (G)", action: nil, keyEquivalent: "g")
        styleItem.submenu = styleSubmenu
        bgSubmenu.addItem(styleItem)

        bgSubmenu.addItem(NSMenuItem.separator())

        for preset in BackgroundPreset.allCases {
            if preset == .custom && bubbleView.customBackgroundImage == nil {
                continue
            }
            let title: String
            if preset == .custom, let name = bubbleView.customBackgroundName {
                title = "Custom: \(name)"
            } else {
                title = preset.rawValue
            }
            let item = NSMenuItem(title: title, action: #selector(menuSelectBackgroundPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if preset == bubbleView.currentBackgroundPreset {
                item.state = .on
            }
            bgSubmenu.addItem(item)
        }
        bgSubmenu.addItem(NSMenuItem.separator())
        let chooseItem = NSMenuItem(title: "Choose Custom Image...", action: #selector(menuChooseCustomBackground), keyEquivalent: "")
        chooseItem.target = self
        bgSubmenu.addItem(chooseItem)

        if bubbleView.customBackgroundImage != nil {
            let clearItem = NSMenuItem(title: "Remove Custom Image", action: #selector(menuClearCustomBackground), keyEquivalent: "")
            clearItem.target = self
            bgSubmenu.addItem(clearItem)
        }

        let bgItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        bgItem.submenu = bgSubmenu
        menu.addItem(bgItem)

        menu.addItem(NSMenuItem.separator())

        let w1 = Int(bubbleView.currentShape.presetWidth(for: 1))
        let h1 = Int(round(CGFloat(w1) / bubbleView.currentShape.aspectRatio))
        let s1 = NSMenuItem(title: "Small (\(w1)x\(h1))", action: #selector(menuSmall), keyEquivalent: "1")
        s1.target = self
        menu.addItem(s1)

        let w2 = Int(bubbleView.currentShape.presetWidth(for: 2))
        let h2 = Int(round(CGFloat(w2) / bubbleView.currentShape.aspectRatio))
        let s2 = NSMenuItem(title: "Medium (\(w2)x\(h2))", action: #selector(menuMedium), keyEquivalent: "2")
        s2.target = self
        menu.addItem(s2)

        let w3 = Int(bubbleView.currentShape.presetWidth(for: 3))
        let h3 = Int(round(CGFloat(w3) / bubbleView.currentShape.aspectRatio))
        let s3 = NSMenuItem(title: "Large (\(w3)x\(h3))", action: #selector(menuLarge), keyEquivalent: "3")
        s3.target = self
        menu.addItem(s3)

        menu.addItem(NSMenuItem.separator())

        let camSubmenu = NSMenu()
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        for dev in discovery.devices {
            let item = NSMenuItem(title: dev.localizedName, action: #selector(menuSelectCamera(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = dev
            if dev.uniqueID == bubbleView.currentDevice?.uniqueID {
                item.state = .on
            }
            camSubmenu.addItem(item)
        }
        let camItem = NSMenuItem(title: "Select Camera", action: nil, keyEquivalent: "")
        camItem.submenu = camSubmenu
        menu.addItem(camItem)

        let borderTitle = bubbleView.hasWhiteBorder ? "Hide White Border" : "Show White Border"
        let borderItem = NSMenuItem(title: borderTitle, action: #selector(menuToggleBorder), keyEquivalent: "b")
        borderItem.target = self
        menu.addItem(borderItem)

        menu.addItem(NSMenuItem.separator())

        let q = NSMenuItem(title: "Quit Camera Bubble", action: #selector(menuQuit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
    }

    @objc func menuToggleFS() { bubbleView.toggleFullScreen() }
    @objc func menuSelectShape(_ sender: NSMenuItem) {
        if let shape = sender.representedObject as? BubbleShape {
            bubbleView.setShape(shape)
        }
    }
    @objc func menuSelectBackgroundPreset(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? BackgroundPreset {
            bubbleView.setBackgroundPreset(preset)
        }
    }
    @objc func menuSelectCameraBackgroundStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? CameraBackgroundStyle {
            bubbleView.setCameraBackgroundStyle(style)
        }
    }
    @objc func menuChooseCustomBackground() {
        bubbleView.selectCustomBackgroundImage()
    }
    @objc func menuClearCustomBackground() {
        bubbleView.clearCustomBackgroundImage()
    }
    @objc func menuSmall() { bubbleView.setSmall() }
    @objc func menuMedium() { bubbleView.setMedium() }
    @objc func menuLarge() { bubbleView.setLarge() }
    @objc func menuSelectCamera(_ sender: NSMenuItem) {
        bubbleView.switchCameraDevice(sender)
    }
    @objc func menuToggleBorder() { bubbleView.toggleBorder() }
    @objc func menuQuit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
