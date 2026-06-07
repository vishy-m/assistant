import SwiftUI
import AssistantShared

struct ClassInfoEditorSheet: View {
    let detail: ClassDetail
    let onSave: () -> Void
    var body: some View { Text("Edit class").padding(40) }
}
