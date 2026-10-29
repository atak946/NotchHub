import CoreAudio
import Foundation

/// How an output device is connected; drives the icon.
enum AudioTransportKind: Int, Comparable, Sendable {
    case builtIn
    case bluetooth
    case usb
    case hdmi
    case airPlay
    case other

    init(transportType: UInt32) {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: self = .hdmi
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        default: self = .other
        }
    }

    static func < (lhs: AudioTransportKind, rhs: AudioTransportKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let name: String
    let isDefault: Bool
    let transport: AudioTransportKind

    /// SF Symbol for the device, recognising AirPods models by name.
    var systemImage: String {
        switch transport {
        case .bluetooth: Self.bluetoothImage(for: name)
        case .builtIn: "laptopcomputer"
        case .usb: "hifispeaker"
        case .hdmi: "tv"
        case .airPlay: "airplayaudio"
        case .other: "speaker.wave.2"
        }
    }

    func with(isDefault: Bool) -> AudioOutputDevice {
        AudioOutputDevice(id: id, name: name, isDefault: isDefault, transport: transport)
    }

    private static func bluetoothImage(for name: String) -> String {
        let lowered = name.lowercased()
        guard lowered.contains("airpods") else {
            return lowered.contains("beats") ? "beats.headphones" : "headphones"
        }
        if lowered.contains("max") { return "airpodsmax" }
        if lowered.contains("pro") { return "airpodspro" }
        return "airpods"
    }
}

/// Raw facts read from CoreAudio for one device.
struct AudioDeviceSnapshot: Equatable, Sendable {
    let id: AudioObjectID
    let name: String
    let transportType: UInt32
    let outputStreamCount: Int
}

enum AudioOutputDeviceList {
    /// Keeps devices that can play audio, marks the default one and orders them by transport, then name.
    static func make(from snapshots: [AudioDeviceSnapshot], defaultID: AudioObjectID?) -> [AudioOutputDevice] {
        snapshots
            .filter { $0.outputStreamCount > 0 && !$0.name.isEmpty }
            .map {
                AudioOutputDevice(
                    id: $0.id,
                    name: $0.name,
                    isDefault: $0.id == defaultID,
                    transport: AudioTransportKind(transportType: $0.transportType)
                )
            }
            .sorted { lhs, rhs in
                if lhs.transport != rhs.transport { return lhs.transport < rhs.transport }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Marks `defaultID` as default without re-reading the hardware.
    static func markingDefault(_ devices: [AudioOutputDevice], defaultID: AudioObjectID) -> [AudioOutputDevice] {
        devices.map { $0.with(isDefault: $0.id == defaultID) }
    }
}
