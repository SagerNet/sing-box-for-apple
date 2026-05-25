import Combine
import Foundation
import GhosttyKit
import GhosttyTerminal

/// Forwarder delegate set on the underlying AppTerminalView / UITerminalView
/// in place of TerminalViewState. Forwards every protocol TerminalViewState
/// already implements back to it (so its @Published-equivalent state stays
/// in sync), and additionally implements OpenURL / HoverLink / Progress
/// which TerminalViewState does not conform to upstream.
@MainActor
public final class TailsshTerminalExtras: NSObject, ObservableObject,
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceGridResizeDelegate,
    TerminalSurfaceFocusDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceDesktopNotificationDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceLifecycleDelegate,
    TerminalSurfaceOpenURLDelegate,
    TerminalSurfaceHoverLinkDelegate,
    TerminalSurfaceProgressReportDelegate,
    TerminalSurfaceTextSelectionRequestDelegate
{
    public weak var state: TerminalViewState?

    public var onClose: ((Bool) -> Void)?
    public var onOpenURL: ((String, TerminalOpenURLKind) -> Void)?
    public var onDesktopNotification: ((String, String) -> Void)?
    public var onRequestTextSelection: ((TerminalTextSelectionRequest) -> Void)?

    @Published public var title: String = ""
    @Published public var hoveredLink: String?
    @Published public var lastProgressState: TerminalProgressState?
    @Published public var lastProgressPercent: Int?

    override public init() {
        super.init()
    }

    public func terminalDidChangeTitle(_ title: String) {
        state?.terminalDidChangeTitle(title)
        self.title = title
    }

    public func terminalDidResize(_ size: TerminalGridMetrics) {
        state?.terminalDidResize(size)
    }

    public func terminalDidChangeFocus(_ focused: Bool) {
        state?.terminalDidChangeFocus(focused)
    }

    public func terminalDidClose(processAlive: Bool) {
        state?.terminalDidClose(processAlive: processAlive)
        onClose?(processAlive)
    }

    public func terminalDidRingBell() {
        state?.terminalDidRingBell()
    }

    public func terminalDidRequestDesktopNotification(title: String, body: String) {
        state?.terminalDidRequestDesktopNotification(title: title, body: body)
        onDesktopNotification?(title, body)
    }

    public func terminalDidChangeWorkingDirectory(_ path: String) {
        state?.terminalDidChangeWorkingDirectory(path)
    }

    public func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        state?.terminalDidFinishCommand(exitCode: exitCode, durationNanos: durationNanos)
    }

    public func terminalDidAttachSurface(_ surface: TerminalSurface) {
        state?.terminalDidAttachSurface(surface)
    }

    public func terminalDidDetachSurface() {
        state?.terminalDidDetachSurface()
    }

    public func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        onOpenURL?(url, kind)
    }

    public func terminalDidUpdateHoverLink(_ url: String?) {
        hoveredLink = url
    }

    public func terminalDidReportProgress(state: TerminalProgressState, percent: Int?) {
        lastProgressState = state
        lastProgressPercent = percent
    }

    public func terminalDidRequestTextSelection(_ request: TerminalTextSelectionRequest) {
        onRequestTextSelection?(request)
    }
}
