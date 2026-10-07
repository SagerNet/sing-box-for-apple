import Foundation
import Library
import os

@_silgen_name("memorystatus_control")
private func memorystatusControl(_ command: UInt32, _ pid: Int32, _ flags: Int32, _ buffer: UnsafeMutableRawPointer?, _ bufferSize: Int) -> Int32

// MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT from xnu's kern_memorystatus.h; a limit of -1 removes it.
private let memorystatusCommandSetJetsamTaskLimit: UInt32 = 6

if memorystatusControl(memorystatusCommandSetJetsamTaskLimit, getpid(), -1, nil, 0) != 0 {
    Logger(category: "RootHelper").error("remove memory limit: \(String(cString: strerror(errno)), privacy: .public)")
}

let service = IOSRootHelperService()
service.start()
dispatchMain()
