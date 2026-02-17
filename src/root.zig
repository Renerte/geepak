//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

const FileEntry = struct { name: []u8, size: u32 };

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
    std.log.info("Extracting {} files...", .{fileEntries.len});
    errdefer bufferedPrint("\n", .{}) catch unreachable;
    var writeBuf: [8192]u8 = undefined;
    for (fileEntries, 0..) |fileEntry, i| {
        const path, const fileName = splitFilePath(fileEntry.name);
        try bufferedPrint("\r\x1b[2K{d: >5}/{d} | {s}/{s}", .{i + 1, fileCount, path, fileName});
        const dir = try target.makeOpenPath(path, .{});
        var file = try dir.createFile(fileName, .{});
        defer file.close();
        var writer = file.writerStreaming(&writeBuf);
        try reader.interface.streamExact(&writer.interface, fileEntry.size);
        try writer.interface.flush();
    }
    try bufferedPrint("\r\x1b[2K", .{});
}

fn splitFilePath(path: []const u8) struct { []const u8, []const u8 } {
    std.debug.assert(path.len > 1);
    const idx = findLast(path, '/');
    return .{ path[0..idx], path[(idx + 1)..path.len] };
}

fn findLast(array: []const u8, element: u8) usize {
    var idx: usize = 0;
    for (array, 0..) |el, i| {
        if (el == element) idx = i;
    }
    return idx;
}

fn bufferedPrint(comptime fmt: []const u8, args: anytype) !void {
    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writerStreaming(&stdoutBuf);
    try stdout.interface.print(fmt, args);
    try stdout.interface.flush();
}
