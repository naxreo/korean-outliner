//
//  PreferencesStore.swift
//  macos-korean-outliner — PreferencesStoring 구현체
//
//  UserDefaults에 OverlayConfig를 JSON으로 영속화하고,
//  CurrentValueSubject 기반 publisher를 노출한다.
//
//  계약 보강 (review-major-3):
//  - publisher emit은 즉시 (overlay 렌더링이 ColorPicker 드래그에 즉각 반응해야 함)
//  - UserDefaults 영속화는 150ms 디바운스 (드래그 중 초당 수십 회 인코딩/디스크 write 방지)
//  - 마지막 변경 후 150ms 동안 추가 변경이 없으면 그때 한 번 save 수행
//
//  ColorData ↔ NSColor / CGColor 변환은 `ColorData+Convert.swift`(overlay-renderer-dev 작성)
//  에서 단일 정의되므로 본 파일에서는 NSColor 변환 코드를 추가하지 않는다.
//

import Combine
import Foundation

public final class PreferencesStore: ObservableObject, PreferencesStoring {

    private let subject: CurrentValueSubject<OverlayConfig, Never>
    private let defaults: UserDefaults
    private let key: String

    /// 영속화 디바운스용 work item — 매 set에서 cancel & 재예약.
    private var saveDebouncer: DispatchWorkItem?
    /// 디바운스 지연 (ColorPicker 드래그 종료 후 디스크 write).
    private let saveDebounceDelay: TimeInterval = 0.15

    /// SwiftUI 양방향 바인딩용 computed property.
    /// objectWillChange + subject.send (즉시) + 영속화(디바운스) 순서로 트리거.
    public var config: OverlayConfig {
        get { subject.value }
        set {
            guard newValue != subject.value else { return }
            objectWillChange.send()
            subject.send(newValue)        // 1) 구독자 즉시 emit (overlay 렌더링 응답성 보장)
            scheduleSave(newValue)        // 2) UserDefaults 디스크 쓰기는 디바운스
        }
    }

    public var current: OverlayConfig { subject.value }

    public var publisher: AnyPublisher<OverlayConfig, Never> {
        subject.eraseToAnyPublisher()
    }

    public init(defaults: UserDefaults = .standard, key: String = "OverlayConfig.v1") {
        self.defaults = defaults
        self.key = key
        let loaded = Self.load(key: key, defaults: defaults) ?? .default
        self.subject = CurrentValueSubject<OverlayConfig, Never>(loaded)
    }

    /// PreferencesStoring 프로토콜 진입점. 외부에서 비-SwiftUI 경로로 갱신할 때 사용.
    public func update(_ config: OverlayConfig) {
        self.config = config
    }

    /// 앱 종료 시 미처 flush되지 않은 변경분을 디스크에 즉시 저장.
    /// AppDelegate.applicationWillTerminate에서 호출 권장.
    public func flush() {
        saveDebouncer?.cancel()
        saveDebouncer = nil
        save(subject.value)
    }

    // MARK: - Persistence

    private static func load(key: String, defaults: UserDefaults) -> OverlayConfig? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(OverlayConfig.self, from: data)
        } catch {
            NSLog("[PreferencesStore] decode failed, falling back to default: \(error)")
            return nil
        }
    }

    private func scheduleSave(_ config: OverlayConfig) {
        saveDebouncer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.save(config)
        }
        saveDebouncer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceDelay, execute: item)
    }

    private func save(_ config: OverlayConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: key)
        } catch {
            NSLog("[PreferencesStore] encode/save failed: \(error)")
        }
    }
}
