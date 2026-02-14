//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

const FileEntry = struct {
    name: []u8,
    size: u32
};

pub fn unpackArchive(allocator: std.mem.Allocator, archive: std.fs.File, target: std.fs.Dir) !void {
    var buffer: [64]u8 = undefined;
    var reader = archive.reader(&buffer);
    const fileCountBuf = try reader.interface.readAlloc(allocator, 4);
    defer allocator.free(fileCountBuf);
    const fileCount = std.mem.readPackedInt(u32, fileCountBuf, 0, .little);
    const fileEntries = try allocator.alloc(FileEntry, fileCount);
    defer allocator.free(fileEntries);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (fileEntries) |*fileEntry| {
        const fileNameLenBuf = try reader.interface.readAlloc(allocator, 2);
        defer allocator.free(fileNameLenBuf);
        const fileNameLen = std.mem.readPackedInt(u16, fileNameLenBuf, 0, .little);
        const fileName = try reader.interface.readAlloc(arena.allocator(), fileNameLen);
        const fileSizeBuf = try reader.interface.readAlloc(allocator, 4);
        defer allocator.free(fileSizeBuf);
        const fileSize = std.mem.readPackedInt(u32, fileSizeBuf, 0, .little);
        fileEntry.* = FileEntry {
            .name = fileName,
            .size = fileSize
        };
    }
    std.log.info("Extracting {} files...", .{ fileEntries.len });
    for (fileEntries) |fileEntry| {
        const path, const fileName = splitFilePath(fileEntry.name);
        std.log.debug("Writing '{s}' in '{s}'", .{ fileName, path });
        const dir = try target.makeOpenPath(path, .{});
        var file = try dir.createFile(fileName, .{});
        defer file.close();
        const contentsBuf = try reader.interface.readAlloc(allocator, fileEntry.size);
        defer allocator.free(contentsBuf);
        try file.writeAll(contentsBuf);
    }
    _ = @TypeOf(target);
}

fn splitFilePath(path: []const u8) struct {[]const u8, [] const u8} {
    std.debug.assert(path.len > 1);
    const idx = findLast(path, '/');
    return .{
        path[0..idx],
        path[(idx + 1)..path.len]
    };
}

fn findLast(array: []const u8, element: u8) usize {
    var idx: usize = 0;
    for (array, 0..) |el, i| {
        if (el == element) idx = i;
    }
    return idx;
}
