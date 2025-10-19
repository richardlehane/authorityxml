const std = @import("std");
const windows = std.os.windows;
const testing = std.testing;
const Session = @import("Session.zig");
const xml = @import("xml");
const Package = @import("package.zig").Package;

const max_file = 100 * 1_048_576; //100MB

const global_allocator = std.heap.c_allocator;
var sess: *Session = undefined;
var has_sess: bool = false;
var freefn: ?*const fn (?*anyopaque) callconv(.c) void = null;

const DLL_PROCESS_ATTACH: windows.DWORD = 1;
const DLL_PROCESS_DETACH: windows.DWORD = 0;
const DLL_THREAD_ATTACH: windows.DWORD = 2;
const DLL_THREAD_DETACH: windows.DWORD = 3;

// just for debugging
fn dump(name: []const u8, str: []const u8) void {
    const file = std.fs.cwd().createFile(name, .{}) catch unreachable;
    defer file.close();
    file.writeAll(str) catch unreachable;
}

pub fn DllMain(hinstDLL: windows.HINSTANCE, dwReason: windows.DWORD, lpReserved: ?windows.LPVOID) callconv(std.builtin.CallingConvention.winapi) windows.BOOL {
    _ = hinstDLL;
    switch (dwReason) {
        DLL_PROCESS_ATTACH => {
            if (!has_sess) {
                freefn = xml.xmlFree orelse null;
                sess = Session.init(global_allocator) catch return windows.FALSE;
                has_sess = true;
                dump("started", "got here");
            }
        },
        DLL_PROCESS_DETACH => {
            dump("detach", "curses");
            if (lpReserved != null and has_sess) {
                has_sess = false;
                unload();
                dump("ended", "got here");
            }
        },
        DLL_THREAD_ATTACH, DLL_THREAD_DETACH => {},
        else => {},
    }
    return windows.TRUE;
}

export fn unload() void {
    if (has_sess) {
        has_sess = false;
        for (sess.docs.items) |d| {
            d.deinit();
        }
        sess.deinit();
    }
}

export fn valid(idx: u8) bool {
    var doc = sess.get(idx);
    return doc.valid();
}

export fn load_doc(path: [*c]const u8) u8 {
    const ret = sess.load(std.mem.span(path)) catch return 255;
    return @intCast(ret);
}

export fn toStr(idx: u8) [*c]u8 {
    var doc = sess.get(idx);
    return doc.toStr();
}

export fn freeStr(ptr: [*c]u8) void {
    freefn.?(ptr);
}

// for testing. List format is: number of entries, entries
// Entry format is: length, bytes
var t_data = [_]u8{ 2, 3, 65, 66, 67, 2, 68, 69 };

export fn context(idx: u8) Package {
    const doc = sess.get(idx);
    return .{ .length = @intCast(doc.tree.items.len), .data = doc.tree.items.ptr };
}

test {
    std.testing.refAllDecls(@This());
}

const example = "data/SRNSW_example.xml";

test "validate" {
    sess = Session.init(testing.allocator) catch unreachable;
    has_sess = true;
    defer unload();
    const idx = load_doc(example);
    try testing.expect(valid(idx));
}
