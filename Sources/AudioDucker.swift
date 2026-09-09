import Foundation
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

    private static var saved: (device: AudioDeviceID, volume: Float32)?

    /// 낮춘다. 이미 낮춘 상태면 아무것도 안 한다.
    static func duck(device: AudioDeviceID? = nil) {
        guard saved == nil else { return }
        let dev = device ?? defaultOutputDevice()
        guard dev != kAudioObjectUnknown else { return }
        if device == nil, isBluetooth(dev) {
            Log.write("소리 줄이기 건너뜀 — 블루투스 출력은 macOS 가 알아서 낮춘다")
            return
        }
        guard canSetVolume(dev), let current = volume(of: dev), current > 0.02 else { return }
        saved = (dev, current)
        setVolume(dev, current * factor)
        Log.write(String(format: "소리 줄이기: %.2f → %.2f (%@)", current, current * factor, name(of: dev)))
    }

    /// 되돌린다. 녹음 중에 사용자가 볼륨을 직접 만졌으면 그 값을 존중해 건드리지 않는다.
    static func restore() {
        guard let s = saved else { return }
        saved = nil
        guard let current = volume(of: s.device) else { return }
        if abs(current - s.volume * factor) < 0.03 {
            setVolume(s.device, s.volume)
            Log.write(String(format: "소리 되돌림: %.2f → %.2f", current, s.volume))
        } else {
            Log.write(String(format: "소리 되돌림 생략 — 녹음 중 볼륨이 바뀜 (%.2f)", current))
        }
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
