//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn unpackArchive(allocator: std.mem.Allocator, archive: std.fs.File, target: std.fs.Dir) !void {
    var buffer: [64]u8 = undefined;
    var reader = archive.reader(&buffer);
    const fileCountBuf = try reader.interface.readAlloc(allocator, 4);
    defer allocator.free(fileCountBuf);
    const fileCount = std.mem.readPackedInt(u32, fileCountBuf, 0, .little);
    const fileNames = try allocator.alloc([]u8, fileCount);
    defer allocator.free(fileNames);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (fileNames) |*fileNamePtr| {
        const fileNameLenBuf = try reader.interface.readAlloc(allocator, 2);
        defer allocator.free(fileNameLenBuf);
        const fileNameLen = std.mem.readPackedInt(u16, fileNameLenBuf, 0, .little);
        const fileName = try reader.interface.readAlloc(arena.allocator(), fileNameLen);
        std.log.debug("\tFile name -> '{s}'", .{ fileName });
        fileNamePtr.* = fileName;
        const fileSizeBuf = try reader.interface.readAlloc(allocator, 4);
        defer allocator.free(fileSizeBuf);
    }
    std.log.debug("Extracting {} files, example: '{s}'", .{ fileNames.len, fileNames[0] });
    _ = @TypeOf(target);
}

pub fn bufferedPrint(comptime fmt: []const u8, args: anytype) !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print(fmt, args);

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
