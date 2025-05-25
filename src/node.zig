const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const xml = @import("xml");

pub fn equals(a: [*]const xml.xmlChar, b: []const u8) bool {
    for (b, 0..) |char, idx| if (a[idx] != char) return false;
    return a[b.len] == 0;
}

// length includes the sentinel
fn xmlStrLen(a: [*]const xml.xmlChar) usize {
    var idx: usize = 0;
    while (true) : (idx += 1) if (a[idx] == 0) return idx + 1;
}

pub fn xmlStrDup(ally: Allocator, a: [*]const xml.xmlChar) ![:0]const u8 {
    const len = xmlStrLen(a);
    const arr = try ally.alloc(u8, len);
    var idx: usize = 0;
    while (idx < len) : (idx += 1) {
        arr[idx] = a[idx];
    }
    return arr[0 .. len - 1 :0];
}

pub fn xmlStrJoin(ally: Allocator, strs: []const [*]const xml.xmlChar, j: []const u8) ![:0]const u8 {
    var len: usize = 1; // include the sentinel
    for (strs, 0..) |str, i| {
        if (i > 0) len += j.len;
        len = len + xmlStrLen(str) - 1;
    }
    const arr = try ally.alloc(u8, len);
    var idx: usize = 0;
    for (strs, 0..) |str, i| {
        if (i > 0) {
            for (j) |char| {
                arr[idx] = char;
                idx += 1;
            }
        }
        const xl = xmlStrLen(str) - 1;
        var xi: usize = 0;
        while (xi < xl) : (xi += 1) {
            arr[idx] = str[xi];
            idx += 1;
        }
    }
    arr[idx] = 0;
    return arr[0 .. len - 1 :0];
}

/// Returns the Nth child of node
pub fn childN(node: xml.xmlNodePtr, name: []const u8, nth: usize) ?xml.xmlNodePtr {
    var current_node = node.*.children;
    var idx: usize = 0;
    while (current_node != null) : (current_node = current_node.*.next) {
        if (equals(current_node.*.name, name)) {
            if (idx == nth) return current_node;
            idx += 1;
        }
    }
    return null;
}

/// Returns the contents of the first child element of node with the given name
pub fn attrValue(ally: Allocator, node: xml.xmlNodePtr, name: []const u8) ?[:0]const u8 {
    return xmlStrDup(ally, xml.xmlGetProp(node, name)) catch null;
}

/// Returns the contents of the first child element of node with the given name
pub fn elementValue(ally: Allocator, node: xml.xmlNodePtr, name: []const u8) ?[:0]const u8 {
    const current_node = childN(node, name, 0) orelse return null;
    return xmlStrDup(ally, xml.xmlNodeGetContent(current_node)) catch null;
}

test "strdup" {
    const a = "hello";
    const b = try xmlStrDup(testing.allocator, a);
    try testing.expect(xmlStrLen(a) == xmlStrLen(b.ptr));
    testing.allocator.free(b);
}

test "strjoin" {
    const a = try xmlStrJoin(testing.allocator, &.{ "test", "apple", "pie" }, " - ");
    try testing.expect(xmlStrLen("test - apple - pie") == xmlStrLen(a.ptr));
    testing.allocator.free(a);
}
