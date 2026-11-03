import Testing
@testable import SonaryCore

struct PermissionBrokerTests {
    @Test func ensureReturnsTrueWhenAllGranted() async {
        let checker = FakeChecker(statuses: [.accessibility: .granted, .calendars: .granted])
        let broker = PermissionBroker(checker: checker)
        #expect(await broker.ensure([.accessibility, .calendars]))
        #expect(checker.requested.isEmpty)
    }

    @Test func ensureRequestsOnlyMissingPermissions() async {
        let checker = FakeChecker(statuses: [.accessibility: .granted], requestResult: .granted)
        let broker = PermissionBroker(checker: checker)
        #expect(await broker.ensure([.accessibility, .notifications]))
        #expect(checker.requested == [.notifications])
    }

    @Test func ensureReturnsFalseWhenAnyDenied() async {
        let checker = FakeChecker(statuses: [.accessibility: .granted], requestResult: .denied)
        let broker = PermissionBroker(checker: checker)
        #expect(await broker.ensure([.accessibility, .screenRecording]) == false)
    }

    @Test func ensureWithEmptyListNeverTouchesChecker() async {
        let checker = FakeChecker()
        let broker = PermissionBroker(checker: checker)
        #expect(await broker.ensure([]))
        #expect(checker.statusCalls == 0)
        #expect(checker.requested.isEmpty)
    }
}
