import Darwin
import Foundation

/// The calling Claude Code instance's identity, resolved from process
/// ancestry: walk parents until the nearest `claude` process and key on its
/// pid + start time (start time defeats pid reuse). Every process a Claude
/// instance spawns — Bash tool commands, hook scripts, Task subagents — is a
/// descendant of that instance, so they all resolve the SAME key, while a
/// second Claude instance running a different prompt on the same gm session
/// resolves a different one. That is what lets the daemon's activation
/// registry keep several prompts active per session without last-writer-wins
/// clobbering, and what makes a spawned agent's briefing lookup
/// deterministic (no uuid has to survive a spawn prompt).
///
/// nil when no claude ancestor exists (a bare terminal running gm by hand):
/// callers omit the key and the daemon falls back to the session's single
/// activation when unambiguous.
enum ClientKey {
    static func resolve() -> String? {
        var pid = getpid()
        var hops = 0
        while pid > 1, hops < 64 {
            guard let info = procInfo(pid) else { return nil }
            var proc = info.kp_proc
            let comm = withUnsafeBytes(of: &proc.p_comm) { raw -> String in
                guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
                return String(cString: base)
            }
            if comm.lowercased().hasPrefix("claude") {
                return "claude:\(pid):\(proc.p_starttime.tv_sec)"
            }
            pid = info.kp_eproc.e_ppid
            hops += 1
        }
        return nil
    }

    private static func procInfo(_ pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let rc = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard rc == 0, size > 0 else { return nil }
        return info
    }
}
