---
name: macos-menubar-preferences
description: macOS 메뉴바(NSStatusItem) 앱 + SwiftUI Preferences 윈도우 + UserDefaults 영속화 + Accessibility 권한 안내 UI를 구현할 때 사용하라. LSUIElement 앱(Dock 미표시), AppDelegate 진입점, NSColor의 Codable 저장(rgba 래퍼), 시스템 설정 딥링크를 다룬다. "메뉴바 앱", "NSStatusItem", "Preferences 화면", "LSUIElement", "설정 저장" 같은 키워드가 등장하면 반드시 이 스킬을 사용할 것.
---

# Menubar App & Preferences

`AppDelegate`, `MenuBarController`, `PreferencesView`, `PreferencesStore` 모듈 구현 가이드. `preferences-dev` 에이전트가 사용한다.

## LSUIElement 앱 설정

`Info.plist`에 추가:

```xml
<key>LSUIElement</key>
<true/>
```

효과:
- Dock 아이콘 사라짐
- 앱 전환(Cmd+Tab) 목록에서 제외
- 메뉴바 앱의 표준 형태

## AppDelegate 진입점

```swift
import AppKit
import SwiftUI

@main
struct KoreanOutlinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }                    // SwiftUI Settings 사용 X (수동 NSWindow 사용 권장)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var inputMonitor: InputSourceMonitor!
    private var windowTracker: FocusedWindowTracker!
    private var renderer: OverlayRenderer!
    private var preferencesStore: PreferencesStore!
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferencesStore = PreferencesStore()
        inputMonitor = InputSourceMonitor()
        windowTracker = FocusedWindowTracker()
        renderer = OverlayRenderer(
            inputMonitor: inputMonitor,
            windowTracker: windowTracker,
            preferencesStore: preferencesStore
        )

        inputMonitor.start()
        if windowTracker.permissionStatus == .granted {
            windowTracker.start()
        }
        renderer.start()

        menuBar = MenuBarController(
            onShowPreferences: { [weak self] in self?.showPreferences() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    func showPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView()
                .environmentObject(preferencesStore)
                .environmentObject(PermissionViewModel(tracker: windowTracker))
            let host = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: host)
            win.title = "Preferences"
            win.styleMask = [.titled, .closable, .resizable]
            win.setContentSize(NSSize(width: 420, height: 380))
            win.center()
            preferencesWindow = win
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

## MenuBarController

```swift
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onShowPreferences: () -> Void
    private let onQuit: () -> Void

    init(onShowPreferences: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShowPreferences = onShowPreferences
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Korean Outliner")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Preferences…", action: #selector(prefsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitAction), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func prefsAction() { onShowPreferences() }
    @objc private func quitAction() { onQuit() }
}
```

주의:
- `statusItem`을 강한 참조로 보관 (안 하면 메뉴바에서 사라짐)
- `target = self`를 NSMenuItem에 설정 (없으면 액션 미실행)

## NSColor를 Codable로 저장

`@AppStorage`는 NSColor 직접 지원 X. rgba 래퍼 사용:

```swift
struct ColorData: Codable, Equatable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        r = rgb.redComponent
        g = rgb.greenComponent
        b = rgb.blueComponent
        a = rgb.alphaComponent
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { nsColor.cgColor }
}
```

## PreferencesStore

```swift
final class PreferencesStore: ObservableObject {
    @Published var config: OverlayConfig {
        didSet { save() }
    }
    private let key = "OverlayConfig.v1"

    init() {
        self.config = Self.load() ?? .default
    }

    var publisher: AnyPublisher<OverlayConfig, Never> {
        $config.eraseToAnyPublisher()
    }

