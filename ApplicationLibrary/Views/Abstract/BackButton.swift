import Foundation
import SwiftUI

public struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.backward")
        }
    }
}
