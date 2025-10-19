const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Package = extern struct { length: i32, data: ?[*]u8 };

// Context package data is: num_entries, entries. Each entry is len,text

// TermClass package data:  [node_type, itemno_len, itemno_chars, title_len, title_chars, num_children], children.
// Root is [0,0,0,num_children]