    private static func load() -> OverlayConfig? {
        guard let data = UserDefaults.standard.data(forKey: "OverlayConfig.v1") else { return nil }
        return try? JSONDecoder().decode(OverlayConfig.self, from: data)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension OverlayConfig {
    static var `default`: OverlayConfig {
        OverlayConfig(
            koreanColor: ColorData(.systemBlue),
            englishColor: ColorData(.systemRed),
            thickness: 3,
            sides: [.top, .bottom]
        )
    }
}
```

## PreferencesView (SwiftUI)

```swift
struct PreferencesView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var permission: PermissionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionSection
            colorSection
            thicknessSection
            sidesSection
        }
        .padding(20)
        .frame(width: 420)
    }

    private var permissionSection: some View {
        HStack {
            Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(permission.isGranted ? .green : .orange)
            Text(permission.isGranted ? "Accessibility 권한 허용됨" : "Accessibility 권한 필요")
            Spacer()
            if !permission.isGranted {
                Button("시스템 설정 열기") { AXPermission.openSystemSettings() }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading) {
            ColorPickerRow(title: "한글", color: Binding(
                get: { store.config.koreanColor.nsColor },
                set: { store.config.koreanColor = ColorData($0) }
            ))
            ColorPickerRow(title: "영문", color: Binding(
                get: { store.config.englishColor.nsColor },
                set: { store.config.englishColor = ColorData($0) }
            ))
        }
    }

    private var thicknessSection: some View {
        HStack {
            Text("두께")
            Slider(value: Binding(
                get: { Double(store.config.thickness) },
                set: { store.config.thickness = CGFloat($0) }
            ), in: 1...10, step: 1)
            Text("\(Int(store.config.thickness))pt")
        }
    }

    private var sidesSection: some View {
        VStack(alignment: .leading) {
            Text("표시 위치")
            HStack {
                Toggle("위", isOn: bindSide(.top))
                Toggle("아래", isOn: bindSide(.bottom))
                Toggle("왼쪽", isOn: bindSide(.leading))
                Toggle("오른쪽", isOn: bindSide(.trailing))
            }
        }
    }

    private func bindSide(_ side: OverlaySides) -> Binding<Bool> {
        Binding(
            get: { store.config.sides.contains(side) },
            set: { include in
                if include { store.config.sides.insert(side) }
                else { store.config.sides.remove(side) }
            }
        )
    }
}
```

## 권한 안내 ViewModel

```swift
final class PermissionViewModel: ObservableObject {
    @Published var isGranted: Bool
    private weak var tracker: FocusedWindowTracker?
    private var timer: Timer?

    init(tracker: FocusedWindowTracker) {
        self.tracker = tracker
        self.isGranted = tracker.permissionStatus == .granted
        // 시스템 설정에서 권한 변경은 알림이 없어 폴링 필요
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXPermission.status() == .granted
            if granted != self.isGranted {
                self.isGranted = granted
                if granted { self.tracker?.start() }
            }
        }
    }
    deinit { timer?.invalidate() }
}
```

> 권한 변경은 NotificationCenter 알림이 없어 폴링이 유일한 방법. 1.5초 간격으로 충분.

## 흔한 실수

| 실수 | 결과 | 수정 |
|------|------|------|
| `LSUIElement` 누락 | Dock에 아이콘 표시 | Info.plist에 추가 |
| `statusItem` 약한 참조 | 메뉴바 아이콘 사라짐 | 강한 참조 |
| `NSMenuItem`에 `target` 미설정 | 메뉴 클릭해도 반응 없음 | `target = self` |
| `@AppStorage` NSColor 직접 사용 | 컴파일 에러 | `ColorData` 래퍼 |
| Preferences 윈도우를 매번 새로 생성 | 메모리 누수 + 멀티 인스턴스 | `if preferencesWindow == nil`로 캐시 |
| 권한 상태를 한 번만 읽음 | 설정에서 변경해도 반영 X | 폴링 ViewModel |

## 산출물 위치

- `_workspace/modules/AppDelegate.swift`
- `_workspace/modules/MenuBarController.swift`
- `_workspace/modules/PreferencesView.swift`
- `_workspace/modules/PreferencesStore.swift`
- `_workspace/modules/PermissionViewModel.swift`
- `_workspace/modules/ColorData.swift`
- `_workspace/modules/Info.plist.additions.md`
