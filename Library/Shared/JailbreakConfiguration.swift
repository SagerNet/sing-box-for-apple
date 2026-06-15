#if JAILBREAK
    import Foundation

    public enum JailbreakConfiguration {
        /// procursus rootless prefix (palera1n / Dopamine default).
        public static let rootlessPrefix = "/var/jb"

        public static let shellCandidates = [
            "\(rootlessPrefix)/bin/bash",
            "\(rootlessPrefix)/bin/zsh",
            "\(rootlessPrefix)/bin/fish",
            "\(rootlessPrefix)/bin/sh",
            "/bin/sh",
        ]

        public static let sftpServerPath = "\(rootlessPrefix)/usr/libexec/sftp-server"

        public static let systemSSHHostKeyPath = "\(rootlessPrefix)/etc/ssh/ssh_host_ed25519_key"
    }
#endif
