import AVFoundation
import EventKit
import Foundation
import Testing
import UserNotifications
@testable import NotchHub

struct PermissionStatusMappingTests {
    @Test(arguments: [
        (EKAuthorizationStatus.fullAccess, PermissionStatus.granted),
        (.notDetermined, .notDetermined),
        (.denied, .denied),
        (.restricted, .denied),
        (.writeOnly, .denied),
    ])
    func calendar(status: EKAuthorizationStatus, expected: PermissionStatus) {
        #expect(PermissionStatusMapping.calendar(status) == expected)
    }

    @Test(arguments: [
        (UNAuthorizationStatus.authorized, PermissionStatus.granted),
        (.provisional, .granted),
        (.notDetermined, .notDetermined),
        (.denied, .denied),
    ])
    func notifications(status: UNAuthorizationStatus, expected: PermissionStatus) {
        #expect(PermissionStatusMapping.notifications(status) == expected)
    }

    @Test(arguments: [
        (AVAuthorizationStatus.authorized, PermissionStatus.granted),
        (.notDetermined, .notDetermined),
        (.denied, .denied),
        (.restricted, .denied),
    ])
    func camera(status: AVAuthorizationStatus, expected: PermissionStatus) {
        #expect(PermissionStatusMapping.camera(status) == expected)
    }

    @Test func accessibility() {
        #expect(PermissionStatusMapping.accessibility(isTrusted: true) == .granted)
        #expect(PermissionStatusMapping.accessibility(isTrusted: false) == .notDetermined)
    }

    @Test func automationCodes() {
        #expect(PermissionStatusMapping.automation(0) == .granted)
        #expect(PermissionStatusMapping.automation(-1744) == .notDetermined)
        #expect(PermissionStatusMapping.automation(-1743) == .denied)
        #expect(PermissionStatusMapping.automation(-600) == nil)
    }

    static let automationCases: [([PermissionStatus?], PermissionStatus)] = [
        ([.denied, .granted], .granted),
        ([.denied, nil], .denied),
        ([.notDetermined, nil], .notDetermined),
        ([nil, nil], .notDetermined),
        ([], .notDetermined),
    ]

    @Test(arguments: automationCases)
    func combinedAutomation(statuses: [PermissionStatus?], expected: PermissionStatus) {
        #expect(PermissionStatusMapping.combinedAutomation(statuses) == expected)
    }

    @Test func accessibilityRefusalAfterRequestIsShownAsDenied() {
        #expect(PermissionStatusMapping.displayed(.notDetermined, for: .accessibility, wasRequested: true) == .denied)
        #expect(PermissionStatusMapping.displayed(.notDetermined, for: .accessibility, wasRequested: false) == .notDetermined)
        #expect(PermissionStatusMapping.displayed(.notDetermined, for: .calendar, wasRequested: true) == .notDetermined)
        #expect(PermissionStatusMapping.displayed(.granted, for: .accessibility, wasRequested: true) == .granted)
    }

    @Test func everyPermissionHasASettingsPane() {
        for permission in AppPermission.allCases {
            let url = permission.settingsURL(bundleID: "example.app")
            #expect(url?.scheme == "x-apple.systempreferences")
        }
        #expect(AppPermission.notifications.settingsURL(bundleID: "example.app")?.absoluteString.hasSuffix("id=example.app") == true)
    }

    @Test func optionalFlags() {
        #expect(!AppPermission.calendar.isOptional)
        #expect(AppPermission.camera.isOptional)
        #expect(AppPermission.accessibility.isOptional)
    }
}

@MainActor
final class FakePermissionChecker: PermissionChecking {
    var statuses: [AppPermission: PermissionStatus] = [:]
    var grantOnRequest: Set<AppPermission> = []
    private(set) var requests: [AppPermission] = []
    private(set) var openedSettings: [AppPermission] = []
    private(set) var statusReads = 0

    func status(of permission: AppPermission) async -> PermissionStatus {
        statusReads += 1
        return statuses[permission] ?? .notDetermined
    }

    func request(_ permission: AppPermission) async {
        requests.append(permission)
        if grantOnRequest.contains(permission) {
            statuses[permission] = .granted
        }
    }

    func openSettings(for permission: AppPermission) {
        openedSettings.append(permission)
    }
}

/// Lets a fixed number of poll ticks through, then fails like a cancelled sleep.
final class CountingPollingClock: PermissionPollingClock, @unchecked Sendable {
    private let lock = NSLock()
    private let allowedSleeps: Int
    private var sleeps = 0

    init(allowedSleeps: Int) {
        self.allowedSleeps = allowedSleeps
    }

    var sleepCount: Int { lock.withLock { sleeps } }

    func sleep(for duration: Duration) async throws {
        let count = lock.withLock { () -> Int in
            sleeps += 1
            return sleeps
        }
        if count > allowedSleeps { throw CancellationError() }
        await Task.yield()
    }
}

@MainActor
struct PermissionsModelTests {
    @Test func refreshReadsEveryPermission() async {
        let checker = FakePermissionChecker()
        checker.statuses = [.calendar: .granted, .camera: .denied]
        let model = PermissionsModel(checker: checker, clock: CountingPollingClock(allowedSleeps: 0))

        await model.refresh()

        #expect(model.status(of: .calendar) == .granted)
        #expect(model.status(of: .camera) == .denied)
        #expect(model.status(of: .notifications) == .notDetermined)
        #expect(model.allStatuses.count == AppPermission.allCases.count)
    }

    @Test func requestUpdatesStatusAndFiresGrantedHook() async {
        let checker = FakePermissionChecker()
        checker.grantOnRequest = [.calendar]
        let model = PermissionsModel(checker: checker, clock: CountingPollingClock(allowedSleeps: 0))
        var granted: [AppPermission] = []
        model.onGranted = { granted.append($0) }
        await model.refresh()

        await model.request(.calendar)

        #expect(checker.requests == [.calendar])
        #expect(model.status(of: .calendar) == .granted)
        #expect(granted == [.calendar])
        #expect(model.inFlight.isEmpty)
    }

    @Test func refusedAccessibilityRequestOffersSettings() async {
        let checker = FakePermissionChecker()
        let model = PermissionsModel(checker: checker, clock: CountingPollingClock(allowedSleeps: 0))

        await model.request(.accessibility)
        model.openSettings(for: .accessibility)

        #expect(model.status(of: .accessibility) == .denied)
        #expect(checker.openedSettings == [.accessibility])
    }

    @Test func pollingRefreshesUntilTheClockStops() async {
        let checker = FakePermissionChecker()
        let clock = CountingPollingClock(allowedSleeps: 2)
        let model = PermissionsModel(checker: checker, clock: clock)

        model.startPolling()
        model.startPolling()
        #expect(model.isPolling)
        while clock.sleepCount < 3 {
            await Task.yield()
        }
        model.stopPolling()

        #expect(!model.isPolling)
        #expect(checker.statusReads == 3 * AppPermission.allCases.count)
    }
}
