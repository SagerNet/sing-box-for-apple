import Foundation
import Libbox
import Library

NativeCrashReporter.installForCurrentProcess(
    basePath: URL(fileURLWithPath: WorkingDirectoryManager.helperNativeCrashBasePath, isDirectory: true)
)

let pendingCrashLogs = RootHelperService.readCrashLogFiles()

let setupOptions = LibboxSetupOptions()
setupOptions.basePath = WorkingDirectoryManager.helperBasePath
setupOptions.workingPath = WorkingDirectoryManager.helperWorkingDirectoryPath
setupOptions.tempPath = WorkingDirectoryManager.helperTempDirectoryPath
setupOptions.crashReportSource = "RootHelper"
var setupError: NSError?
LibboxSetup(setupOptions, &setupError)

let service = RootHelperService()
service.pendingCrashLogs = pendingCrashLogs
service.start()
dispatchMain()
