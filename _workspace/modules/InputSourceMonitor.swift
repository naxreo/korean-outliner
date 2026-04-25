//
//  InputSourceMonitor.swift
//  macos-korean-outliner — InputSourceMonitoring 구현체
//

import Carbon.HIToolbox
import Combine
import Foundation

public final class InputSourceMonitor: InputSourceMonitoring {

    private let subject = CurrentValueSubject<InputLanguage, Never>(.english)
    private var observer: NSObjectProtocol?
    private var isRunning = false

    public init() {}

    public var current: InputLanguage { subject.value }

    public var publisher: AnyPublisher<InputLanguage, Never> {
        subject.eraseToAnyPublisher()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        refreshCurrentSource()

        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCurrentSource()
        }
    }

    public func stop() {
        guard isRunning else { return }
        if let obs = observer {
            DistributedNotificationCenter.default().removeObserver(obs)
            observer = nil
        }
        isRunning = false
    }

    deinit { stop() }

    private func refreshCurrentSource() {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else {
            subject.send(.other(id: "unknown"))
            return
        }
        let source = unmanaged.takeRetainedValue()

        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            subject.send(.other(id: "unknown"))
            return
        }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        let languages = Self.languages(of: source)
        let next = Self.classify(sourceID: id, languages: languages)
        if next != subject.value {
            subject.send(next)
        }
    }

    /// 입력 소스의 BCP-47 언어 코드 배열을 추출한다.
    ///
    /// `TISGetInputSourceProperty`는 Get-규칙(unretained)이므로 `takeUnretainedValue()`로 가져온다.
    /// 반환 CFArray는 CFString을 담고 있으며, Swift 배열로 toll-free bridge된다.
    static func languages(of source: TISInputSource) -> [String] {
        guard let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        let cfArray = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue()
        return (cfArray as? [String]) ?? []
    }

    /// 입력 소스 ID + 언어 코드 배열을 사용해 한/영을 분류한다.
    ///
    /// 1순위: ID prefix 패턴(가장 신뢰도 높음 — Apple 표준 키레이아웃/IME)
    /// 2순위: `kTISPropertyInputSourceLanguages` 배열의 BCP-47 코드 ("ko", "en", ...)
    ///        Dvorak/Colemak/Czech-QWERTY 등 화이트리스트로 잡지 못한 영문 키보드를 정확히 `.english`로 분류.
    /// 그 외: `.other(id:)`로 폴백.
    static func classify(sourceID: String, languages: [String]) -> InputLanguage {
        // 1) ID 기반 강한 신호 — Apple 표준 한글 IME / 키레이아웃 prefix
        if sourceID.hasPrefix("com.apple.inputmethod.Korean")
            || sourceID.hasPrefix("com.apple.keylayout.Korean") {
            return .korean
        }

        // 2) BCP-47 언어 코드 — IME 이름이나 키레이아웃 화이트리스트에 의존하지 않음
        //    primary language(첫 항목)를 기준으로 판단. "ko" / "ko-KR" / "en" / "en-US" 등 prefix 매칭.
        if let primary = languages.first {
            if primary == "ko" || primary.hasPrefix("ko-") || primary.hasPrefix("ko_") {
                return .korean
            }
            if primary == "en" || primary.hasPrefix("en-") || primary.hasPrefix("en_") {
                return .english
            }
        }

        // 3) 폴백 — primary 언어 정보가 없거나 지원 외 언어
        return .other(id: sourceID)
    }
}
