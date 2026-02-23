const builtin = @import("builtin");
const std = @import("std");
const geepak = @import("geepak");

const config = @import("config");
const utils = @import("utils");

const Mode = enum { none, unpack, pack };

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.smp_allocator;
    std.log.info("geepak v{s}", .{config.version});
    const cwd = std.fs.cwd();
    var archive: ?std.fs.File = null;
    var directory: ?std.fs.Dir = null;
    var firstArg: []u8 = undefined;
    var mode = Mode.none;
    var argsIter = try std.process.argsWithAllocator(allocator);
    if (!argsIter.skip()) return;
    while (argsIter.next()) |arg| {
        switch (mode) {
            .none => {
                firstArg = try allocator.alloc(u8, arg.len);
                @memcpy(firstArg, arg);
                const stat = cwd.statFile(arg) catch |err| switch (err) {
                    error.IsDir => {
                        directory = try cwd.openDir(arg, .{ .iterate = true });
                        mode = .pack;
                        continue;
                    },
                    else => {
                        std.log.err("Error parsing the arguments: {}", .{err});
                        return;
                    }
                };
                switch (stat.kind) {
                    .file => {
                        archive = try cwd.openFile(arg, .{});
                        mode = .unpack;
                    },
                    .directory => {
                        directory = try cwd.openDir(arg, .{ .iterate = true });
                        mode = .pack;
                    },
                    else => {}
                }
            },
            .pack => archive = try cwd.createFile(arg, .{}),
            .unpack => directory = try cwd.makeOpenPath(arg, .{})
        }
    }
    argsIter.deinit();
    if (archive == null) {
        const archivePath = try fileFromDirectory(allocator, firstArg);
        defer allocator.free(archivePath);
        archive = try cwd.createFile(archivePath, .{});
    } else if (directory == null) {
        directory = try cwd.makeOpenPath(directoryFromFile(firstArg), .{});
    }
    allocator.free(firstArg);
    switch (mode) {
        .none => std.log.warn("Usage: geepak <source archive/directory> [target file/directory]", .{}),
        .pack => try geepak.packArchive(allocator, directory.?, archive.?),
        .unpack => geepak.unpackArchive(allocator, archive.?, directory.?) catch |e| {
            std.log.err("Error unpacking the archive:\n\t{}", .{e});
            return e;
        }
    }
    if (builtin.mode == .Debug) {
        _ = gpa.deinit();
    }
    std.log.info("Done!", .{});
}

fn directoryFromFile(filePath: []const u8) []const u8 {
    return filePath[0..(utils.findLast(filePath, '.') orelse filePath.len)];
}

fn fileFromDirectory(allocator: std.mem.Allocator, dirPath: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}.gpak", .{dirPath});
}
