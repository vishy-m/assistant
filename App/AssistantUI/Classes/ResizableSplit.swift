import SwiftUI

enum PanelEdge { case leading, trailing, bottom }

/// Wraps `center` with one resizable, collapsible `panel` docked on `edge`.
/// `size` (width for leading/trailing, height for bottom) and `collapsed` are
/// bindings the caller persists. A draggable divider resizes; a chevron collapses.
struct ResizableSplit<Center: View, Panel: View>: View {
    let edge: PanelEdge
    @Binding var size: CGFloat
    @Binding var collapsed: Bool
    let range: ClosedRange<CGFloat>
    @ViewBuilder var center: () -> Center
    @ViewBuilder var panel: () -> Panel

    private let railThickness: CGFloat = 22
    private let dividerThickness: CGFloat = 6

    var body: some View {
        switch edge {
        case .leading:  hStack(panelFirst: true)
        case .trailing: hStack(panelFirst: false)
        case .bottom:   vStack()
        }
    }

    private var collapseIcon: String {
        switch edge {
        case .leading:  return collapsed ? "chevron.right" : "chevron.left"
        case .trailing: return collapsed ? "chevron.left" : "chevron.right"
        case .bottom:   return collapsed ? "chevron.up" : "chevron.down"
        }
    }

    private var toggle: some View {
        Button { collapsed.toggle() } label: { Image(systemName: collapseIcon).font(.system(size: 9)) }
            .buttonStyle(.plain).padding(3)
    }

    private func hDivider() -> some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: dividerThickness)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(DragGesture().onChanged { v in
                let delta = edge == .leading ? v.translation.width : -v.translation.width
                size = min(max(size + delta, range.lowerBound), range.upperBound)
            })
    }

    private func hStack(panelFirst: Bool) -> some View {
        HStack(spacing: 0) {
            if panelFirst { panelOrRail; if !collapsed { hDivider() } }
            center().frame(maxWidth: .infinity, maxHeight: .infinity)
            if !panelFirst { if !collapsed { hDivider() }; panelOrRail }
        }
    }

    private func vStack() -> some View {
        VStack(spacing: 0) {
            center().frame(maxWidth: .infinity, maxHeight: .infinity)
            if !collapsed {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: dividerThickness)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(DragGesture().onChanged { v in
                        size = min(max(size - v.translation.height, range.lowerBound), range.upperBound)
                    })
            }
            panelOrRail
        }
    }

    @ViewBuilder private var panelOrRail: some View {
        if collapsed {
            ZStack(alignment: edge == .bottom ? .center : .top) { toggle }
                .frame(width: edge == .bottom ? nil : railThickness,
                       height: edge == .bottom ? railThickness : nil)
                .background(Color.primary.opacity(0.03))
        } else {
            ZStack(alignment: .topTrailing) {
                panel()
                toggle
            }
            .frame(width: edge == .bottom ? nil : size,
                   height: edge == .bottom ? size : nil)
        }
    }
}
