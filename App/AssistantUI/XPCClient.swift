import Foundation
import AssistantShared
import AssistantStore
import AssistantGrades

extension Notification.Name {
    /// Posted in-process after any successful task write. Every task-displaying
    /// store observes it and re-pulls from the daemon (the single source of
    /// truth), so the dashboard, Tasks window, and class panels stay in sync
    /// regardless of which one made the change.
    static let assistantTasksDidChange = Notification.Name("assistantTasksDidChange")

    /// Posted in-process after a successful class-pin write. The originating
    /// `ClassStore` is the `object` and the changed class's id rides in
    /// `userInfo["courseId"]`. Other stores viewing the same class re-pull pins;
    /// the originator skips itself (its local pins are already updated), so a
    /// window never reloads — and risks a mid-drag flicker — from its own edits.
    static let assistantPinsDidChange = Notification.Name("assistantPinsDidChange")

    /// Posted in-process after a successful class file/folder write (create,
    /// rename, move, delete, import). Same shape as `.assistantPinsDidChange`:
    /// the originating `ClassStore` is the `object` and the class id rides in
    /// `userInfo["courseId"]`. Other stores viewing that class re-pull their
    /// file tree (and pins, since deleting a file cascades its pins); the
    /// originator skips its own echo (it already reloaded locally).
    static let assistantFilesDidChange = Notification.Name("assistantFilesDidChange")
}

/// Wraps NSXPCConnection to the daemon. All future XPC calls go through here.
///
/// Connection lifecycle: lazily created on first use, kept alive for the
/// process lifetime, recreated automatically if it invalidates.
final class XPCClient {

    static let shared = XPCClient()

    private let queue = DispatchQueue(label: "com.vishruth.assistant.xpcclient")
    private var connection: NSXPCConnection?
    /// Generation of `connection` in `gate`; nil whenever `connection` is nil.
    private var connectionGeneration: UInt64?
    /// Exactly-once reply registry, connection identity, re-register state.
    private let gate = XPCCallGate()
    /// Briefing endpoint to (re)register on each new connection.
    private var eventEndpoint: NSXPCListenerEndpoint?

    private init() {}

