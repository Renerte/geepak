const builtin = @import("builtin");
const std = @import("std");
const geepak = @import("geepak");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == std.builtin.OptimizeMode.Debug) gpa.allocator() else std.heap.smp_allocator;
    // var args = try std.process.argsWithAllocator(allocator);
    // defer args.deinit();
    // while (args.next()) |arg| {
    //     std.debug.print("Arg: {s}", arg);
    // }
    const args = try std.process.argsAlloc(allocator);
    for (args) |arg| {
        std.debug.print("Arg: {s}\n", .{ arg });
    }
    if (args.len < 3) {
        std.log.err("usage: geepak <archive> <directory>\n", .{});
        return;
    }
    const cwd = std.fs.cwd();
    var archive = cwd.openFile(args[1], .{ .mode = .read_only }) catch {
        std.log.err("Couldn't find the archive at '{s}'", .{ args[1] });
        return;
    };
    defer archive.close();
    var target = cwd.makeOpenPath(args[2], .{}) catch {
        std.log.err("Failed to prepare target directory '{s}'", .{ args[2] });
        return;
    };
    defer target.close();
    std.process.argsFree(allocator, args);
    geepak.unpackArchive(allocator, archive, target) catch |e| {
        std.log.err("Error unpacking the archive:\n\t{}", .{ e });
    };
    if (builtin.mode == .Debug) {
        _ = gpa.detectLeaks();
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
