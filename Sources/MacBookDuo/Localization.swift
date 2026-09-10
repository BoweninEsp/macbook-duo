import Foundation

/// Stable BCP 47 identifiers are stored instead of menu positions.
enum AppLanguage: String, CaseIterable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case spanish = "es"

    var label: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .spanish: "Español"
        }
    }

    static func resolve(saved: String?, preferred: [String]) -> Self {
        if let saved, let language = Self(rawValue: saved) { return language }
        for identifier in preferred {
            let parts = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-")
            switch parts.first {
            case "zh":
                if parts.contains("hans") { return .simplifiedChinese }
                return parts.contains(where: { ["hant", "tw", "hk", "mo"].contains(String($0)) }) ? .traditionalChinese : .simplifiedChinese
            case "en": return .english
            case "es": return .spanish
            default: continue
            }
        }
        return .english
    }

    private var column: Int {
        switch self {
        case .simplifiedChinese: 0
        case .traditionalChinese: 1
        case .english: 2
        case .spanish: 3
        }
    }

    func text(_ key: TextKey) -> String {
        guard let translations = Self.translations[key], translations.count == Self.allCases.count else {
            preconditionFailure("Missing translation: \(key)")
        }
        return translations[column]
    }

    func text(_ key: TextKey, angle: Int) -> String {
        text(key).replacingOccurrences(of: "{angle}", with: String(angle))
    }

    private static let translations: [TextKey: [String]] = [
        .title: [
            "让桌面，随开合舒展。",
            "讓桌面，隨開合舒展。",
            "Let your desktop unfold.",
            "Tu escritorio se despliega contigo."
        ],
        .subtitle: [
            "底边固定 · 透视折叠 · 渐变柔焦",
            "底邊固定 · 透視折疊 · 漸變柔焦",
            "Anchored base · Spatial perspective · Gradual defocus",
            "Base fija · Perspectiva espacial · Desenfoque gradual"
        ],
        .angle: [
            "开合角度",
            "開合角度",
            "Lid angle",
            "Ángulo de tapa"
        ],
        .play: [
            "播放",
            "播放",
            "Play",
            "Reproducir"
        ],
        .follow: [
            "跟随真实屏幕",
            "跟隨真實螢幕",
            "Follow real lid",
            "Seguir la tapa"
        ],
        .calibrate: [
            "将当前角度设为展开",
            "將目前角度設為展開",
            "Set current angle as open",
            "Usar este ángulo como apertura"
        ],
        .live: [
            "启用真实桌面",
            "啟用真實桌面",
            "Enable live desktop",
            "Activar escritorio real"
        ],
        .stop: [
            "停止真实桌面",
            "停止真實桌面",
            "Stop live desktop",
            "Detener escritorio real"
        ],
        .perspective: [
            "透视",
            "透視",
            "Perspective",
            "Perspectiva"
        ],
        .blur: [
            "柔焦",
            "柔焦",
            "Defocus",
            "Desenfoque"
        ],
        .shade: [
            "阴影",
            "陰影",
            "Shade",
            "Sombra"
        ],
        .footer: [
            "真实桌面需屏幕录制权限 · 菜单栏随时停止 · 图像只在内存中处理",
            "真實桌面需要螢幕錄製權限 · 選單列可隨時停止 · 圖像只在記憶體中處理",
            "Live desktop requires Screen Recording permission · Stop anytime from the menu bar · Frames stay in memory",
            "El escritorio real requiere permiso de grabación de pantalla. Puedes detenerlo desde la barra de menús. Los fotogramas solo se procesan en memoria."
        ],
        .sensor: [
            "传感器已连接 · 当前 {angle}°。拖动滑块预览，或选择跟随真实屏幕。",
            "感測器已連線 · 目前 {angle}°。拖動滑桿預覽，或選擇跟隨真實螢幕。",
            "Sensor connected · {angle}°. Drag the slider to preview, or follow the lid.",
            "Sensor conectado · {angle}°. Arrastra el control para probar el efecto o sigue el movimiento de la tapa."
        ],
        .manual: [
            "未读取到传感器，可使用手动预览。",
            "未讀取到感測器，可使用手動預覽。",
            "Lid sensor unavailable; manual preview is ready.",
            "Sensor no disponible; puedes usar la vista previa manual."
        ],
        .menuOpen: [
            "打开预览",
            "開啟預覽",
            "Open preview",
            "Abrir vista previa"
        ],
        .menuStop: [
            "停止桌面效果",
            "停止桌面效果",
            "Stop desktop effect",
            "Detener efecto de escritorio"
        ],
        .menuQuit: [
            "退出 MacBook Duo",
            "退出 MacBook Duo",
            "Quit MacBook Duo",
            "Salir de MacBook Duo"
        ],
        .calibrated: [
            "展开角度设为 {angle}°。低于此角度时开始折叠。",
            "展開角度設為 {angle}°。低於此角度時開始折疊。",
            "Open angle set to {angle}°. Folding starts below this angle.",
            "Ángulo de apertura establecido en {angle}°. El efecto comienza por debajo de este ángulo."
        ],
        .permission: [
            "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 MacBook Duo，然后重新打开应用。",
            "請在系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製中允許 MacBook Duo，然後重新開啟應用程式。",
            "Allow MacBook Duo in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app.",
            "Permite MacBook Duo en Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema, y vuelve a abrir la app."
        ],
        .enabled: [
            "桌面效果已启用。正常打开时自动隐藏；菜单栏可随时停止。",
            "桌面效果已啟用。正常開啟時自動隱藏；選單列可隨時停止。",
            "Desktop effect enabled. It hides when the lid is open; stop anytime from the menu bar.",
            "Efecto de escritorio activado. Se oculta al abrir la tapa; puedes detenerlo desde la barra de menús."
        ],
        .stopped: [
            "传感器读取中断，桌面效果已停止。",
            "感測器讀取中斷，桌面效果已停止。",
            "Sensor read interrupted; desktop effect stopped.",
            "Se interrumpió el sensor; el efecto se detuvo."
        ],
        .noDisplay: [
            "找不到内置显示屏。",
            "找不到內建顯示器。",
            "Built-in display not found.",
            "No se encontró la pantalla integrada."
        ],
        .captureError: [
            "无法启动桌面捕获：",
            "無法啟動桌面擷取：",
            "Could not start desktop capture: ",
            "No se pudo iniciar la captura: "
        ],
        .captureStopped: [
            "捕获停止：",
            "擷取停止：",
            "Capture stopped: ",
            "Captura detenida: "
        ],
        .language: [
            "语言",
            "語言",
            "Language",
            "Idioma"
        ],
        .pause: [
            "暂停",
            "暫停",
            "Pause",
            "Pausar"
        ],
        .disabled: [
            "桌面效果已停止，可继续手动预览。",
            "桌面效果已停止，可繼續手動預覽。",
            "Desktop effect stopped. You can still use the preview.",
            "Efecto detenido. Puedes seguir usando la vista previa."
        ],
        .starting: [
            "正在启动桌面效果…",
            "正在啟動桌面效果…",
            "Starting desktop effect…",
            "Iniciando el efecto…"
        ],
        .exclusionFailed: [
            "无法排除效果窗口，已停止以防止重复捕获画面。",
            "無法排除效果視窗，已停止以防止重複擷取畫面。",
            "Could not exclude the effect window. Capture stopped to prevent feedback.",
            "No se pudo excluir la ventana del efecto. La captura se ha detenido para evitar imágenes repetidas."
        ],
        .metalUnavailable: [
            "此 Mac 无法使用 Metal 图形渲染。",
            "此 Mac 無法使用 Metal 圖形繪製。",
            "Metal graphics are unavailable on this Mac.",
            "Los gráficos Metal no están disponibles en este Mac."
        ],
        .imageConversionFailed: [
            "无法准备预览图像。",
            "無法準備預覽圖像。",
            "Could not prepare the preview image.",
            "No se pudo preparar la imagen de vista previa."
        ],
        .textureAllocationFailed: [
            "无法分配图形内存。",
            "無法分配圖形記憶體。",
            "Could not allocate graphics memory.",
            "No se pudo reservar memoria gráfica."
        ],
        .errorTitle: [
            "无法完成操作",
            "無法完成操作",
            "Unable to complete the action",
            "No se pudo completar la acción"
        ],
        .ok: [
            "好",
            "好",
            "OK",
            "Aceptar"
        ],
    ]
}

enum TextKey: String, CaseIterable {
    case title
    case subtitle
    case angle
    case play
    case follow
    case calibrate
    case live
    case stop
    case perspective
    case blur
    case shade
    case footer
    case sensor
    case manual
    case menuOpen
    case menuStop
    case menuQuit
    case calibrated
    case permission
    case enabled
    case stopped
    case noDisplay
    case captureError
    case captureStopped
    case language
    case pause
    case disabled
    case starting
    case exclusionFailed
    case metalUnavailable
    case imageConversionFailed
    case textureAllocationFailed
    case errorTitle
    case ok
}

/// App-owned errors use the selected language; macOS error details retain the system language.
enum AppFailure: Error {
    case missingDisplay, exclusionFailed, metalUnavailable, imageConversionFailed, textureAllocationFailed

    var textKey: TextKey {
        switch self {
        case .missingDisplay: .noDisplay
        case .exclusionFailed: .exclusionFailed
        case .metalUnavailable: .metalUnavailable
        case .imageConversionFailed: .imageConversionFailed
        case .textureAllocationFailed: .textureAllocationFailed
        }
    }
}
