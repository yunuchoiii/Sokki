import AppKit
import CoreAudio
import AudioToolbox

/// 녹음 중에 재생 중인 다른 소리(음악·영상)를 낮춘다.
///
/// 에어팟은 마이크를 잡는 순간 macOS 가 통화 모드로 바꾸며 출력 볼륨을 알아서 낮추지만(0.50→0.40 실측),
/// 내장 스피커나 유선 출력은 아무 일도 없다. 그래서 기본 출력 장치의 볼륨을 직접 내렸다가 되돌린다.
/// 블루투스 장치는 macOS 가 이미 하므로 건드리지 않는다(겹치면 두 번 줄어든다).
enum AudioDucker {

    /// 녹음 중 볼륨 = 원래 볼륨 × 이 값
    static let factor: Float32 = 0.3

    private enum State {
        case volume(device: AudioDeviceID, original: Float32)   // 볼륨을 내렸다
        case paused                                             // 재생/일시정지 키로 멈췄다
    }
    private static var state: State?
    private static var pending: DispatchWorkItem?
    private static var preVolume: (device: AudioDeviceID, volume: Float32)?

    /// 녹음 시작 **전에** 부른다. 블루투스는 마이크를 잡은 뒤 macOS 가 알아서 줄이는지 비교하려면 시작 전 값이 필요하다.
    static func prepare() {
        let dev = defaultOutputDevice()
        preVolume = volume(of: dev).map { (dev, $0) }
    }

    /// 녹음 시작 직후에 부른다.
    /// - pauseWhenLocked: HDMI 모니터처럼 볼륨을 못 만지는 출력이면 재생/일시정지 키로 멈출지
    static func duck(pauseWhenLocked: Bool, device: AudioDeviceID? = nil) {
        guard state == nil, pending == nil else { return }
        let dev = device ?? defaultOutputDevice()
        guard dev != kAudioObjectUnknown else { return }

        if canSetVolume(dev) {
            if device == nil, isBluetooth(dev) {
                // 에어팟은 통화 모드로 바뀌며 macOS 가 낮춘다(0.50→0.40). 1초 뒤 실제로 줄었는지 보고, 안 줄었으면 우리가 줄인다.
                let pre = preVolume?.device == dev ? preVolume?.volume : nil
                let work = DispatchWorkItem {
                    pending = nil
                    guard state == nil else { return }
                    if let pre, let now = volume(of: dev), now < pre - 0.02 {
                        Log.write(String(format: "소리 줄이기 건너뜀 — macOS 가 이미 낮춤 %.2f → %.2f (%@)", pre, now, name(of: dev)))
                        return
                    }
                    duckVolume(dev)
                }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
            } else {
                duckVolume(dev)
            }
            return
        }

        // 볼륨 속성이 없는 출력(HDMI·DisplayPort). 소리가 나고 있을 때만 재생/일시정지 키를 보낸다 — 아니면 반대로 재생이 시작된다.
        guard pauseWhenLocked else {
            Log.write("소리 줄이기 불가 — \(name(of: dev)) 은 볼륨 조절이 안 되는 출력 (재생 멈춤 옵션 꺼짐)")
            return
        }
        guard isRunningSomewhere(dev) else {
            Log.write("재생 멈춤 생략 — \(name(of: dev)) 에서 나는 소리가 없음")
            return
        }
        if sendPlayPause() {
            state = .paused
            Log.write("재생 일시정지 — \(name(of: dev)) 은 볼륨 조절이 안 되는 출력이라 재생/일시정지 키로 멈춤")
        } else {
            Log.write("재생 멈춤 실패 — 미디어 키 이벤트를 보내지 못함 (손쉬운 사용 권한 확인)")
        }
    }

    private static func duckVolume(_ dev: AudioDeviceID) {
        guard let current = volume(of: dev), current > 0.02 else { return }
        state = .volume(device: dev, original: current)
        setVolume(dev, current * factor)
        Log.write(String(format: "소리 줄이기: %.2f → %.2f (%@)", current, current * factor, name(of: dev)))
    }

    /// 되돌린다. 녹음 중에 사용자가 볼륨을 직접 만졌으면 그 값을 존중해 건드리지 않는다.
    static func restore() {
        pending?.cancel()
        pending = nil
        preVolume = nil
        guard let s = state else { return }
        state = nil
        switch s {
        case .volume(let dev, let original):
            guard let current = volume(of: dev) else { return }
            if abs(current - original * factor) < 0.03 {
                setVolume(dev, original)
                Log.write(String(format: "소리 되돌림: %.2f → %.2f", current, original))
            } else {
                Log.write(String(format: "소리 되돌림 생략 — 녹음 중 볼륨이 바뀜 (%.2f)", current))
            }
        case .paused:
            if sendPlayPause() { Log.write("재생 다시 시작") } else { Log.write("재생 재개 실패 — 미디어 키 이벤트를 보내지 못함") }
        }
    }

    // MARK: - 미디어 키

    /// 키보드의 ⏯ 를 누른 것과 같다. NX_KEYTYPE_PLAY(16) 의 systemDefined 이벤트를 HID 탭에 넣는다.
    /// 손쉬운 사용 권한이 없으면 조용히 무시된다.
    @discardableResult
    static func sendPlayPause() -> Bool {
        let key: Int = 16   // NX_KEYTYPE_PLAY
        func post(down: Bool) -> Bool {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                                 windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1),
                  let cg = event.cgEvent else { return false }
            cg.post(tap: .cghidEventTap)
            return true
        }
        return post(down: true) && post(down: false)
    }

    // MARK: - CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
    }

    static func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func isBluetooth(_ dev: AudioDeviceID) -> Bool {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = address(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// HDMI·DisplayPort 모니터처럼 볼륨 조절이 안 되는 장치가 있다.
    static func canSetVolume(_ dev: AudioDeviceID) -> Bool {
        var addr = volumeAddress
        guard AudioObjectHasProperty(dev, &addr) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr else { return false }
        return settable.boolValue
    }

    /// 어떤 프로세스든 이 장치로 소리를 내는 중인지.
    static func isRunningSomewhere(_ dev: AudioDeviceID) -> Bool {
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr else { return false }
        return v != 0
    }

    static func volume(of dev: AudioDeviceID) -> Float32? {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = volumeAddress
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    @discardableResult
    static func setVolume(_ dev: AudioDeviceID, _ value: Float32) -> Bool {
        var v = max(0, min(1, value))
        var addr = volumeAddress
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    static func name(of dev: AudioDeviceID) -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var addr = address(kAudioObjectPropertyName)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name) == noErr else { return "장치 \(dev)" }
        return name as String
    }
}
