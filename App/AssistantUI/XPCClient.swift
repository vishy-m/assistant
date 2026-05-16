import Foundation
import AssistantShared
import AssistantStore
import AssistantGrades

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
