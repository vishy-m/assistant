import SwiftUI
import AppKit
import AssistantShared
import AssistantStore

struct ClassDetailView: View {
    let courseId: String
    @ObservedObject var store: ClassStore
    @State private var showEditor = false
    @State private var showAddEvent = false
    @State private var showAddTask = false
    @State private var showEditTask = false
    @State private var taskToEdit: AssistantStore.Task?

    // Panel sizes/collapse persist per course in UserDefaults.
    @State private var filesWidth: CGFloat = 200
    @State private var tasksWidth: CGFloat = 200
    @State private var calHeight: CGFloat = 110
    @State private var filesCollapsed = false
    @State private var tasksCollapsed = false
    @State private var calCollapsed = false

    private func loadPanelPrefs() {
        let d = UserDefaults.standard
        filesWidth = CGFloat(d.double(forKey: "cf.\(courseId).filesW").nonzero ?? 200)
        tasksWidth = CGFloat(d.double(forKey: "cf.\(courseId).tasksW").nonzero ?? 200)
        calHeight = CGFloat(d.double(forKey: "cf.\(courseId).calH").nonzero ?? 110)
        filesCollapsed = d.bool(forKey: "cf.\(courseId).filesC")
        tasksCollapsed = d.bool(forKey: "cf.\(courseId).tasksC")
        calCollapsed = d.bool(forKey: "cf.\(courseId).calC")
    }
    private func savePanelPrefs() {
        let d = UserDefaults.standard
        d.set(Double(filesWidth), forKey: "cf.\(courseId).filesW")
        d.set(Double(tasksWidth), forKey: "cf.\(courseId).tasksW")
        d.set(Double(calHeight), forKey: "cf.\(courseId).calH")
        d.set(filesCollapsed, forKey: "cf.\(courseId).filesC")
        d.set(tasksCollapsed, forKey: "cf.\(courseId).tasksC")
        d.set(calCollapsed, forKey: "cf.\(courseId).calC")
    }

    var body: some View {
        Group {
            if let detail = store.detail, detail.id == courseId {
                content(detail)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(GradeTheme.windowBg)
        .onAppear { store.loadDetail(courseId: courseId); loadPanelPrefs() }
        .sheet(isPresented: $showEditor) {
            if let detail = store.detail {
                ClassInfoEditorSheet(detail: detail) { store.loadDetail(courseId: courseId) }
            }
        }
        .sheet(isPresented: $showAddEvent) {
            ClassEventCreatorSheet(courseId: courseId, store: store) {
                store.loadDetail(courseId: courseId)
            }
        }
        .sheet(isPresented: $showAddTask) {
            TaskEditorSheet(mode: .add, defaultCourseId: courseId,
                            onSave: { store.addTask($0) })
        }
        .sheet(isPresented: $showEditTask) {
            if let task = taskToEdit {
                TaskEditorSheet(mode: .edit(task),
                                onSave: { store.updateTask($0) },
                                onDelete: { store.deleteTask($0) })
            }
        }
    }

    private func content(_ detail: ClassDetail) -> some View {
        VStack(spacing: 0) {
            header(detail).padding(16)
            Divider()
            ResizableSplit(edge: .bottom, size: $calHeight, collapsed: $calCollapsed,
                           range: 70...260) {
                ResizableSplit(edge: .leading, size: $filesWidth, collapsed: $filesCollapsed,
                               range: 150...360) {
                    ResizableSplit(edge: .trailing, size: $tasksWidth, collapsed: $tasksCollapsed,
                                   range: 150...360) {
                        ClassCanvasPlaceholder()
                    } panel: {
                        tasksPanel()
                    }
                } panel: {
                    ClassFilesPanel(store: store)
                }
            } panel: {
                ClassMiniCalendar(store: store, events: detail.events)
            }
        }
        .navigationTitle(detail.name)
        .onDisappear { savePanelPrefs() }
        .toolbar {
            ToolbarItemGroup {
                Button("Add Event") { showAddEvent = true }
                Button("Grades") { GradeDashboardWindow.shared.show() }
                Button("Edit") { showEditor = true }
            }
        }
    }

    /// Right-hand panel listing this class's tasks — create, edit, complete.
    /// All tasks here belong to this class (created tasks auto-assign to it).
    private func tasksPanel() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    EyebrowLabel("Tasks & Deadlines")
                    Spacer()
                    Button { showAddTask = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add a task to this class")
                }
                if store.classTasks.isEmpty {
                    Text("No tasks for this class")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(store.classTasks, id: \.id) { taskRow($0) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 260)
        .background(Color.primary.opacity(0.035))
    }

    private func header(_ d: ClassDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: d.iconName ?? "book.closed")
                    .foregroundStyle(GradeTheme.color(fromHex: d.colorHex))
                Text(d.name).font(GradeTheme.metric(20))
            }
            if let term = d.term, !term.isEmpty {
                Text(term).font(GradeTheme.mono(11)).foregroundStyle(.secondary)
            }
            if let prof = d.professorName, !prof.isEmpty {
                Text(prof).font(GradeTheme.mono(11))
            }
            if let email = d.professorEmail, !email.isEmpty {
                Button(email) {
                    if let url = URL(string: "mailto:\(email)") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link).font(GradeTheme.mono(11))
            }
            if let room = d.classroom, !room.isEmpty {
                Label(room, systemImage: "mappin.and.ellipse")
                    .font(GradeTheme.mono(11)).foregroundStyle(.secondary)
            }
        }
    }

    private func taskRow(_ t: AssistantStore.Task) -> some View {
        let done = t.completedAt != nil
        return HStack {
            Button { store.toggleTaskCompleted(t) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
            }
            .buttonStyle(.plain)
            Text(t.title).font(GradeTheme.mono(11)).strikethrough(done)
            Spacer()
            if let due = t.dueAt {
                Text(Self.dateFormatter.string(from: due))
                    .font(GradeTheme.mono(10)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { taskToEdit = t; showEditTask = true }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d, h:mm a"; return f
    }()
}

private extension Double { var nonzero: Double? { self == 0 ? nil : self } }