    /// Calls `ping` on the daemon. `reply` is called on `DispatchQueue.main`.
    func ping(reply: @escaping (Result<String, Error>) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: .failure(XPCClientError.connectionLost))
            proxy.ping { response in
                DispatchQueue.main.async { reply(.success(response)) }
            }
        } catch {
            DispatchQueue.main.async { reply(.failure(error)) }
        }
    }

    /// Calls `getTodayPlan` and decodes the JSON response. Reply on main queue.
    func getTodayPlan(reply: @escaping (Result<TodayPlan, Error>) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: .failure(XPCClientError.connectionLost))
            proxy.getTodayPlan { data in
                DispatchQueue.main.async {
                    guard !data.isEmpty else {
                        reply(.failure(XPCClientError.emptyResponse))
                        return
                    }
                    do {
                        let plan = try JSONDecoder().decode(TodayPlan.self, from: data)
                        reply(.success(plan))
                    } catch {
                        reply(.failure(error))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { reply(.failure(error)) }
        }
    }

    func submitPrompt(text: String,
                      imageData: Data? = nil,
                      imageMediaType: String? = nil,
                      sessionId: String? = nil,
                      reply: @escaping (Result<PromptResponse, Error>) -> Void) {
        do {
            let req = PromptRequest(text: text, imageData: imageData,
                                    imageMediaType: imageMediaType, sessionId: sessionId)
            let body = try JSONEncoder().encode(req)
            let (proxy, reply) = try makeProxy(reply, fallback: .failure(XPCClientError.connectionLost))
            proxy.submitPrompt(body) { data in
                DispatchQueue.main.async {
                    do {
                        let resp = try JSONDecoder().decode(PromptResponse.self, from: data)
                        reply(.success(resp))
                    } catch {
                        reply(.failure(error))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { reply(.failure(error)) }
        }
    }

    func setGoogleRefreshToken(_ token: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setGoogleRefreshToken(token) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getMostRecentSessionId(reply: @escaping (String?) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: nil)
            proxy.getMostRecentSessionId { id in
                DispatchQueue.main.async { reply(id) }
            }
        } catch {
            DispatchQueue.main.async { reply(nil) }
        }
    }

    func getMessages(sessionId: String, reply: @escaping ([MessageDTO]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.getMessages(sessionId: sessionId) { data in
                let dtos = (try? JSONDecoder().decode([MessageDTO].self, from: data)) ?? []
                DispatchQueue.main.async { reply(dtos) }
            }
        } catch {
            DispatchQueue.main.async { reply([]) }
        }
    }

    /// Registers the briefing endpoint with the daemon. The endpoint is
    /// remembered and re-sent on every new connection (helper restart,
    /// interruption) and after a failed or refused registration.
    func registerEventClient(_ endpoint: NSXPCListenerEndpoint) {
        queue.sync { eventEndpoint = endpoint }
        gate.markNeedsReregister()
        reregisterEventClientIfNeeded()
    }

    func computeGrade(courseId: String, projection: [String: Double]?,
                      reply: @escaping (GradeBreakdown?) -> Void) {
        do {
            let pjData = projection.flatMap { try? JSONEncoder().encode($0) }
            let (proxy, reply) = try makeProxy(reply, fallback: nil)
            proxy.computeGrade(courseId: courseId, projectionJSON: pjData) { data in
                let bd = try? JSONDecoder().decode(GradeBreakdown.self, from: data)
                DispatchQueue.main.async { reply(bd) }
            }
        } catch {
            DispatchQueue.main.async { reply(nil) }
        }
    }

    func enterGrade(itemId: String, earnedPoints: Double, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.enterGrade(itemId: itemId, earnedPoints: earnedPoints) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func listCourses(reply: @escaping ([Course]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listCourses { data in
                let courses = (try? JSONDecoder().decode([Course].self, from: data)) ?? []
                DispatchQueue.main.async { reply(courses) }
            }
        } catch {
            DispatchQueue.main.async { reply([]) }
        }
    }

    func upsertCourse(_ course: Course, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(course)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.upsertCourse(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func listGradeData(courseId: String,
                       reply: @escaping ([GradeCategory], [GradeItem]) -> Void) {
        do {
            let (proxy, reply2) = try makeProxy({ reply($0.0, $0.1) }, fallback: ([], []))
            proxy.listGradeData(courseId: courseId) { data in
                var cats: [GradeCategory] = []
                var items: [GradeItem] = []
                if let dto = try? JSONDecoder().decode(GradeDataDTO.self, from: data) {
                    cats = (try? JSONDecoder().decode([GradeCategory].self, from: dto.categoriesJSON)) ?? []
                    items = (try? JSONDecoder().decode([GradeItem].self, from: dto.itemsJSON)) ?? []
                }
                DispatchQueue.main.async { reply2((cats, items)) }
            }
        } catch {
            DispatchQueue.main.async { reply([], []) }
        }
    }

    func upsertCategory(_ category: GradeCategory, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(category)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.upsertCategory(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func upsertItem(_ item: GradeItem, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(item)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.upsertItem(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func deleteCategory(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteCategory(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func deleteItem(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteItem(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func deleteCourse(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteCourse(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func setProviderAPIKey(provider: String, key: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setProviderAPIKey(provider: provider, key: key) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getProviderConfigured(provider: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.getProviderConfigured(provider: provider) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getSettings(reply: @escaping (AppSettings) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: .default)
            proxy.getSettings { data in
                let s = (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .default
                DispatchQueue.main.async { reply(s) }
            }
        } catch {
            DispatchQueue.main.async { reply(.default) }
        }
    }

    func setSettings(_ settings: AppSettings, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(settings)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setSettings(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func clearGoogleRefreshToken(reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.clearGoogleRefreshToken { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setGoogleClientSecret(_ secret: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setGoogleClientSecret(secret) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getGoogleClientSecret(reply: @escaping (String?) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: nil)
            proxy.getGoogleClientSecret { secret in
                DispatchQueue.main.async { reply(secret) }
            }
        } catch {
            DispatchQueue.main.async { reply(nil) }
        }
    }

    /// The Google account's display time zone (IANA name), or nil if it can't
    /// be fetched (not connected / offline).
    func googleAccountTimeZone(reply: @escaping (String?) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: nil)
            proxy.googleAccountTimeZone { tz in
                DispatchQueue.main.async { reply(tz) }
            }
        } catch {
            DispatchQueue.main.async { reply(nil) }
        }
    }

    func getDashboardSummary(reply: @escaping (DashboardSummary?) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: nil)
            proxy.getDashboardSummary { data in
                let s = try? JSONDecoder().decode(DashboardSummary.self, from: data)
                DispatchQueue.main.async { reply(s) }
            }
        } catch { DispatchQueue.main.async { reply(nil) } }
    }

    func getWeekEvents(start: Date, end: Date,
                       reply: @escaping ([WeekEvent]) -> Void) {
        let iso = ISO8601DateFormatter()
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.getWeekEvents(startISO: iso.string(from: start),
                                endISO: iso.string(from: end)) { data in
                let events = (try? JSONDecoder().decode(
                    WeekEventsResponse.self, from: data))?.events ?? []
                DispatchQueue.main.async { reply(events) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func createCalendarEvent(_ request: CreateEventRequest,
                             reply: @escaping (CalendarWriteResult) -> Void) {
        do {
            let data = try JSONEncoder().encode(request)
            let (proxy, reply) = try makeProxy(reply, fallback: CalendarWriteResult(event: nil, errorMessage: XPCClientError.connectionLost.message))
            proxy.createCalendarEvent(data) { resultData in
                let result = (try? JSONDecoder().decode(
                    CalendarWriteResult.self, from: resultData))
                    ?? CalendarWriteResult(event: nil, errorMessage: "no response")
                DispatchQueue.main.async { reply(result) }
            }
        } catch {
            DispatchQueue.main.async {
                reply(CalendarWriteResult(event: nil, errorMessage: "\(error)"))
            }
        }
    }

    func updateCalendarEvent(_ request: UpdateEventRequest,
                             reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(request)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.updateCalendarEvent(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteCalendarEvent(eventId: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteCalendarEvent(eventId: eventId) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func listCategories(reply: @escaping ([AssistantStore.Category]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listCategories { data in
                let cats = (try? JSONDecoder().decode([AssistantStore.Category].self, from: data)) ?? []
                DispatchQueue.main.async { reply(cats) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func listEventTypes(reply: @escaping ([EventTypeDTO]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listEventTypes { data in
                let types = (try? JSONDecoder().decode([EventTypeDTO].self, from: data)) ?? []
                DispatchQueue.main.async { reply(types) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func upsertEventType(_ type: EventTypeDTO, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(type)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.upsertEventType(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteEventType(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteEventType(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func listClasses(reply: @escaping ([ClassSummary]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listClasses { data in
                let classes = (try? JSONDecoder().decode([ClassSummary].self, from: data)) ?? []
                DispatchQueue.main.async { reply(classes) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func getClassDetail(courseId: String, reply: @escaping (ClassDetail?) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: nil)
            proxy.getClassDetail(courseId: courseId) { data in
                let detail = try? JSONDecoder().decode(ClassDetail.self, from: data)
                DispatchQueue.main.async { reply(detail) }
            }
        } catch { DispatchQueue.main.async { reply(nil) } }
    }

    func listClassFolders(courseId: String, reply: @escaping ([ClassFolderDTO]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listClassFolders(courseId: courseId) { data in
                let v = (try? JSONDecoder().decode([ClassFolderDTO].self, from: data)) ?? []
                DispatchQueue.main.async { reply(v) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func listClassFiles(courseId: String, reply: @escaping ([ClassFileDTO]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listClassFiles(courseId: courseId) { data in
                let v = (try? JSONDecoder().decode([ClassFileDTO].self, from: data)) ?? []
                DispatchQueue.main.async { reply(v) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func createClassFolder(_ folder: ClassFolderDTO, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(folder)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.createClassFolder(data) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func renameClassFolder(id: String, name: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.renameClassFolder(id: id, name: name) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func moveClassFolder(id: String, parentId: String?, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.moveClassFolder(id: id, parentId: parentId) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteClassFolder(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteClassFolder(id: id) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func addClassFile(_ file: ClassFileDTO, bytes: Data, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(file)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.addClassFile(data, bytes: bytes) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func renameClassFile(id: String, name: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.renameClassFile(id: id, name: name) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func moveClassFile(id: String, folderId: String?, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.moveClassFile(id: id, folderId: folderId) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteClassFile(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteClassFile(id: id) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func listClassPins(courseId: String, reply: @escaping ([ClassPinDTO]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listClassPins(courseId: courseId) { data in
                let v = (try? JSONDecoder().decode([ClassPinDTO].self, from: data)) ?? []
                DispatchQueue.main.async { reply(v) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func upsertClassPin(_ pin: ClassPinDTO, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(pin)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.upsertClassPin(data) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteClassPin(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteClassPin(id: id) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func saveCategory(originalName: String?, name: String, colorHex: String,
                      reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.saveCategory(originalName: originalName, name: name,
                               colorHex: colorHex) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func removeCategory(name: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.removeCategory(name: name) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setEventCategory(eventId: String, category: String,
                          reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setEventCategory(eventId: eventId, category: category) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setEventClassification(eventId: String, courseId: String?, eventType: String?,
                                reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setEventClassification(eventId: eventId, courseId: courseId,
                                         eventType: eventType) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func getWeekTasks(start: Date, end: Date,
                      reply: @escaping ([WeekTask]) -> Void) {
        let iso = ISO8601DateFormatter()
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.getWeekTasks(startISO: iso.string(from: start),
                               endISO: iso.string(from: end)) { data in
                let tasks = (try? JSONDecoder().decode(
                    WeekTasksResponse.self, from: data))?.tasks ?? []
                DispatchQueue.main.async { reply(tasks) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    /// Wraps a Bool task-write reply so a successful write broadcasts an
    /// in-process change notification — every task view then re-pulls from the
    /// shared daemon DB. Always delivers `reply` on the main queue.
    private func taskWriteReply(_ reply: @escaping (Bool) -> Void) -> (Bool) -> Void {
        { ok in
            DispatchQueue.main.async {
                reply(ok)
                if ok {
                    NotificationCenter.default.post(name: .assistantTasksDidChange, object: nil)
                }
            }
        }
    }

    func rescheduleTask(taskId: String, dueAt: Date,
                        reply: @escaping (Bool) -> Void) {
        let iso = ISO8601DateFormatter()
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.rescheduleTask(taskId: taskId, dueISO: iso.string(from: dueAt),
                                 reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func completeTask(taskId: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.completeTask(taskId: taskId, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func listTasks(reply: @escaping ([AssistantStore.Task]) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: [])
            proxy.listTasks { data in
                let tasks = (try? JSONDecoder().decode(
                    [AssistantStore.Task].self, from: data)) ?? []
                DispatchQueue.main.async { reply(tasks) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func createTask(_ task: AssistantStore.Task, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(task)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.createTask(data, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func updateTask(_ task: AssistantStore.Task, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(task)
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.updateTask(data, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteTask(taskId: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.deleteTask(taskId: taskId, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setTaskCompleted(taskId: String, completed: Bool,
                          reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setTaskCompleted(taskId: taskId, completed: completed,
                                   reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func clearCompletedTasks(reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.clearCompletedTasks(reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func getTasksNote(reply: @escaping (String) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: "")
            proxy.getTasksNote { note in DispatchQueue.main.async { reply(note) } }
        } catch { DispatchQueue.main.async { reply("") } }
    }

    func setTasksNote(_ note: String, reply: @escaping (Bool) -> Void) {
        do {
            let (proxy, reply) = try makeProxy(reply, fallback: false)
            proxy.setTasksNote(note) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    // MARK: - Connection management

    /// Returns a proxy on the current connection plus a guarded `reply`.
    /// The guarded reply is registered with `gate` before the message is sent,
    /// so exactly one of these delivers to the caller: the daemon's reply, the
    /// proxy error handler, or the connection's interruption/invalidation
    /// handler (which deliver `fallback` on the main queue).
    private func makeProxy<T>(_ reply: @escaping (T) -> Void,
                              fallback: @escaping @autoclosure () -> T) throws
        -> (AssistantServiceProtocol, (T) -> Void) {
        reregisterEventClientIfNeeded()
        let (conn, generation) = currentConnection()
        let gate = self.gate
        let call = gate.register(generation: generation) {
            DispatchQueue.main.async { reply(fallback()) }
        }
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] err in
            NSLog("[XPCClient] remote proxy error: \(err)")
            self?.connectionFailed(conn, generation: generation)
        }) as? AssistantServiceProtocol else {
            gate.complete(call)   // the caller's catch replies synchronously
            throw XPCClientError.proxyCastFailed
        }
        let guarded: (T) -> Void = { value in
            if gate.complete(call) { reply(value) }
        }
        return (proxy, guarded)
    }

    private func currentConnection() -> (NSXPCConnection, UInt64) {
        let (conn, generation, created) = queue.sync { () -> (NSXPCConnection, UInt64, Bool) in
            if let existing = connection, let generation = connectionGeneration {
                return (existing, generation, false)
            }

            // .privileged is NOT used: this is a user-level LaunchAgent, not a daemon.
            let conn = NSXPCConnection(machServiceName: XPCConstants.machServiceName,
                                       options: [])
            conn.remoteObjectInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
            let generation = gate.beginConnection()
            // Handlers carry their connection's identity so a dead
            // connection's late callback cannot tear down its replacement.
            conn.invalidationHandler = { [weak self, weak conn] in
                NSLog("[XPCClient] connection invalidated")
                guard let conn else { return }
                self?.connectionFailed(conn, generation: generation)
            }
            conn.interruptionHandler = { [weak self, weak conn] in
                NSLog("[XPCClient] connection interrupted (daemon crashed?)")
                guard let conn else { return }
                self?.connectionFailed(conn, generation: generation)
            }
            conn.resume()
            self.connection = conn
            self.connectionGeneration = generation
            return (conn, generation, true)
        }
        if created { reregisterEventClientIfNeeded(on: conn, generation: generation) }
        return (conn, generation)
    }

    /// Tears down `conn` if it is still the current connection, then fails
    /// every outstanding call made on it. Safe to call repeatedly and from
    /// any of the connection's handlers.
    private func connectionFailed(_ conn: NSXPCConnection, generation: UInt64) {
        let wasCurrent = queue.sync { () -> Bool in
            guard connection === conn, gate.endConnection(generation: generation) else {
                return false
            }
            connection = nil
            connectionGeneration = nil
            if eventEndpoint != nil { gate.markNeedsReregister() }
            return true
        }
        if wasCurrent {
            conn.invalidationHandler = nil
            conn.interruptionHandler = nil
            conn.invalidate()
        }
        gate.failAll(generation: generation)
    }

    /// Re-sends the remembered briefing endpoint when the daemon may have
    /// lost it. Never builds a connection itself unless `conn` is nil.
    private func reregisterEventClientIfNeeded(on existing: NSXPCConnection? = nil,
                                               generation existingGeneration: UInt64? = nil) {
        guard let endpoint = queue.sync(execute: { eventEndpoint }),
              gate.needsReregister, gate.beginReregister() else { return }
        let conn: NSXPCConnection
        let generation: UInt64
        if let existing, let existingGeneration {
            conn = existing; generation = existingGeneration
        } else {
            (conn, generation) = currentConnection()
        }
        let gate = self.gate
        let call = gate.register(generation: generation) {
            gate.recordReregister(success: false)
        }
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] err in
            NSLog("[XPCClient] register event client failed: \(err)")
            self?.connectionFailed(conn, generation: generation)
        }) as? AssistantServiceProtocol else {
            gate.complete(call)
            gate.recordReregister(success: false)
            return
        }
        proxy.registerEventClient(endpoint) { ok in
            guard gate.complete(call) else { return }
            if !ok { NSLog("[XPCClient] daemon refused event client registration") }
            gate.recordReregister(success: ok)
        }
    }
}

enum XPCClientError: Error {
    case proxyCastFailed
    case emptyResponse
    /// The connection was interrupted or invalidated before the daemon replied.
    case connectionLost

    var message: String {
        switch self {
        case .proxyCastFailed: return "Could not reach the assistant helper."
        case .emptyResponse: return "The assistant helper returned no data."
        case .connectionLost: return "Lost connection to the assistant helper."
        }
    }
}
