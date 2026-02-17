const builtin = @import("builtin");
const std = @import("std");
const geepak = @import("geepak");

const config = @import("config");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.smp_allocator;
    std.log.info("geepak v{s}", .{config.version});
    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) {
        std.log.err("Usage: geepak <archive> [directory]", .{});
        return;
    }
    const cwd = std.fs.cwd();
    var archive = cwd.openFile(args[1], .{ .mode = .read_only }) catch {
        std.log.err("Couldn't find the archive at '{s}'", .{args[1]});
        return;
    };
    defer archive.close();
    var target = cwd.makeOpenPath(if (args.len >= 3) args[2] else directoryFromFile(args[1]), .{}) catch {
        std.log.err("Failed to prepare target directory '{s}'", .{args[2]});
        return;
    };
    defer target.close();
    std.process.argsFree(allocator, args);
    geepak.unpackArchive(allocator, archive, target) catch |e| {
        std.log.err("Error unpacking the archive:\n\t{}", .{e});
        return;
    };
    if (builtin.mode == .Debug) {
        _ = gpa.deinit();
    }
    std.log.info("Done!", .{});
}

fn directoryFromFile(filePath: []const u8) []const u8 {
    return filePath[0..geepak.findLast(filePath, '.')];
}
