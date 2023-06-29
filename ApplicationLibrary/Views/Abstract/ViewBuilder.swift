import Foundation
import SwiftUI

public func viewBuilder(@ViewBuilder _ builder: () -> some View) -> some View {
    builder()
}
