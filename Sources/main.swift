import Cocoa
import AVFoundation

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
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        bubbleView?.handleKey(event)
    }
}

/// The main content view managing camera capture session, circular masking, resizing, and interactions.
class BubbleView: NSView {
    var session: AVCaptureSession?
    var currentDevice: AVCaptureDevice?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var hasWhiteBorder = true
    var isFullScreen = false
    var savedBubbleFrame: NSRect?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        updateAppearance()
    }

    func updateAppearance() {
        guard let layer = self.layer else { return }
        if isFullScreen {
            layer.cornerRadius = 0
            layer.borderWidth = 0
            layer.masksToBounds = true
        } else {
            layer.cornerRadius = bounds.width / 2.0
            layer.masksToBounds = true
            if hasWhiteBorder {
                layer.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
                layer.borderWidth = 3.5
            } else {
                layer.borderWidth = 0
            }
        }
        previewLayer?.frame = bounds
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

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
            let pLayer = AVCaptureVideoPreviewLayer(session: newSession)
            pLayer.videoGravity = .resizeAspectFill
            pLayer.frame = self.bounds
            self.previewLayer = pLayer
            self.layer?.addSublayer(pLayer)
            self.session = newSession

            DispatchQueue.global(qos: .userInitiated).async {
                newSession.startRunning()
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }

    func resizeBubble(to newSize: CGFloat) {
        if isFullScreen {
            toggleFullScreen()
        }
        let clamped = max(130, min(650, newSize))
        guard let window = self.window else { return }
        let oldFrame = window.frame
        let diff = clamped - oldFrame.width
        let newOrigin = NSPoint(x: oldFrame.origin.x - diff / 2, y: oldFrame.origin.y - diff / 2)
        window.setFrame(NSRect(origin: newOrigin, size: CGSize(width: clamped, height: clamped)), display: true, animate: false)
    }

    @objc func toggleFullScreen() {
        guard let window = self.window, let screen = window.screen ?? NSScreen.main else { return }
        if isFullScreen {
            // Restore to floating corner bubble
            isFullScreen = false
            let restoreFrame = savedBubbleFrame ?? NSRect(
                x: screen.visibleFrame.maxX - 260,
                y: screen.visibleFrame.minY + 40,
                width: 220,
                height: 220
            )
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

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)

        // Double-click: Toggle Full Screen / Bubble
        if event.clickCount == 2 {
            toggleFullScreen()
            return
        }
        super.mouseDown(with: event)
    }

    func handleKey(_ event: NSEvent) {
        let char = event.charactersIgnoringModifiers?.lowercased()
        if char == "f" || event.keyCode == 49 /* Space */ || event.keyCode == 53 /* Esc */ {
            toggleFullScreen()
        } else if char == "1" {
            if isFullScreen { toggleFullScreen() }
            resizeBubble(to: 170)
        } else if char == "2" {
            if isFullScreen { toggleFullScreen() }
            resizeBubble(to: 280)
        } else if char == "3" {
            if isFullScreen { toggleFullScreen() }
            resizeBubble(to: 420)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if isFullScreen { return }
        let delta = event.deltaY + event.scrollingDeltaY
        if abs(delta) > 0.3 {
            let current = window?.frame.width ?? 220
            resizeBubble(to: current + delta * 2.5)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let fsTitle = isFullScreen ? "Exit Full Screen (Double Click / F / Esc)" : "Enter Full Screen [Intro] (Double Click / F)"
        let fsItem = NSMenuItem(title: fsTitle, action: #selector(toggleFullScreen), keyEquivalent: "f")
        fsItem.target = self
        menu.addItem(fsItem)

        menu.addItem(NSMenuItem.separator())

        let small = NSMenuItem(title: "Small Bubble (170px)", action: #selector(setSmall), keyEquivalent: "1")
        small.target = self
        menu.addItem(small)

        let med = NSMenuItem(title: "Medium Bubble (280px)", action: #selector(setMedium), keyEquivalent: "2")
        med.target = self
        menu.addItem(med)

        let large = NSMenuItem(title: "Large Bubble (420px)", action: #selector(setLarge), keyEquivalent: "3")
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

    @objc func setSmall() { resizeBubble(to: 170) }
    @objc func setMedium() { resizeBubble(to: 280) }
    @objc func setLarge() { resizeBubble(to: 420) }

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

class AppDelegate: NSObject, NSApplicationDelegate {
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
        let fs = NSMenuItem(title: "Toggle Full Screen / Bubble", action: #selector(menuToggleFS), keyEquivalent: "f")
        fs.target = self
        menu.addItem(fs)

        menu.addItem(NSMenuItem.separator())

        let s1 = NSMenuItem(title: "Small Bubble", action: #selector(menuSmall), keyEquivalent: "1")
        s1.target = self
        menu.addItem(s1)

        let s2 = NSMenuItem(title: "Medium Bubble", action: #selector(menuMedium), keyEquivalent: "2")
        s2.target = self
        menu.addItem(s2)

        let s3 = NSMenuItem(title: "Large Bubble", action: #selector(menuLarge), keyEquivalent: "3")
        s3.target = self
        menu.addItem(s3)

        menu.addItem(NSMenuItem.separator())

        let q = NSMenuItem(title: "Quit Camera Bubble", action: #selector(menuQuit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)

        statusItem.menu = menu
    }

    @objc func menuToggleFS() { bubbleView.toggleFullScreen() }
    @objc func menuSmall() { bubbleView.setSmall() }
    @objc func menuMedium() { bubbleView.setMedium() }
    @objc func menuLarge() { bubbleView.setLarge() }
    @objc func menuQuit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
