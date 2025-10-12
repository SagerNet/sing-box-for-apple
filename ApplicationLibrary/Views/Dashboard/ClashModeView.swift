import Libbox
import Library
import SwiftUI

@MainActor
public struct ClashModeView: View {
    @EnvironmentObject private var commandClient: CommandClient
    @StateObject private var viewModel = ClashModeViewModel()

    public init() {}
    public var body: some View {
        VStack {
            if viewModel.shouldShowPicker {
                Picker("", selection: Binding(get: {
                    viewModel.clashMode
                }, set: { newMode in
                    viewModel.clashMode = newMode
                    Task {
                        await viewModel.setClashMode(newMode)
                    }
                }), content: {
                    ForEach(viewModel.clashModeList, id: \.self) { mode in
                        Text(mode)
                    }
                })
                .pickerStyle(.segmented)
                .padding([.top], 8)
            }
        }
        .padding([.leading, .trailing])
        .onAppear {
            viewModel.setCommandClient(commandClient)
        }
        .alertBinding($viewModel.alert)
    }
}
