import Testing
@testable import NotchHub

struct SystemDefinedKeyEventTests {
    /// Builds `data1` the way the HID system does: key code << 16 | state << 8 | repeat.
    private func data1(key: Int, state: Int, isRepeat: Bool = false) -> Int {
        (key << 16) | (state << 8) | (isRepeat ? 1 : 0)
    }

    @Test func decodesBrightnessUpKeyDown() throws {
        let event = try #require(SystemDefinedKeyEvent.decode(subtype: 8, data1: data1(key: 2, state: 0x0A)))

        #expect(event.key == .brightnessUp)
        #expect(event.isKeyDown)
        #expect(!event.isRepeat)
        #expect(event.hudKind == .brightness)
    }

    @Test func decodesKeyUpWithoutAHUD() throws {
        let event = try #require(SystemDefinedKeyEvent.decode(subtype: 8, data1: data1(key: 3, state: 0x0B)))

        #expect(event.key == .brightnessDown)
        #expect(!event.isKeyDown)
        #expect(event.hudKind == nil)
    }

    @Test func decodesRepeatFlag() throws {
        let event = try #require(SystemDefinedKeyEvent.decode(subtype: 8, data1: data1(key: 0, state: 0x0A, isRepeat: true)))

        #expect(event.isRepeat)
        #expect(event.hudKind == .volume)
    }

    @Test(arguments: [(0, HUDKind.volume), (1, .volume), (7, .volume), (2, .brightness), (3, .brightness),
                      (21, .keyboardBacklight), (22, .keyboardBacklight), (23, .keyboardBacklight)])
    func mapsKeysToHUDKinds(key: Int, kind: HUDKind) {
        #expect(SystemDefinedKeyEvent.decode(subtype: 8, data1: data1(key: key, state: 0x0A))?.hudKind == kind)
    }

    @Test func ignoresOtherSubtypes() {
        #expect(SystemDefinedKeyEvent.decode(subtype: 7, data1: data1(key: 2, state: 0x0A)) == nil)
    }

    @Test func ignoresUnknownKeyState() {
        #expect(SystemDefinedKeyEvent.decode(subtype: 8, data1: data1(key: 2, state: 0x01)) == nil)
    }

    @Test func unknownKeyCodeDecodesButShowsNoHUD() throws {
        // NX_KEYTYPE_PLAY (16) is a media key the HUD does not handle.
        let event = try #require(SystemDefinedKeyEvent.decode(subtype: 8, data1: data1(key: 16, state: 0x0A)))

        #expect(event.key == nil)
        #expect(event.hudKind == nil)
    }

    @Test func ignoresBitsAbove32() throws {
        let noisy = data1(key: 2, state: 0x0A) | (1 << 40)
        let event = try #require(SystemDefinedKeyEvent.decode(subtype: 8, data1: noisy))

        #expect(event.key == .brightnessUp)
    }
}
