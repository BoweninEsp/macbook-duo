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
    private var languagePopup: NSPopUpButton!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var angleTitle: NSTextField!
    private var playButton: NSButton!
    private var calibrateButton: NSButton!
    private var effectsTitles: [NSTextField] = []
    private var footerLabel: NSTextField!
    private var language = AppLanguage.resolve(saved: UserDefaults.standard.string(forKey: "appLanguage"), preferred: Locale.preferredLanguages)
    private var languageLabel: NSTextField!
    private var effectSliders: [NSSlider] = []
    private enum StatusMessage {
        case ready, text(TextKey), calibrated(Int), captureFailed(any Error), captureStopped(String)
    }
    private var currentStatus: StatusMessage = .ready
    private var menuOpenItem: NSMenuItem!
    private var menuStopItem: NSMenuItem!
    private var menuQuitItem: NSMenuItem!
    private var statusQuitItem: NSMenuItem!

    private func tr(_ key: TextKey) -> String { language.text(key) }

    private func errorText(_ error: any Error) -> String {
        if let failure = error as? AppFailure { return tr(failure.textKey) }
        return error.localizedDescription
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { preview = try FoldRenderer(size: NSSize(width: 660, height: 380)) }
        catch { showFatal(errorText(error)); return }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 810), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MacBook Duo"
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 25, left: 32, bottom: 24, right: 32)
        window.contentView = root
        titleLabel = NSTextField(labelWithString: tr(.title)); titleLabel.font = .systemFont(ofSize: 26, weight: .semibold); root.addArrangedSubview(titleLabel)
        subtitleLabel = NSTextField(labelWithString: tr(.subtitle)); subtitleLabel.textColor = .secondaryLabelColor; root.addArrangedSubview(subtitleLabel)
        let languageRow = NSStackView()
        languageRow.spacing = 10
        languageLabel = NSTextField(labelWithString: tr(.language))
        languageRow.addArrangedSubview(languageLabel)
        languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.label))
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: language) ?? 0)
        languagePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        languageRow.addArrangedSubview(languagePopup)
        root.addArrangedSubview(languageRow)
        preview.view.widthAnchor.constraint(equalToConstant: 676).isActive = true
        preview.view.heightAnchor.constraint(equalToConstant: 300).isActive = true
        preview.view.wantsLayer = true
        preview.view.layer?.cornerRadius = 14
        preview.view.layer?.masksToBounds = true
        root.addArrangedSubview(preview.view)
        do { try preview.setImage(Self.demoImage()) } catch { showFatal(errorText(error)) }
        let row = NSStackView()
        row.spacing = 12
        label = NSTextField(labelWithString: "105°")
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 58).isActive = true
        angleSlider = NSSlider(value: 105, minValue: 10, maxValue: 140, target: self, action: #selector(manualAngle))
        angleSlider.widthAnchor.constraint(equalToConstant: 320).isActive = true
        angleTitle = NSTextField(labelWithString: tr(.angle)); row.addArrangedSubview(angleTitle)
        angleTitle.widthAnchor.constraint(equalToConstant: 112).isActive = true
        row.addArrangedSubview(angleSlider)
        row.addArrangedSubview(label)
        playButton = NSButton(title: tr(.play), target: self, action: #selector(playDemo)); row.addArrangedSubview(playButton)
        playButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        root.addArrangedSubview(row)
        let controls = NSStackView()
        controls.spacing = 14
        follow = NSButton(checkboxWithTitle: tr(.follow), target: self, action: #selector(toggleFollow))
        follow.isEnabled = sensor.read() != nil
        controls.addArrangedSubview(follow)
        calibrateButton = NSButton(title: tr(.calibrate), target: self, action: #selector(calibrate)); controls.addArrangedSubview(calibrateButton)
        liveButton = NSButton(title: tr(.live), target: self, action: #selector(toggleLive))
        liveButton.bezelStyle = .rounded
        root.addArrangedSubview(controls)
        root.addArrangedSubview(liveButton)
        let effects = NSStackView()
        effects.spacing = 10
        for (index, key) in [TextKey.perspective, .blur, .shade].enumerated() {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 5
            let effectTitle = NSTextField(labelWithString: tr(key)); effectsTitles.append(effectTitle); column.addArrangedSubview(effectTitle)
            let slider = NSSlider(value: [1.0, 0.65, 0.4][index], minValue: 0, maxValue: 1, target: self, action: #selector(effectChanged(_:)))
            slider.tag = index
            slider.widthAnchor.constraint(equalToConstant: 218).isActive = true
            effectSliders.append(slider)
            column.addArrangedSubview(slider)
            effects.addArrangedSubview(column)
        }
        root.addArrangedSubview(effects)
        message = NSTextField(wrappingLabelWithString: "")
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 12)
        message.widthAnchor.constraint(equalToConstant: 670).isActive = true
        message.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        root.addArrangedSubview(message)
        footerLabel = NSTextField(wrappingLabelWithString: tr(.footer))
        footerLabel.widthAnchor.constraint(equalToConstant: 670).isActive = true
        footerLabel.font = .systemFont(ofSize: 12)
        footerLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(footerLabel)
        setupMenu()
        refreshLanguage()
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
        menuQuitItem = appMenu.addItem(withTitle: tr(.menuQuit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; main.addItem(item); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◩ Duo"
        let menu = NSMenu()
        menuOpenItem = menu.addItem(withTitle: tr(.menuOpen), action: #selector(showWindow), keyEquivalent: ""); menuOpenItem.target = self
        menuStopItem = menu.addItem(withTitle: tr(.menuStop), action: #selector(stopLive), keyEquivalent: ""); menuStopItem.target = self
        menu.addItem(.separator())
        statusQuitItem = menu.addItem(withTitle: tr(.menuQuit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard AppLanguage.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        language = AppLanguage.allCases[sender.indexOfSelectedItem]
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        refreshLanguage()
    }
    private func refreshLanguage() {
        titleLabel.stringValue = tr(.title); subtitleLabel.stringValue = tr(.subtitle); angleTitle.stringValue = tr(.angle)
        languageLabel.stringValue = tr(.language)
        languagePopup.setAccessibilityLabel(tr(.language))
        angleSlider.setAccessibilityLabel(tr(.angle))
        playButton.title = tr(demo ? .pause : .play); follow.title = tr(.follow); calibrateButton.title = tr(.calibrate)
        liveButton.title = tr(starting ? .starting : (live ? .stop : .live)); footerLabel.stringValue = tr(.footer)
        for (label, key) in zip(effectsTitles, [TextKey.perspective, .blur, .shade]) { label.stringValue = tr(key) }
        for (slider, key) in zip(effectSliders, [TextKey.perspective, .blur, .shade]) { slider.setAccessibilityLabel(tr(key)) }
        menuOpenItem.title = tr(.menuOpen); menuStopItem.title = tr(.menuStop); menuQuitItem.title = tr(.menuQuit)
        statusQuitItem.title = tr(.menuQuit)
        updateMessage()
    }
    private func setStatus(_ status: StatusMessage) {
        currentStatus = status
        updateMessage()
    }
    private func updateMessage() {
        guard let message else { return }
        switch currentStatus {
        case .ready:
            message.stringValue = sensor.read().map { language.text(.sensor, angle: Int($0)) } ?? tr(.manual)
        case .text(let key): message.stringValue = tr(key)
        case .calibrated(let angle): message.stringValue = language.text(.calibrated, angle: angle)
        case .captureFailed(let error): message.stringValue = tr(.captureError) + errorText(error)
        case .captureStopped(let detail): message.stringValue = tr(.captureStopped) + detail
        }
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
    @objc private func manualAngle() { demo = false; follow.state = .off; playButton.title = tr(.play) }
    @objc private func playDemo() { demo.toggle(); demoStart = Date(); follow.state = .off; playButton.title = tr(demo ? .pause : .play) }
    @objc private func toggleFollow() { demo = false; playButton.title = tr(.play) }
    @objc private func calibrate() {
        calibration = max(40, sensor.read() ?? angleSlider.doubleValue)
        setStatus(.calibrated(Int(calibration)))
    }
    private func tick() {
        var angle = angleSlider.doubleValue
        if demo { angle = 65 + 40 * cos(Date().timeIntervalSince(demoStart) * 1.25); angleSlider.doubleValue = angle }
        if follow.state == .on {
            guard let reading = sensor.read() else { stopLive(); setStatus(.text(.stopped)); follow.state = .off; return }
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
            setStatus(.text(.permission))
            return
        }
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else {
            setStatus(.text(.noDisplay)); return
        }
        starting = true
        liveButton.title = tr(.starting)
        setStatus(.text(.starting))
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
                capture.onFailure = { [weak self] error in self?.stopLive(); self?.setStatus(.captureStopped(error)) }
                try await capture.start(displayID: id, excluding: panel.windowNumber)
                guard starting else { await capture.stop(); panel.orderOut(nil); return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                live = true
                demo = false
                playButton.title = tr(.play)
                if sensor.read() != nil { follow.state = .on }
                liveButton.title = tr(.stop)
                setStatus(.text(.enabled))
            } catch {
                stopLive()
                setStatus(.captureFailed(error))
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
        liveButton?.title = tr(.live)
        liveButton?.isEnabled = true
        setStatus(.text(.disabled))
        Task { await capture.stop() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); sensor.close(); overlay?.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
    private func showFatal(_ text: String) {
        let alert = NSAlert()
        alert.messageText = tr(.errorTitle)
        alert.informativeText = text
        alert.addButton(withTitle: tr(.ok))
        alert.runModal()
    }
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
