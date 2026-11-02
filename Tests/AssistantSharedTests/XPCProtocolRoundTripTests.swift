import XCTest
@testable import AssistantShared

final class XPCProtocolRoundTripTests: XCTestCase {

    func testPingRoundTripReturnsPong() throws {
        let harness = try InProcessXPCHarness(service: StubService())
        defer { harness.invalidate() }

        let exp = expectation(description: "ping reply")
        var captured: String?
        harness.proxy.ping { reply in
            captured = reply
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(captured, "pong")
    }

    // Local stub — production implementation lives in the daemon binary.
    private final class StubService: NSObject, AssistantServiceProtocol {
        func ping(reply: @escaping (String) -> Void) {
            reply("pong")
        }
        func getTodayPlan(reply: @escaping (Data) -> Void) {
            reply(Data())
        }
        func submitPrompt(_ requestData: Data, reply: @escaping (Data) -> Void) {
            reply(Data())
        }
        func setGoogleRefreshToken(_ token: String, reply: @escaping (Bool) -> Void) {
            reply(false)
        }
        func getMostRecentSessionId(reply: @escaping (String?) -> Void) {
            reply(nil)
        }
        func getMessages(sessionId: String, reply: @escaping (Data) -> Void) {
            reply(Data())
        }
        func registerEventClient(_ endpoint: NSXPCListenerEndpoint, reply: @escaping (Bool) -> Void) {
            reply(false)
        }
        func computeGrade(courseId: String, projectionJSON: Data?, reply: @escaping (Data) -> Void) {
            reply(Data())
        }
        func enterGrade(itemId: String, earnedPoints: Double, reply: @escaping (Bool) -> Void) {
            reply(false)
        }
        func listCourses(reply: @escaping (Data) -> Void) { reply(Data()) }
        func upsertCourse(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func listGradeData(courseId: String, reply: @escaping (Data) -> Void) { reply(Data()) }
        func upsertCategory(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func upsertItem(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteCategory(id: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteItem(id: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteCourse(id: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func setProviderAPIKey(provider: String, key: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func getProviderConfigured(provider: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func getSettings(reply: @escaping (Data) -> Void) { reply(Data()) }
        func setSettings(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func clearGoogleRefreshToken(reply: @escaping (Bool) -> Void) { reply(false) }
        func setGoogleClientSecret(_ secret: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func getGoogleClientSecret(reply: @escaping (String?) -> Void) { reply(nil) }
        func googleAccountTimeZone(reply: @escaping (String?) -> Void) { reply(nil) }
        func getDashboardSummary(reply: @escaping (Data) -> Void) { reply(Data()) }
        func getWeekEvents(startISO: String, endISO: String, reply: @escaping (Data) -> Void) { reply(Data()) }
        func createCalendarEvent(_ data: Data, reply: @escaping (Data) -> Void) { reply(Data()) }
        func updateCalendarEvent(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteCalendarEvent(eventId: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func listCategories(reply: @escaping (Data) -> Void) { reply(Data()) }
        func listEventTypes(reply: @escaping (Data) -> Void) { reply(Data()) }
        func upsertEventType(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteEventType(id: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func listClasses(reply: @escaping (Data) -> Void) { reply(Data()) }
        func getClassDetail(courseId: String, reply: @escaping (Data) -> Void) { reply(Data()) }
        func listClassFolders(courseId: String, reply: @escaping (Data) -> Void) { reply(Data()) }
        func listClassFiles(courseId: String, reply: @escaping (Data) -> Void) { reply(Data()) }
        func createClassFolder(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func renameClassFolder(id: String, name: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func moveClassFolder(id: String, parentId: String?, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteClassFolder(id: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func addClassFile(_ data: Data, bytes: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func renameClassFile(id: String, name: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func moveClassFile(id: String, folderId: String?, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteClassFile(id: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func listClassPins(courseId: String, reply: @escaping (Data) -> Void) { reply(Data()) }
        func upsertClassPin(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteClassPin(id: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func saveCategory(originalName: String?, name: String, colorHex: String,
                          reply: @escaping (Bool) -> Void) { reply(false) }
        func removeCategory(name: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func setEventCategory(eventId: String, category: String,
                              reply: @escaping (Bool) -> Void) { reply(false) }
        func setEventClassification(eventId: String, courseId: String?,
                                    eventType: String?,
                                    reply: @escaping (Bool) -> Void) { reply(false) }
        func getWeekTasks(startISO: String, endISO: String, reply: @escaping (Data) -> Void) { reply(Data()) }
        func rescheduleTask(taskId: String, dueISO: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func completeTask(taskId: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func listTasks(reply: @escaping (Data) -> Void) { reply(Data()) }
        func createTask(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func updateTask(_ data: Data, reply: @escaping (Bool) -> Void) { reply(false) }
        func deleteTask(taskId: String, reply: @escaping (Bool) -> Void) { reply(false) }
        func setTaskCompleted(taskId: String, completed: Bool, reply: @escaping (Bool) -> Void) { reply(false) }
        func clearCompletedTasks(reply: @escaping (Bool) -> Void) { reply(false) }
        func getTasksNote(reply: @escaping (String) -> Void) { reply("") }
        func setTasksNote(_ note: String, reply: @escaping (Bool) -> Void) { reply(false) }
    }
}

// MARK: - XPCCallGate (exactly-once completion, connection identity, re-register)

final class XPCCallGateTests: XCTestCase {

    func testSuccessThenFailureCompletesOnce() {
        let gate = XPCCallGate()
        let gen = gate.beginConnection()
        var failures = 0
        let call = gate.register(generation: gen) { failures += 1 }
        XCTAssertTrue(gate.complete(call))
        XCTAssertEqual(gate.failAll(generation: gen), 0)
        XCTAssertEqual(failures, 0)
    }

    func testFailureThenLateReplyCompletesOnce() {
        let gate = XPCCallGate()
        let gen = gate.beginConnection()
        var failures = 0
        let a = gate.register(generation: gen) { failures += 1 }
        let b = gate.register(generation: gen) { failures += 1 }
        XCTAssertEqual(gate.failAll(generation: gen), 2)
        XCTAssertEqual(failures, 2)
        XCTAssertFalse(gate.complete(a))
        XCTAssertFalse(gate.complete(b))
        XCTAssertEqual(gate.failAll(generation: gen), 0)
        XCTAssertEqual(failures, 2)
    }

    func testDoubleCompleteIsNoOp() {
        let gate = XPCCallGate()
        let gen = gate.beginConnection()
        let call = gate.register(generation: gen) {}
        XCTAssertTrue(gate.complete(call))
        XCTAssertFalse(gate.complete(call))
    }

    func testFailureOfGenerationNDoesNotFinishGenerationNPlus1() {
        let gate = XPCCallGate()
        let g1 = gate.beginConnection()
        var failed1 = 0, failed2 = 0
        _ = gate.register(generation: g1) { failed1 += 1 }
        XCTAssertTrue(gate.endConnection(generation: g1))
        let g2 = gate.beginConnection()
        let c2 = gate.register(generation: g2) { failed2 += 1 }
        XCTAssertEqual(gate.failAll(generation: g1), 1)
        XCTAssertEqual(failed1, 1)
        XCTAssertEqual(failed2, 0)
        XCTAssertTrue(gate.complete(c2))
    }

    func testEndingOldGenerationDoesNotClearCurrentConnection() {
        let gate = XPCCallGate()
        let g1 = gate.beginConnection()
        XCTAssertTrue(gate.endConnection(generation: g1))
        let g2 = gate.beginConnection()
        // A's late invalidation handler must not tear down B.
        XCTAssertFalse(gate.endConnection(generation: g1))
        XCTAssertEqual(gate.currentGeneration, g2)
        XCTAssertTrue(gate.endConnection(generation: g2))
        XCTAssertNil(gate.currentGeneration)
    }

    func testReregisterFlagClearsOnlyOnSuccess() {
        let gate = XPCCallGate()
        XCTAssertFalse(gate.needsReregister)
        gate.markNeedsReregister()
        XCTAssertTrue(gate.needsReregister)
        XCTAssertTrue(gate.beginReregister())
        XCTAssertFalse(gate.beginReregister(), "only one registration in flight")
        gate.recordReregister(success: false)
        XCTAssertTrue(gate.needsReregister)
        XCTAssertTrue(gate.beginReregister())
        gate.recordReregister(success: true)
        XCTAssertFalse(gate.needsReregister)
        XCTAssertFalse(gate.beginReregister())
    }

    func testConnectionLossDuringRegistrationStaysDirty() {
        let gate = XPCCallGate()
        gate.markNeedsReregister()
        XCTAssertTrue(gate.beginReregister())
        gate.markNeedsReregister()            // connection died mid-flight
        gate.recordReregister(success: true)  // stale ack from the dead connection
        XCTAssertTrue(gate.needsReregister)
    }
}
