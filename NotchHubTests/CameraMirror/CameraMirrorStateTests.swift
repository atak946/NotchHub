import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import NotchHub

struct CameraMirrorStateTests {
    @Test(arguments: [
        (CameraAuthorization.notDetermined, CameraMirrorState.requestingAccess),
        (.authorized, .live),
        (.denied, .denied),
    ])
    func openFollowsAuthorization(authorization: CameraAuthorization, expected: CameraMirrorState) {
        #expect(CameraMirrorState.closed.reduce(.open(authorization)) == expected)
    }

    @Test func accessResultDecidesBetweenLiveAndDenied() {
        #expect(CameraMirrorState.requestingAccess.reduce(.accessResolved(granted: true)) == .live)
        #expect(CameraMirrorState.requestingAccess.reduce(.accessResolved(granted: false)) == .denied)
    }

    @Test func lateGrantAfterCloseNeverStartsTheCamera() {
        let closed = CameraMirrorState.requestingAccess.reduce(.close)

        #expect(closed.reduce(.accessResolved(granted: true)) == .closed)
    }

    @Test func closeAndTimeoutAlwaysClose() {
        for state in [CameraMirrorState.live, .requestingAccess, .denied, .unavailable] {
            #expect(state.reduce(.close) == .closed)
            #expect(state.reduce(.timedOut) == .closed)
        }
    }

    @Test func captureFailureOnlyAffectsLive() {
        #expect(CameraMirrorState.live.reduce(.captureFailed) == .unavailable)
        #expect(CameraMirrorState.closed.reduce(.captureFailed) == .closed)
    }

    @Test func reopeningWhileLiveStaysLive() {
        #expect(CameraMirrorState.live.reduce(.open(.authorized)) == .live)
        #expect(CameraMirrorState.requestingAccess.reduce(.open(.notDetermined)) == .requestingAccess)
    }

    @Test func onlyLiveRunsTheCamera() {
        #expect(CameraMirrorState.live.isCameraRunning)
        for state in [CameraMirrorState.closed, .requestingAccess, .denied, .unavailable] {
            #expect(!state.isCameraRunning)
        }
    }
}

final class FakeCameraCapture: CameraCapturing, @unchecked Sendable {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var failsOnStart = false

    var previewSession: AVCaptureSession? { nil }

    func start(onFailure: @escaping @MainActor @Sendable () -> Void) {
        startCount += 1
        if failsOnStart {
            MainActor.assumeIsolated { onFailure() }
        }
    }

    func stop() { stopCount += 1 }
}

final class FakeCameraAuthorizer: CameraAuthorizing {
    private let storage: Mutex<(status: CameraAuthorization, grants: Bool, requests: Int)>

    init(status: CameraAuthorization, grants: Bool = true) {
        storage = Mutex((status, grants, 0))
    }

    var status: CameraAuthorization { storage.withLock { $0.status } }
    var requestCount: Int { storage.withLock { $0.requests } }

    func requestAccess() async -> Bool {
        storage.withLock { value in
            value.requests += 1
            value.status = value.grants ? .authorized : .denied
            return value.grants
        }
    }
}

@MainActor
struct CameraMirrorServiceTests {
    private static let displayID: CGDirectDisplayID = 7
    private static let neverSleep: CameraMirrorService.Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }
    private static let noSleep: CameraMirrorService.Sleeper = { _ in }

    private let capture = FakeCameraCapture()

    private func makeService(_ authorizer: FakeCameraAuthorizer, sleep: @escaping CameraMirrorService.Sleeper = neverSleep) -> CameraMirrorService {
        let service = CameraMirrorService(capture: capture, authorizer: authorizer, sleep: sleep)
        service.displayResolver = { Self.displayID }
        return service
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test func nothingStartsWithoutAnExplicitOpen() {
        _ = makeService(FakeCameraAuthorizer(status: .authorized))

        #expect(capture.startCount == 0)
    }

    @Test func openStartsTheCameraOnTheResolvedDisplay() {
        let service = makeService(FakeCameraAuthorizer(status: .authorized))

        service.open()

        #expect(service.state == .live)
        #expect(service.isShown(on: Self.displayID))
        #expect(!service.isShown(on: Self.displayID + 1))
        #expect(capture.startCount == 1)
    }

    @Test func closeStopsTheCameraImmediately() {
        let service = makeService(FakeCameraAuthorizer(status: .authorized))
        service.open()

        service.close()

        #expect(service.state == .closed)
        #expect(capture.stopCount == 1)
        #expect(!service.isShown(on: Self.displayID))
    }

    @Test func noVisibleNotchMeansNoCamera() {
        let service = makeService(FakeCameraAuthorizer(status: .authorized))
        service.displayResolver = { nil }

        service.open()

        #expect(service.state == .closed)
        #expect(capture.startCount == 0)
    }

    @Test func notDeterminedRequestsAccessThenGoesLive() async {
        let authorizer = FakeCameraAuthorizer(status: .notDetermined)
        let service = makeService(authorizer)

        service.open()
        #expect(service.state == .requestingAccess)
        await settle()

        #expect(authorizer.requestCount == 1)
        #expect(service.state == .live)
        #expect(capture.startCount == 1)
    }

    @Test func deniedShowsThePermissionStateWithoutCamera() async {
        let service = makeService(FakeCameraAuthorizer(status: .notDetermined, grants: false))

        service.open()
        await settle()

        #expect(service.state == .denied)
        #expect(capture.startCount == 0)
    }

    @Test func autoClosesAfterTimeout() async {
        let service = makeService(FakeCameraAuthorizer(status: .authorized), sleep: Self.noSleep)

        service.open()
        await settle()

        #expect(service.state == .closed)
        #expect(capture.stopCount == 1)
    }

    @Test func captureFailureShowsUnavailable() {
        capture.failsOnStart = true
        let service = makeService(FakeCameraAuthorizer(status: .authorized))

        service.open()

        #expect(service.state == .unavailable)
    }
}
