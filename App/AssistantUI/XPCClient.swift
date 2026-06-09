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
}

/// Wraps NSXPCConnection to the daemon. All future XPC calls go through here.
///
/// Connection lifecycle: lazily created on first use, kept alive for the
/// process lifetime, recreated automatically if it invalidates.
final class XPCClient {

    static let shared = XPCClient()

    private let queue = DispatchQueue(label: "com.vishruth.assistant.xpcclient")
    private var connection: NSXPCConnection?

    private init() {}

    /// Calls `ping` on the daemon. `reply` is called on `DispatchQueue.main`.
    func ping(reply: @escaping (Result<String, Error>) -> Void) {
        do {
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.setGoogleRefreshToken(token) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getMostRecentSessionId(reply: @escaping (String?) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.getMostRecentSessionId { id in
                DispatchQueue.main.async { reply(id) }
            }
        } catch {
            DispatchQueue.main.async { reply(nil) }
        }
    }

    func getMessages(sessionId: String, reply: @escaping ([MessageDTO]) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.getMessages(sessionId: sessionId) { data in
                let dtos = (try? JSONDecoder().decode([MessageDTO].self, from: data)) ?? []
                DispatchQueue.main.async { reply(dtos) }
            }
        } catch {
            DispatchQueue.main.async { reply([]) }
        }
    }

    func registerEventClient(_ endpoint: NSXPCListenerEndpoint) {
        do {
            let proxy = try makeProxy()
            proxy.registerEventClient(endpoint) { _ in }
        } catch {
            NSLog("[XPCClient] register event client failed: \(error)")
        }
    }

