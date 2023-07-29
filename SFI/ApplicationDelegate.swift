import ApplicationLibrary
import Foundation
import Libbox
import Library
import Network
import UIKit

class ApplicationDelegate: NSObject, UIApplicationDelegate {
    private var profileServer: ProfileServer?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NSLog("Here I stand")
        LibboxSetup(FilePath.sharedDirectory.relativePath, FilePath.workingDirectory.relativePath, FilePath.cacheDirectory.relativePath, false)
        Task.detached {
            do {
                try await UIProfileUpdateTask.setup()
                NSLog("setup background task success")
            } catch {
                NSLog("setup background task error: \(error.localizedDescription)")
            }
        }
        Task.detached {
            await self.requestNetworkPermission()
        }
        if #available(iOS 16.0, *) {
            Task.detached {
                await self.setupProfileServer()
            }
        }
        return true
    }

    @available(iOS 16.0, *)
    private func setupProfileServer() {
        do {
            let profileServer = try ProfileServer()
            profileServer.start()
            self.profileServer = profileServer
        } catch {
            NSLog("setup profile server error: \(error.localizedDescription)")
        }
    }

    private func requestNetworkPermission() {
        if UIDevice.current.userInterfaceIdiom != .phone {
            return
        }
        if SharedPreferences.networkPermissionRequested {
            return
        }
        if !DeviceCensorship.isChinaDevice() {
            SharedPreferences.networkPermissionRequested = true
            return
        }
        URLSession.shared.dataTask(with: URL(string: "http://captive.apple.com")!) { _, response, _ in
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    SharedPreferences.networkPermissionRequested = true
                }
            }
        }.resume()
    }
}
