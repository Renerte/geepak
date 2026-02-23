//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

const utils = @import("utils");

const FileEntry = struct { name: []const u8, size: u32 };

pub fn unpackArchive(allocator: std.mem.Allocator, archive: std.fs.File, target: std.fs.Dir) !void {
    var readBuf: [8192]u8 = undefined;
    var reader = archive.readerStreaming(&readBuf);
    const fileCount = try reader.interface.takeInt(u32, .little);
    const fileEntries = try allocator.alloc(FileEntry, fileCount);
    defer allocator.free(fileEntries);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (fileEntries) |*fileEntry| {
        const nameLen = try reader.interface.takeInt(u16, .little);
        const name = try reader.interface.readAlloc(arena.allocator(), nameLen);
        const size = try reader.interface.takeInt(u32, .little);
        fileEntry.* = FileEntry{ .name = name, .size = size };
    }
    std.log.info("Extracting {d} files...", .{fileEntries.len});
    errdefer bufferedPrint("\n", .{}) catch unreachable;
    const progress = try Progress.init(allocator, fileCount);
    defer progress.deinit();
    var writeBuf: [8192]u8 = undefined;
    for (fileEntries, 1..) |fileEntry, i| {
        try progress.print(i, fileEntry.name);
        const path = directoryFromPath(fileEntry.name);
        if (path) |dir| try target.makePath(dir);
        var file = try target.createFile(fileEntry.name, .{});
        defer file.close();
        var writer = file.writerStreaming(&writeBuf);
        try reader.interface.streamExact(&writer.interface, fileEntry.size);
        try writer.end();
    }
    try bufferedPrint("\r\x1b[2K", .{});
}

pub fn packArchive(allocator: std.mem.Allocator, source: std.fs.Dir, archive: std.fs.File) !void {
    var fileCount: u32 = 0;
    {
        var fileCounter = try source.walk(allocator);
        defer fileCounter.deinit();
        while (try fileCounter.next()) |entry| {
            if (entry.kind == .file) fileCount += 1;
        }
    }
    const fileEntries = try allocator.alloc(FileEntry, fileCount);
    defer allocator.free(fileEntries);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var dirWalker = try source.walk(allocator);
    defer dirWalker.deinit();
    var entryIndex: u32 = 0;
    while (try dirWalker.next()) |entry| {
        if (entry.kind == .file) {
            const path = try normalizeFilePath(arena.allocator(), entry.path);
            const file = try entry.dir.openFile(entry.basename, .{});
            defer file.close();
            const stat = try file.stat();
            fileEntries[entryIndex] = FileEntry{.name = path, .size = @intCast(stat.size)};
            entryIndex += 1;
            try bufferedPrint("\r\x1b[2KCollected files: {d}", .{entryIndex});
        }
    }
    try bufferedPrint("\r\x1b[2K", .{});
    std.log.info("Packing {d} files!", .{fileCount});
    var writeBuf: [8192]u8 = undefined;
    var writer = archive.writerStreaming(&writeBuf);
    const progress = try Progress.init(allocator, fileCount);
    defer progress.deinit();
    try writer.interface.writeInt(u32, fileCount, .little);
    std.log.info("Writing file entries...", .{});
    for (fileEntries, 1..) |fileEntry, i| {
        try progress.print(i, fileEntry.name);
        try writer.interface.writeInt(u16, @intCast(fileEntry.name.len), .little);
        try writer.interface.writeAll(fileEntry.name);
        try writer.interface.writeInt(u32, fileEntry.size, .little);
    }
    try bufferedPrint("\r\x1b[2K", .{});
    std.log.info("Writing file contents...", .{});
    for (fileEntries, 1..) |fileEntry, i| {
        try progress.print(i, fileEntry.name);
        var file = try source.openFile(fileEntry.name, .{});
        defer file.close();
        var readBuf: [8192]u8 = undefined;
        var reader = file.readerStreaming(&readBuf);
        try reader.interface.streamExact(&writer.interface, fileEntry.size);
    }
    try writer.end();
    try bufferedPrint("\r\x1b[2K", .{});
}

fn directoryFromPath(path: []const u8) ?[]const u8 {
    std.debug.assert(path.len > 1);
    const idx = utils.findLast(path, '/');
    if (idx) |i| {
        return path[0..i];
    } else {
        return null;
    }
}

fn normalizeFilePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    std.debug.assert(path.len > 0);
    const result = try allocator.alloc(u8, path.len);
    for (path, 0..) |char, i| {
        result[i] = if (char != '\\') char else '/';
    }
    return result;
}

const Progress = struct {
    _allocator: std.mem.Allocator,
    _targetStr: []const u8,
    _padBuf: []const u8,

    pub fn init(allocator: std.mem.Allocator, target: usize) !Progress {
        const targetStr = try std.fmt.allocPrint(allocator, "{d}", .{target});
        const padBuf = try allocator.alloc(u8, targetStr.len);
        @memset(padBuf, ' ');
        return Progress{ ._allocator = allocator, ._targetStr = targetStr, ._padBuf = padBuf };
    }

    pub fn print(self: Progress, count: usize, path: []const u8) !void {
        const countStr = try std.fmt.allocPrint(self._allocator, "{d}", .{count});
        defer self._allocator.free(countStr);
        try bufferedPrint("\r\x1b[2K{s}{s}/{s} | {s}", .{ self._padBuf[0..(self._targetStr.len - countStr.len)], countStr, self._targetStr, path });
    }

    pub fn deinit(self: Progress) void {
        self._allocator.free(self._targetStr);
        self._allocator.free(self._padBuf);
    }
};

fn bufferedPrint(comptime fmt: []const u8, args: anytype) !void {
    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writerStreaming(&stdoutBuf);
    try stdout.interface.print(fmt, args);
    try stdout.interface.flush();
}
