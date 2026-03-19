const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.process);

/// Get the name of the foreground process in the PTY session.
/// Returns allocated string or null if no foreground process.
/// Caller owns returned memory.
pub fn getForegroundProcessName(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    return switch (builtin.os.tag) {
        .linux => getForegroundProcessNameLinux(alloc, pty_master_fd),
        .macos => getForegroundProcessNameBSD(alloc, pty_master_fd),
        else => null,
    };
}

const c_unistd = @cImport({
    @cInclude("unistd.h");
});

fn getForegroundProcessNameLinux(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    const pgid = c_unistd.tcgetpgrp(pty_master_fd);
    if (pgid <= 0) return null;

    var proc_dir = std.fs.openDirAbsolute("/proc", .{ .iterate = true }) catch |err| {
        log.warn("failed to open /proc: {}", .{err});
        return null;
    };
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;

        const pid = std.fmt.parseInt(posix.pid_t, entry.name, 10) catch continue;

        const pid_pgid = c_unistd.getpgid(pid);
        if (pid_pgid == pgid) {
            var buf: [32]u8 = undefined;
            const comm_path = std.fmt.bufPrint(&buf, "/proc/{d}/comm", .{pid}) catch continue;

            const comm_file = std.fs.openFileAbsolute(comm_path, .{}) catch continue;
            defer comm_file.close();

            var name_buf: [16]u8 = undefined;
            const bytes_read = comm_file.readAll(&name_buf) catch continue;
            if (bytes_read == 0) continue;

            const name = std.mem.trimRight(u8, name_buf[0..bytes_read], "\n");
            return try alloc.dupe(u8, name);
        }
    }

    return null;
}

fn getForegroundProcessNameBSD(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    const pgid = c_unistd.tcgetpgrp(pty_master_fd);
    if (pgid <= 0) return null;

    const c = @cImport({
        @cInclude("libproc.h");
    });

    var pids_buf: [4096]c_int = undefined;
    const buf_size = @sizeOf(@TypeOf(pids_buf));
    const bytes = c.proc_listallpids(&pids_buf, buf_size);
    if (bytes <= 0) return null;

    const pid_count = @divTrunc(bytes, @sizeOf(c_int));
    for (pids_buf[0..@intCast(pid_count)]) |pid| {
        if (pid <= 0) continue;

        const pid_pgid = c_unistd.getpgid(pid);
        if (pid_pgid == pgid) {
            var bsdinfo: c.proc_bsdinfo = undefined;
            const ret = c.proc_pidinfo(
                pid,
                c.PROC_PIDTBSDINFO,
                0,
                &bsdinfo,
                @sizeOf(c.proc_bsdinfo),
            );
            if (ret <= 0) continue;

            const name = std.mem.sliceTo(&bsdinfo.pbi_name, 0);
            if (name.len == 0) continue;

            return try alloc.dupe(u8, name);
        }
    }

    return null;
}

test "unsupported platform returns null" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const result = try getForegroundProcessName(std.testing.allocator, 0);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "invalid fd returns null" {
    const result = try getForegroundProcessName(std.testing.allocator, -1);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}
