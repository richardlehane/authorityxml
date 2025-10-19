const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const node = @import("node.zig"); // todo: get rid of these helpers
const xml = @import("xml");

pub const NodeType = enum(u8) {
    Authority,
    Term,
    Class,
    Context,
    None,

    fn fromStr(a: [*]const xml.xmlChar) NodeType {
        if (node.equals(a, "Authority")) return .Authority;
        if (node.equals(a, "Term")) return .Term;
        if (node.equals(a, "Class")) return .Class;
        if (node.equals(a, "Context")) return .Context;
        return .None;
    }

    pub fn toStr(tc: NodeType) []const u8 {
        return switch (tc) {
            .Authority => "Authority",
            .Term => "Term",
            .Class => "Class",
            .Context => "Context",
            .None => "Neither",
        };
    }

    fn title(tc: NodeType) []const u8 {
        return switch (tc) {
            .Authority => "AuthorityTitle",
            .Term => "TermTitle",
            .Class => "ClassTitle",
            .Context => "ContextTitle",
            .None => "",
        };
    }
};

// pub const Entry = struct {
//     typ: NodeType,
//     depth: u8,
//     node: xml.xmlNodePtr,
//     label: ?[:0]const u8,
// };

// fn makeLabel(ally: Allocator, curr: xml.xmlNodePtr, tc: NodeType) ?[:0]const u8 {
//     const itemno = xml.xmlGetProp(curr, "itemno");
//     const title = node.childN(curr, tc.title(), 0);
//     if (itemno == null and title == null) return null;
//     if (itemno == null) return node.xmlStrDup(
//         ally,
//     ) catch null;
//     if (title == null) return node.xmlStrDup(ally, itemno) catch null;
//     return node.xmlStrJoin(ally, &.{ itemno, xml.xmlNodeGetContent(title.?) }, " ") catch null;
// }

fn countContext(current_node: xml.xmlNodePtr) u8 {
    var count: u8 = 0;
    var curr = current_node.*.children;
    while (curr != null) : (curr = curr.*.next) {
        const tc = NodeType.fromStr(curr.*.name);
        if (tc == .Context) count = count + 1;
    }
    return count;
}

fn countChildren(current_node: xml.xmlNodePtr) u8 {
    var count: u8 = 0;
    var curr = current_node.*.children;
    while (curr != null) : (curr = curr.*.next) {
        const tc = NodeType.fromStr(curr.*.name);
        if (tc == .Term or tc == .Class) count = count + 1;
    }
    return count;
}

fn add(list: *std.ArrayList(u8), ally: Allocator, current_node: xml.xmlNodePtr) !void {
    var curr: xml.xmlNodePtr = current_node;
    while (curr != null) : (curr = curr.*.next) {
        switch (NodeType.fromStr(curr.*.name)) {
            .Authority => {
                try list.append(ally, countContext(curr));
                try list.append(ally, countChildren(curr));
                try add(list, ally, curr.*.children);
            },
            .Context => {
                const title = node.childN(curr, NodeType.Context.title(), 0);
                if (title == null) {
                    try list.append(ally, 0);
                } else {
                    const chars = xml.xmlNodeGetContent(title.?);
                    const len: u8 = @truncate(std.mem.len(chars));
                    try list.append(ally, len);
                    if (len > 0) try list.appendSlice(ally, std.mem.span(chars));
                }
            },
            else => {},
        }
    }
}

pub fn refresh(list: *std.ArrayList(u8), ally: Allocator, doc: xml.xmlDocPtr) !void {
    list.clearRetainingCapacity();
    const root: xml.xmlNodePtr = xml.xmlDocGetRootElement(doc);
    try add(list, ally, root);
}
