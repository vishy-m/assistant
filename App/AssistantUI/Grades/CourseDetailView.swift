import SwiftUI
import AssistantStore

// `.sheet(item:)` needs Identifiable; both records already carry a `String` id.
extension GradeCategory: @retroactive Identifiable {}
extension GradeItem: @retroactive Identifiable {}

/// The work surface: a status band of instrument readings on top, the graded
/// items as a spec matrix below, and the breakdown inspector on the right.
struct CourseDetailView: View {
    @ObservedObject var store: GradeStore

    @State private var editingCategory: GradeCategory?
    @State private var editingItem: GradeItem?
    @State private var showingNewCategory = false
    @State private var showingNewItem = false

    private var course: Course? {
        store.courses.first { $0.id == store.selectedCourseId }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBand
            Divider()
            HStack(spacing: 0) {
                matrix
                Divider()
                BreakdownPanel(store: store).frame(width: 264)
            }
        }
        .background(GradeTheme.windowBg)
        .sheet(isPresented: $showingNewCategory) { categorySheet(nil) }
        .sheet(item: $editingCategory) { categorySheet($0) }
        .sheet(isPresented: $showingNewItem) { itemSheet(nil) }
        .sheet(item: $editingItem) { itemSheet($0) }
    }

    // MARK: - Status band

    private var statusBand: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(course?.name ?? "—")
                    .font(.system(size: 19, weight: .semibold))
                if let term = course?.term, !term.isEmpty {
                    Text(term)
                        .font(GradeTheme.mono(11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 24)
            reading(title: "Current",
                    value: store.breakdown.map { GradeTheme.num($0.currentPct) } ?? "—",
                    letter: store.breakdown?.currentLetter,
                    big: true)
            bandDivider
            reading(title: "Projected",
                    value: store.breakdown.map { GradeTheme.num($0.projectedPct) } ?? "—",
                    letter: store.breakdown?.projectedLetter,
                    big: false)
            bandDivider
            reading(title: "Target",
                    value: course?.targetGrade ?? "—",
                    letter: nil,
                    big: false)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(GradeTheme.panelBg)
    }

    private var bandDivider: some View {
        Rectangle()
            .fill(GradeTheme.hairline)
            .frame(width: 1, height: 38)
            .padding(.horizontal, 18)
    }

    private func reading(title: String, value: String, letter: String?, big: Bool) -> some View {
        let target = GradeTheme.targetCutoff(forLetter: course?.targetGrade)
        let tone: Color = {
            guard big, let pct = store.breakdown?.currentPct else { return .primary }
            return GradeTheme.health(pct: pct, target: target)
        }()
        return VStack(alignment: .trailing, spacing: 2) {
            EyebrowLabel(title)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(GradeTheme.metric(big ? 34 : 22, weight: big ? .bold : .semibold))
                    .foregroundStyle(tone)
                if let letter {
                    Text(letter)
                        .font(GradeTheme.metric(big ? 17 : 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: value)
    }

    // MARK: - Matrix

    private var matrix: some View {
        VStack(spacing: 0) {
            actionRow
            Divider()
            if store.categories.isEmpty {
                emptyMatrix
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.categories, id: \.id) { cat in
                            categoryBlock(cat)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            EyebrowLabel("Grade items")
            Spacer()
            compactButton("Category", "folder.badge.plus") { showingNewCategory = true }
            compactButton("Item", "plus") { showingNewItem = true }
            compactButton("Refresh", "arrow.clockwise") {
                _Concurrency.Task { await store.refreshBreakdown() }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
    }

    private func compactButton(_ label: String, _ symbol: String,
                               _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(GradeTheme.accent)
    }

    private func categoryBlock(_ cat: GradeCategory) -> some View {
        let catBreakdown = store.breakdown?.perCategory.first { $0.categoryId == cat.id }
        let items = store.items.filter { $0.categoryId == cat.id }
        return VStack(spacing: 0) {
            // Category header — swipe left to delete the whole category
            SwipeToDelete(onDelete: {
                _Concurrency.Task { await store.deleteCategory(cat.id) }
            }) {
            HStack(spacing: 8) {
                Text(cat.name)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(Int(cat.weightPct))%")
                    .font(GradeTheme.mono(10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(GradeTheme.hairline, in: RoundedRectangle(cornerRadius: 3))
                Spacer()
                if let cb = catBreakdown {
                    Text("\(GradeTheme.num(cb.currentPct))%")
                        .font(GradeTheme.metric(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Button { editingCategory = cat } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 7)
            }

            if items.isEmpty {
                HStack {
                    Text("No items yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            } else {
                ForEach(items, id: \.id) { item in
                    SwipeToDelete(onDelete: {
                        _Concurrency.Task { await store.deleteItem(item.id) }
                    }) {
                        itemRow(item, dropped: catBreakdown?.droppedItemIds.contains(item.id) ?? false)
                    }
                }
            }
            Divider().padding(.leading, 22)
        }
    }

    private func itemRow(_ item: GradeItem, dropped: Bool) -> some View {
        let graded = item.earnedPoints != nil
        return HStack(spacing: 10) {
            Circle()
                .fill(graded ? GradeTheme.accent.opacity(0.85) : Color.secondary.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(item.name)
                .font(.system(size: 12.5))
                .strikethrough(dropped, color: .secondary)
                .foregroundStyle(dropped ? .secondary : .primary)
            if item.isExtraCredit {
                Text("EC")
                    .font(GradeTheme.mono(8.5, weight: .semibold))
                    .foregroundStyle(GradeTheme.accent)
                    .padding(.horizontal, 3).padding(.vertical, 0.5)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(GradeTheme.accent.opacity(0.4)))
            }
            if dropped {
                Text("dropped")
                    .font(GradeTheme.mono(9))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let earned = item.earnedPoints {
                Text("\(GradeTheme.num(earned))")
                    .font(GradeTheme.metric(12.5, weight: .semibold))
                + Text(" / \(GradeTheme.num(item.maxPoints))")
                    .font(GradeTheme.metric(12.5, weight: .regular))
            } else {
                Text("ungraded")
                    .font(GradeTheme.mono(10))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { editingItem = item }
    }

    private var emptyMatrix: some View {
        VStack(spacing: 6) {
            Text("No categories yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Add a category (e.g. Homework 30%) to start tracking grades.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sheets

    private func categorySheet(_ existing: GradeCategory?) -> some View {
        CategoryEditorSheet(courseId: store.selectedCourseId ?? "", existing: existing) { _ in
            if let id = store.selectedCourseId { _Concurrency.Task { await store.selectCourse(id) } }
        }
    }

    private func itemSheet(_ existing: GradeItem?) -> some View {
        GradeItemEditorSheet(courseId: store.selectedCourseId ?? "",
                             categories: store.categories,
                             existing: existing) { _ in
            if let id = store.selectedCourseId { _Concurrency.Task { await store.selectCourse(id) } }
        }
    }
}