    func computeGrade(courseId: String, projection: [String: Double]?,
                      reply: @escaping (GradeBreakdown?) -> Void) {
        do {
            let pjData = projection.flatMap { try? JSONEncoder().encode($0) }
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.enterGrade(itemId: itemId, earnedPoints: earnedPoints) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func listCourses(reply: @escaping ([Course]) -> Void) {
        do {
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.listGradeData(courseId: courseId) { data in
                var cats: [GradeCategory] = []
                var items: [GradeItem] = []
                if let dto = try? JSONDecoder().decode(GradeDataDTO.self, from: data) {
                    cats = (try? JSONDecoder().decode([GradeCategory].self, from: dto.categoriesJSON)) ?? []
                    items = (try? JSONDecoder().decode([GradeItem].self, from: dto.itemsJSON)) ?? []
                }
                DispatchQueue.main.async { reply(cats, items) }
            }
        } catch {
            DispatchQueue.main.async { reply([], []) }
        }
    }

    func upsertCategory(_ category: GradeCategory, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(category)
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.upsertItem(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func deleteCategory(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.deleteCategory(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func deleteItem(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.deleteItem(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func deleteCourse(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.deleteCourse(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func setProviderAPIKey(provider: String, key: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.setProviderAPIKey(provider: provider, key: key) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getProviderConfigured(provider: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.getProviderConfigured(provider: provider) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getSettings(reply: @escaping (AppSettings) -> Void) {
        do {
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.setSettings(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func clearGoogleRefreshToken(reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.clearGoogleRefreshToken { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setGoogleClientSecret(_ secret: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.setGoogleClientSecret(secret) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch {
            DispatchQueue.main.async { reply(false) }
        }
    }

    func getGoogleClientSecret(reply: @escaping (String?) -> Void) {
        do {
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.googleAccountTimeZone { tz in
                DispatchQueue.main.async { reply(tz) }
            }
        } catch {
            DispatchQueue.main.async { reply(nil) }
        }
    }

    func getDashboardSummary(reply: @escaping (DashboardSummary?) -> Void) {
        do {
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.updateCalendarEvent(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteCalendarEvent(eventId: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.deleteCalendarEvent(eventId: eventId) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func listCategories(reply: @escaping ([AssistantStore.Category]) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.listCategories { data in
                let cats = (try? JSONDecoder().decode([AssistantStore.Category].self, from: data)) ?? []
                DispatchQueue.main.async { reply(cats) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func listEventTypes(reply: @escaping ([EventTypeDTO]) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.listEventTypes { data in
                let types = (try? JSONDecoder().decode([EventTypeDTO].self, from: data)) ?? []
                DispatchQueue.main.async { reply(types) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func upsertEventType(_ type: EventTypeDTO, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(type)
            let proxy = try makeProxy()
            proxy.upsertEventType(data) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteEventType(id: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.deleteEventType(id: id) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func listClasses(reply: @escaping ([ClassSummary]) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.listClasses { data in
                let classes = (try? JSONDecoder().decode([ClassSummary].self, from: data)) ?? []
                DispatchQueue.main.async { reply(classes) }
            }
        } catch { DispatchQueue.main.async { reply([]) } }
    }

    func getClassDetail(courseId: String, reply: @escaping (ClassDetail?) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.getClassDetail(courseId: courseId) { data in
                let detail = try? JSONDecoder().decode(ClassDetail.self, from: data)
                DispatchQueue.main.async { reply(detail) }
            }
        } catch { DispatchQueue.main.async { reply(nil) } }
    }

    func saveCategory(originalName: String?, name: String, colorHex: String,
                      reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.saveCategory(originalName: originalName, name: name,
                               colorHex: colorHex) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func removeCategory(name: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.removeCategory(name: name) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setEventCategory(eventId: String, category: String,
                          reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.setEventCategory(eventId: eventId, category: category) { ok in
                DispatchQueue.main.async { reply(ok) }
            }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setEventClassification(eventId: String, courseId: String?, eventType: String?,
                                reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.rescheduleTask(taskId: taskId, dueISO: iso.string(from: dueAt),
                                 reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func completeTask(taskId: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.completeTask(taskId: taskId, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func listTasks(reply: @escaping ([AssistantStore.Task]) -> Void) {
        do {
            let proxy = try makeProxy()
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
            let proxy = try makeProxy()
            proxy.createTask(data, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func updateTask(_ task: AssistantStore.Task, reply: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(task)
            let proxy = try makeProxy()
            proxy.updateTask(data, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func deleteTask(taskId: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.deleteTask(taskId: taskId, reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func setTaskCompleted(taskId: String, completed: Bool,
                          reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.setTaskCompleted(taskId: taskId, completed: completed,
                                   reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func clearCompletedTasks(reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.clearCompletedTasks(reply: taskWriteReply(reply))
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    func getTasksNote(reply: @escaping (String) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.getTasksNote { note in DispatchQueue.main.async { reply(note) } }
        } catch { DispatchQueue.main.async { reply("") } }
    }

    func setTasksNote(_ note: String, reply: @escaping (Bool) -> Void) {
        do {
            let proxy = try makeProxy()
            proxy.setTasksNote(note) { ok in DispatchQueue.main.async { reply(ok) } }
        } catch { DispatchQueue.main.async { reply(false) } }
    }

    // MARK: - Connection management

    private func makeProxy() throws -> AssistantServiceProtocol {
        let conn = currentConnection()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] err in
            NSLog("[XPCClient] remote proxy error: \(err)")
            self?.invalidate()
        }) as? AssistantServiceProtocol else {
            throw XPCClientError.proxyCastFailed
        }
        return proxy
    }

    private func currentConnection() -> NSXPCConnection {
        queue.sync {
            if let existing = connection { return existing }

            // .privileged is NOT used: this is a user-level LaunchAgent, not a daemon.
            let conn = NSXPCConnection(machServiceName: XPCConstants.machServiceName,
                                       options: [])
            conn.remoteObjectInterface = NSXPCInterface(with: AssistantServiceProtocol.self)
            conn.invalidationHandler = { [weak self] in
                NSLog("[XPCClient] connection invalidated")
                self?.invalidate()
            }
            conn.interruptionHandler = {
                NSLog("[XPCClient] connection interrupted (daemon crashed?)")
            }
            conn.resume()
            self.connection = conn
            return conn
        }
    }

    private func invalidate() {
        queue.sync {
            connection?.invalidate()
            connection = nil
        }
    }
}

enum XPCClientError: Error {
    case proxyCastFailed
    case emptyResponse
}
