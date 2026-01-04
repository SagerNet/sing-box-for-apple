import Darwin
import Foundation
import os

private let PROC_PIDPATHINFO_MAXSIZE: Int32 = 4096
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConnectionOwnerLookup")

enum ConnectionOwnerLookup {
    struct Result {
        let userId: Int32
        let userName: String
        let processPath: String
    }

    static func find(
        ipProtocol: Int32,
        sourceAddress: String,
        sourcePort: Int32,
        destinationAddress: String,
        destinationPort: Int32
    ) -> Result? {
        let sourceAddr = parseAddress(sourceAddress)
        let destAddr = parseAddress(destinationAddress)

        guard let sourceAddr, let destAddr else {
            logger.error("find: failed to parse addresses")
            return nil
        }

        let pidCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard pidCount > 0 else {
            logger.error("find: no processes found")
            return nil
        }

        let pidBufferSize = Int(pidCount) * MemoryLayout<pid_t>.size
        let pids = UnsafeMutablePointer<pid_t>.allocate(capacity: Int(pidCount))
        defer { pids.deallocate() }

        let actualCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, pids, Int32(pidBufferSize))
        guard actualCount > 0 else {
            logger.error("find: failed to list processes")
            return nil
        }

        let numPids = Int(actualCount) / MemoryLayout<pid_t>.size

        for i in 0 ..< numPids {
            let pid = pids[i]
            if pid == 0 { continue }

            if let result = checkProcessForConnection(
                pid: pid,
                ipProtocol: ipProtocol,
                sourceAddr: sourceAddr,
                sourcePort: UInt16(sourcePort),
                destAddr: destAddr,
                destPort: UInt16(destinationPort)
            ) {
                return result
            }
        }

        return nil
    }

    private static func checkProcessForConnection(
        pid: pid_t,
        ipProtocol: Int32,
        sourceAddr: Data,
        sourcePort: UInt16,
        destAddr: Data,
        destPort: UInt16
    ) -> Result? {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return nil }

        let fdBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(bufferSize), alignment: MemoryLayout<proc_fdinfo>.alignment)
        defer { fdBuffer.deallocate() }

        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fdBuffer, bufferSize)
        guard actualSize > 0 else { return nil }

        let fdCount = Int(actualSize) / MemoryLayout<proc_fdinfo>.size

        for i in 0 ..< fdCount {
            let fd = fdBuffer.load(fromByteOffset: i * MemoryLayout<proc_fdinfo>.size, as: proc_fdinfo.self)

            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var socketInfo = socket_fdinfo()
            let socketInfoSize = Int32(MemoryLayout<socket_fdinfo>.size)

            let result = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, socketInfoSize)
            guard result == socketInfoSize else { continue }

            let soi: in_sockinfo
            if ipProtocol == IPPROTO_TCP {
                guard socketInfo.psi.soi_kind == SOCKINFO_TCP else { continue }
                soi = socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini
            } else if ipProtocol == IPPROTO_UDP {
                guard socketInfo.psi.soi_kind == SOCKINFO_IN else { continue }
                soi = socketInfo.psi.soi_proto.pri_in
            } else {
                continue
            }

            if matchesConnection(
                socketInfo: soi,
                sourceAddr: sourceAddr,
                sourcePort: sourcePort,
                destAddr: destAddr,
                destPort: destPort
            ) {
                return getProcessInfo(pid: pid)
            }
        }

        return nil
    }

    private static func matchesConnection(
        socketInfo: in_sockinfo,
        sourceAddr: Data,
        sourcePort: UInt16,
        destAddr: Data,
        destPort: UInt16
    ) -> Bool {
        let localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: socketInfo.insi_lport))
        let remotePort = UInt16(bigEndian: UInt16(truncatingIfNeeded: socketInfo.insi_fport))

        guard localPort == sourcePort, remotePort == destPort else {
            return false
        }

        var localAddr = socketInfo.insi_laddr
        var remoteAddr = socketInfo.insi_faddr

        let localData: Data
        let remoteData: Data

        if sourceAddr.count == 4 {
            localData = Data(bytes: &localAddr.ina_46.i46a_addr4, count: 4)
            remoteData = Data(bytes: &remoteAddr.ina_46.i46a_addr4, count: 4)
        } else {
            localData = Data(bytes: &localAddr.ina_6, count: 16)
            remoteData = Data(bytes: &remoteAddr.ina_6, count: 16)
        }

        return localData == sourceAddr && remoteData == destAddr
    }

    private static func getProcessInfo(pid: pid_t) -> Result? {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(PROC_PIDPATHINFO_MAXSIZE))
        defer { pathBuffer.deallocate() }

        let pathLength = proc_pidpath(pid, pathBuffer, UInt32(PROC_PIDPATHINFO_MAXSIZE))
        let processPath = pathLength > 0 ? String(cString: pathBuffer) : ""

        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize)

        guard result == infoSize else { return nil }

        let uid = Int32(info.pbi_uid)
        let userName: String

        if let pw = getpwuid(info.pbi_uid) {
            userName = String(cString: pw.pointee.pw_name)
        } else {
            userName = String(uid)
        }

        return Result(userId: uid, userName: userName, processPath: processPath)
    }

    private static func parseAddress(_ address: String) -> Data? {
        var addr4 = in_addr()
        if inet_pton(AF_INET, address, &addr4) == 1 {
            return Data(bytes: &addr4, count: 4)
        }

        var addr6 = in6_addr()
        if inet_pton(AF_INET6, address, &addr6) == 1 {
            return Data(bytes: &addr6, count: 16)
        }

        return nil
    }
}
