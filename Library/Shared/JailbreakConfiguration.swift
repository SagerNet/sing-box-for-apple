#if JAILBREAK
    import Foundation

    public enum JailbreakConfiguration {
        public static let roothideRoot: String? = {
            let components = Bundle.main.bundleURL.pathComponents
            guard let index = components.firstIndex(where: { $0.hasPrefix(".jbroot-") }) else {
                return nil
            }
            return NSString.path(withComponents: Array(components[...index]))
        }()

        public static let root = roothideRoot ?? "/var/jb"

        public static let shellCandidates = [
            "\(root)/bin/bash",
            "\(root)/bin/zsh",
            "\(root)/bin/fish",
            "\(root)/bin/sh",
            "/bin/sh",
        ]

        public static let sftpServerPath = roothideRoot == nil ? "\(root)/usr/libexec/sftp-server" : "/usr/libexec/sftp-server"

        public static let systemSSHHostKeyPath = "\(root)/etc/ssh/ssh_host_ed25519_key"
    }
#endif
