import CoreAudio
import Testing
@testable import NotchHub

struct AudioOutputDeviceTests {
    @Test(arguments: [
        (kAudioDeviceTransportTypeBuiltIn, AudioTransportKind.builtIn),
        (kAudioDeviceTransportTypeBluetooth, .bluetooth),
        (kAudioDeviceTransportTypeBluetoothLE, .bluetooth),
        (kAudioDeviceTransportTypeUSB, .usb),
        (kAudioDeviceTransportTypeHDMI, .hdmi),
        (kAudioDeviceTransportTypeDisplayPort, .hdmi),
        (kAudioDeviceTransportTypeAirPlay, .airPlay),
        (kAudioDeviceTransportTypeVirtual, .other),
        (UInt32(0), .other),
    ])
    func classifiesTransport(_ transport: UInt32, expected: AudioTransportKind) {
        #expect(AudioTransportKind(transportType: transport) == expected)
    }

    @Test(arguments: [
        ("Deniz's AirPods Pro", AudioTransportKind.bluetooth, "airpodspro"),
        ("AirPods Max", .bluetooth, "airpodsmax"),
        ("AirPods", .bluetooth, "airpods"),
        ("Beats Studio", .bluetooth, "beats.headphones"),
        ("JBL Flip", .bluetooth, "headphones"),
        ("MacBook Pro Speakers", .builtIn, "laptopcomputer"),
        ("LG Monitor", .hdmi, "tv"),
        ("Scarlett 2i2", .usb, "hifispeaker"),
        ("Living Room", .airPlay, "airplayaudio"),
        ("BlackHole", .other, "speaker.wave.2"),
    ])
    func picksIcon(_ name: String, transport: AudioTransportKind, expected: String) {
        let device = AudioOutputDevice(id: 1, name: name, isDefault: false, transport: transport)
        #expect(device.systemImage == expected)
    }

    @Test func buildsSortedOutputListMarkingDefault() {
        let snapshots = [
            AudioDeviceSnapshot(id: 1, name: "Microphone", transportType: kAudioDeviceTransportTypeBuiltIn, outputStreamCount: 0),
            AudioDeviceSnapshot(id: 2, name: "AirPods", transportType: kAudioDeviceTransportTypeBluetooth, outputStreamCount: 1),
            AudioDeviceSnapshot(id: 3, name: "MacBook Pro Speakers", transportType: kAudioDeviceTransportTypeBuiltIn, outputStreamCount: 1),
            AudioDeviceSnapshot(id: 4, name: "", transportType: kAudioDeviceTransportTypeUSB, outputStreamCount: 2),
            AudioDeviceSnapshot(id: 5, name: "Anker", transportType: kAudioDeviceTransportTypeBluetooth, outputStreamCount: 1),
        ]

        let devices = AudioOutputDeviceList.make(from: snapshots, defaultID: 2)

        #expect(devices.map(\.id) == [3, 2, 5])
        #expect(devices.filter(\.isDefault).map(\.id) == [2])
    }

    @Test func marksNewDefaultImmutably() {
        let devices = [
            AudioOutputDevice(id: 1, name: "A", isDefault: true, transport: .builtIn),
            AudioOutputDevice(id: 2, name: "B", isDefault: false, transport: .bluetooth),
        ]

        let updated = AudioOutputDeviceList.markingDefault(devices, defaultID: 2)

        #expect(updated.map(\.isDefault) == [false, true])
        #expect(devices.map(\.isDefault) == [true, false])
    }
}
