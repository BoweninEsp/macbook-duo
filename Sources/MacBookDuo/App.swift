import AppKit

@main
struct MacBookDuo {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            let sensor = LidSensor()
            print(sensor.read().map { "Lid angle: \($0)°" } ?? "Lid sensor unavailable")
            sensor.close()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var preview: FoldRenderer!
    private var overlayRenderer: FoldRenderer?
    private var overlay: NSWindow?
    private let sensor = LidSensor()
    private let capture = DesktopCapture()
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private var angleSlider: NSSlider!
    private var label: NSTextField!
    private var message: NSTextField!
    private var follow: NSButton!
    private var liveButton: NSButton!
    private var calibration = 105.0
    private var smoothed: Float = 0
    private var live = false
    private var starting = false
    private var demo = false
    private var demoStart = Date()
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { preview = try FoldRenderer(size: NSSize(width: 660, height: 380)) }
        catch { showFatal(error.localizedDescription); return }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 750), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MacBook Duo"
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 25, left: 32, bottom: 24, right: 32)
        window.contentView = root
        let title = NSTextField(labelWithString: "让桌面，随开合舒展。")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        root.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "底边固定 · 透视折叠 · 渐变柔焦")
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)
        preview.view.widthAnchor.constraint(equalToConstant: 676).isActive = true
        preview.view.heightAnchor.constraint(equalToConstant: 360).isActive = true
        preview.view.wantsLayer = true
        preview.view.layer?.cornerRadius = 14
        preview.view.layer?.masksToBounds = true
        root.addArrangedSubview(preview.view)
        do { try preview.setImage(Self.demoImage()) } catch { showFatal(error.localizedDescription) }
        let row = NSStackView()
        row.spacing = 12
        label = NSTextField(labelWithString: "105°")
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 58).isActive = true
        angleSlider = NSSlider(value: 105, minValue: 10, maxValue: 140, target: self, action: #selector(manualAngle))
        angleSlider.widthAnchor.constraint(equalToConstant: 370).isActive = true
        row.addArrangedSubview(NSTextField(labelWithString: "开合角度"))
        row.addArrangedSubview(angleSlider)
        row.addArrangedSubview(label)
        row.addArrangedSubview(NSButton(title: "播放", target: self, action: #selector(playDemo)))
        root.addArrangedSubview(row)
        let controls = NSStackView()
        controls.spacing = 14
        follow = NSButton(checkboxWithTitle: "跟随真实屏幕", target: self, action: #selector(toggleFollow))
        follow.isEnabled = sensor.read() != nil
        controls.addArrangedSubview(follow)
        controls.addArrangedSubview(NSButton(title: "将当前角度设为展开", target: self, action: #selector(calibrate)))
        liveButton = NSButton(title: "启用真实桌面", target: self, action: #selector(toggleLive))
        liveButton.bezelStyle = .rounded
        controls.addArrangedSubview(liveButton)
        root.addArrangedSubview(controls)
        let effects = NSStackView()
        effects.spacing = 10
        for (index, title) in ["透视", "柔焦", "阴影"].enumerated() {
            effects.addArrangedSubview(NSTextField(labelWithString: title))
            let slider = NSSlider(value: [1.0, 0.65, 0.4][index], minValue: 0, maxValue: 1, target: self, action: #selector(effectChanged(_:)))
            slider.tag = index
            slider.widthAnchor.constraint(equalToConstant: 145).isActive = true
            effects.addArrangedSubview(slider)
        }
        root.addArrangedSubview(effects)
        message = NSTextField(wrappingLabelWithString: sensor.read().map { "传感器已连接 · 当前 \(Int($0))°。拖动滑块预览，或勾选跟随真实屏幕。" } ?? "未读取到传感器，可使用手动预览。")
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 12)
        message.widthAnchor.constraint(equalToConstant: 670).isActive = true
        root.addArrangedSubview(message)
        root.addArrangedSubview(NSTextField(labelWithString: "真实桌面需屏幕录制权限 · 菜单栏随时停止 · 图像只在内存中处理"))
        setupMenu()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.stopLive() }; return nil }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.stopLive() } }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(stopLive), name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopLive), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func setupMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 MacBook Duo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; main.addItem(item); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◩ Duo"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开预览", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "停止桌面效果", action: #selector(stopLive), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func effectChanged(_ sender: NSSlider) {
        for renderer in [preview, overlayRenderer].compactMap({ $0 }) {
            switch sender.tag {
            case 0: renderer.strength = sender.floatValue
            case 1: renderer.blur = sender.floatValue
            default: renderer.shade = sender.floatValue
            }
            renderer.render()
        }
    }
    @objc private func manualAngle() { demo = false; follow.state = .off }
    @objc private func playDemo() { demo.toggle(); demoStart = Date(); follow.state = .off }
    @objc private func toggleFollow() { demo = false }
    @objc private func calibrate() {
        calibration = max(40, sensor.read() ?? angleSlider.doubleValue)
        message.stringValue = "展开角度设为 \(Int(calibration))°。小于此角度时开始折叠。"
    }
    private func tick() {
        var angle = angleSlider.doubleValue
        if demo { angle = 65 + 40 * cos(Date().timeIntervalSince(demoStart) * 1.25); angleSlider.doubleValue = angle }
        if follow.state == .on {
            guard let reading = sensor.read() else { stopLive(); message.stringValue = "传感器读取中断，桌面效果已停止。"; follow.state = .off; return }
            angle = reading
            angleSlider.doubleValue = angle
        }
        label.stringValue = "\(Int(angle))°"
        let t = Float(min(1, max(0, (calibration-angle)/(calibration-10))))
        let target = t*t*(3-2*t)
        smoothed += (target-smoothed)*0.24
        if abs(target-smoothed)<0.0005 { smoothed = target }
        preview.fold = smoothed
        if window.isVisible { preview.render() }
        if live, let overlay, let renderer = overlayRenderer {
            renderer.fold = smoothed
            if smoothed > 0.002 { overlay.orderFrontRegardless(); renderer.render() }
            else { overlay.orderOut(nil) }
        }
    }
    @objc private func toggleLive() {
        if live { stopLive(); return }
        guard !starting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            message.stringValue = "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 MacBook Duo，然后重新打开应用。"
            return
        }
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else {
            message.stringValue = "找不到内置显示屏。"; return
        }
        starting = true
        liveButton.isEnabled = false
        Task {
            do {
                let renderer = try FoldRenderer(size: screen.frame.size)
                renderer.strength = preview.strength
                renderer.blur = preview.blur
                renderer.shade = preview.shade
                let panel = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                panel.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panel.backgroundColor = .black
                panel.ignoresMouseEvents = true
                panel.isReleasedWhenClosed = false
                panel.contentView = renderer.view
                overlay = panel
                overlayRenderer = renderer
                // Briefly register the window before building the capture exclusion filter.
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                capture.onFrame = { [weak self] buffer in self?.overlayRenderer?.setFrame(buffer) }
                capture.onFailure = { [weak self] error in self?.stopLive(); self?.message.stringValue = "捕获停止：\(error)" }
                try await capture.start(displayID: id, excluding: panel.windowNumber)
                guard starting else { await capture.stop(); panel.orderOut(nil); return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                live = true
                demo = false
                if sensor.read() != nil { follow.state = .on }
                liveButton.title = "停止真实桌面"
                message.stringValue = "桌面效果已启用。正常打开时自动隐藏；菜单栏可随时停止。"
            } catch {
                stopLive()
                message.stringValue = "无法启动桌面捕获：\(error.localizedDescription)"
            }
            starting = false
            liveButton.isEnabled = true
        }
    }
    @objc private func stopLive() {
        live = false
        starting = false
        overlay?.orderOut(nil)
        overlay = nil
        overlayRenderer = nil
        liveButton?.title = "启用真实桌面"
        liveButton?.isEnabled = true
        Task { await capture.stop() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); sensor.close(); overlay?.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
    private func showFatal(_ text: String) { let alert = NSAlert(); alert.messageText = text; alert.runModal() }
    private static func demoImage() -> CGImage {
        let image = NSImage(size: NSSize(width: 1352, height: 720))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: 1352, height: 720)
        NSGradient(colors: [NSColor(red: 0.16, green: 0.22, blue: 0.3, alpha: 1), NSColor(red: 0.55, green: 0.65, blue: 0.67, alpha: 1)])!.draw(in: rect, angle: 75)
        for i in (0..<5).reversed() {
            let path = NSBezierPath()
            let base = CGFloat(i)*60
            path.move(to: NSPoint(x: 0,y: base))
            path.curve(to: NSPoint(x: 1352,y: base+100), controlPoint1: NSPoint(x: 450,y: base+410), controlPoint2: NSPoint(x: 850,y: base-180))
            path.line(to: NSPoint(x: 1352,y: 0)); path.line(to: .zero); path.close()
            NSColor(calibratedWhite: 0.18+CGFloat(i)*0.08, alpha: 1).setFill(); path.fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 85, weight: .thin), .foregroundColor: NSColor.white]
        ("9:41" as NSString).draw(at: NSPoint(x: 580,y: 520), withAttributes: attrs)
        ("MACBOOK DUO" as NSString).draw(at: NSPoint(x: 585,y: 620), withAttributes: [.font:NSFont.systemFont(ofSize: 18,weight: .medium), .foregroundColor:NSColor.white])
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: 430,y: 20,width: 492,height: 65), xRadius: 20,yRadius: 20).fill()
        let colors: [NSColor] = [.systemBlue,.systemOrange,.systemGreen,.systemPurple,.systemPink,.systemTeal,.systemIndigo]
        for (i,color) in colors.enumerated() {
            color.setFill(); NSBezierPath(roundedRect: NSRect(x: 450+i*65,y: 31,width: 46,height: 44),xRadius: 11,yRadius: 11).fill()
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
