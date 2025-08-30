const std = @import("std");
const windows = std.os.windows;
const testing = std.testing;
const rda = @import("rda.zig");
const xml = @import("xml");

const max_file = 100 * 1_048_576; //100MB

const global_allocator = std.heap.c_allocator;
var sess: *rda.RDASession = undefined;
var has_sess: bool = false;

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
                sess = rda.RDASession.init(global_allocator) catch return windows.FALSE;
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

pub const RDA = rda.RDADoc;
test {
    std.testing.refAllDecls(@This());
}

const example = "data/SRNSW_example.xml";

test "validate" {
    sess = rda.RDASession.init(testing.allocator) catch unreachable;
    has_sess = true;
    defer unload();
    const idx = load_doc(example);
    try testing.expect(valid(idx));
}
