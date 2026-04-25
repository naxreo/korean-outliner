//
//  PreferencesView.swift
//  macos-korean-outliner — SwiftUI 설정 화면
//
//  권한 안내 / 마스터 토글 / 색상 / 두께 / 4방향 표시 위치를 한 화면에 배치.
//  값 변경은 즉시 PreferencesStore에 반영 → publisher 통해 OverlayRenderer 전파.
//
//  ColorData ↔ NSColor 변환은 `ColorData+Convert.swift`(공용)에 정의되어 있다.
//  ColorData ↔ SwiftUI.Color 변환만 본 파일에 file-private 헬퍼로 둔다.
//

import AppKit
import SwiftUI

public struct PreferencesView: View {

    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var permission: PermissionViewModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            permissionSection
            Divider()
            enableSection
            launchAtLoginSection
            Divider()
            colorSection
            Divider()
            thicknessSection
            lengthSection
            opacitySection
            Divider()
            sidesSection
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { launchAtLogin.refresh() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var permissionSection: some View {
        if permission.isGranted {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                Text("Accessibility 권한 허용됨")
                    .font(.system(size: 13))
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text("Accessibility 권한 필요")
                        .font(.system(size: 13))
                    Spacer()
                }
                Text("포커스 윈도우 추적을 위해 손쉬운 사용 권한이 필요합니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("권한 허용") {
                        permission.requestPermission()
                    }
                    Button("시스템 설정 열기") {
                        permission.openSystemSettings()
                    }
                    Spacer()
                }
                troubleshootingHint
            }
        }
    }

    /// 권한을 켰는데도 동작하지 않을 때 (코드 사인 mismatch / TCC 캐시 stale)
    /// 사용자가 자체 진단 + 자동 복구할 수 있는 도구를 제공.
    private var troubleshootingHint: some View {
        DisclosureGroup("권한을 허용했는데 동작하지 않나요?") {
            VStack(alignment: .leading, spacing: 8) {
                Text("앱을 새로 빌드한 경우 시스템이 이전 등록 정보와 일치하지 않아 권한이 무효화될 수 있습니다. 아래 버튼으로 권한 캐시를 초기화하고 앱을 재시작하세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button {
                    AXPermission.resetTCC()
                    AppRestart.relaunch()
                } label: {
                    Label("권한 캐시 초기화 후 재시작", systemImage: "arrow.clockwise.circle")
                }

                Divider()

                Text("수동 절차:")
                    .font(.system(size: 11, weight: .semibold))
                Text("1. 시스템 설정 → 손쉬운 사용에서 'Korean Outliner' 항목을 '−'로 제거")
                Text("2. 앱을 /Applications로 옮기고 거기서 실행 (빌드 폴더 X)")
                Text("3. '권한 허용' 또는 '시스템 설정 열기'로 다시 허용")
                Text("4. 그래도 안 되면 터미널에서: tccutil reset Accessibility \(Bundle.main.bundleIdentifier ?? "")")
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)

                Divider()

                diagnosticsBlock
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .font(.system(size: 11))
        .padding(.top, 4)
    }

    /// 진단 정보 — 사용자가 GitHub Issue 등에 첨부할 수 있도록 표시.
    private var diagnosticsBlock: some View {
        let d = AXPermission.diagnostics()
        return VStack(alignment: .leading, spacing: 2) {
            Text("진단 정보")
                .font(.system(size: 11, weight: .semibold))
            Text("• Bundle ID: \(d.bundleID)")
            Text("• 경로: \(d.bundlePath)")
                .lineLimit(2)
            Text("• AXIsProcessTrusted: \(d.trustedRaw ? "true" : "false")")
            Text("• AXIsProcessTrustedWithOptions: \(d.trustedWithOptions ? "true" : "false")")
            if !d.bundlePath.hasPrefix("/Applications/") {
                Text("⚠️ /Applications 외부에서 실행 중입니다. TCC 권한이 불안정할 수 있습니다.")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .textSelection(.enabled)
    }

    private var enableSection: some View {
        Toggle(isOn: bind(\.isEnabled)) {
            Text("외곽선 표시 활성화")
        }
        .toggleStyle(.switch)
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            )) {
                Text("로그인 시 자동 실행")
            }
            .toggleStyle(.switch)

            if let reason = launchAtLogin.disabledReason {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker(
                "한글 입력 색상",
                selection: Binding(
                    get: { store.config.koreanColor.swiftUIColor },
                    set: { store.config.koreanColor = ColorData(swiftUI: $0) }
                ),
                supportsOpacity: true
            )
            ColorPicker(
                "영문 입력 색상",
                selection: Binding(
                    get: { store.config.englishColor.swiftUIColor },
                    set: { store.config.englishColor = ColorData(swiftUI: $0) }
                ),
                supportsOpacity: true
            )
        }
        .disabled(!store.config.isEnabled)
    }

    private var thicknessSection: some View {
        HStack {
            Text("두께")
            Slider(
                value: Binding(
                    get: { Double(store.config.thickness) },
                    set: { store.config.thickness = CGFloat($0) }
                ),
                in: 1...10,
                step: 1
            )
            Text("\(Int(store.config.thickness))pt")
                .frame(width: 48, alignment: .trailing)
                .monospacedDigit()
        }
        .disabled(!store.config.isEnabled)
    }

    private var lengthSection: some View {
        HStack {
            Text("길이")
            Slider(
                value: Binding(
                    get: { Double(store.config.lengthRatio) },
                    set: { store.config.lengthRatio = CGFloat($0) }
                ),
                in: 0.05...1.0
            )
            Text("\(Int((store.config.lengthRatio * 100).rounded()))%")
                .frame(width: 48, alignment: .trailing)
                .monospacedDigit()
        }
        .disabled(!store.config.isEnabled)
    }

    private var opacitySection: some View {
        HStack {
            Text("투명도")
            Slider(
                value: Binding(
                    get: { Double(store.config.opacity) },
                    set: { store.config.opacity = CGFloat($0) }
                ),
                in: 0.05...1.0
            )
            Text("\(Int((store.config.opacity * 100).rounded()))%")
                .frame(width: 48, alignment: .trailing)
                .monospacedDigit()
        }
        .disabled(!store.config.isEnabled)
    }

    private var sidesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("표시 위치")
            HStack(spacing: 16) {
                Toggle("위", isOn: bindSide(.top))
                Toggle("아래", isOn: bindSide(.bottom))
                Toggle("왼쪽", isOn: bindSide(.leading))
                Toggle("오른쪽", isOn: bindSide(.trailing))
            }
        }
        .disabled(!store.config.isEnabled)
    }

    // MARK: - Binding helpers

    private func bind<T>(_ keyPath: WritableKeyPath<OverlayConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { store.config[keyPath: keyPath] = $0 }
        )
    }

    private func bindSide(_ side: OverlaySides) -> Binding<Bool> {
        Binding(
            get: { store.config.sides.contains(side) },
            set: { include in
                var sides = store.config.sides
                if include { sides.insert(side) } else { sides.remove(side) }
                store.config.sides = sides
            }
        )
    }
}

// MARK: - SwiftUI.Color ↔ ColorData (file-private)

private extension ColorData {
    /// SwiftUI.Color → ColorData. NSColor 경유 후 sRGB 강제.
    /// 라벨을 `swiftUI:`로 둔 이유: `ColorData+Convert.swift`의 `init(_ NSColor)`와
    /// 시그니처 충돌을 피하기 위함 (NSColor와 Color는 사촌 타입이라 추론 모호함).
    init(swiftUI color: Color) {
        // NSColor(_:) 는 SwiftUI.Color → NSColor 컨버전. 그 후 공용 init(_ NSColor) 위임.
        self.init(NSColor(color))
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
