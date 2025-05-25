const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const node = @import("node.zig");
const xml = @import("xml");

pub const TermClass = enum(c_int) {
    Authority,
    Term,
    Class,
    Neither,

    fn fromStr(a: [*]const xml.xmlChar) TermClass {
        if (node.equals(a, "Authority")) return .Authority;
        if (node.equals(a, "Term")) return .Term;
        if (node.equals(a, "Class")) return .Class;
        return .Neither;
    }

    pub fn toStr(tc: TermClass) []const u8 {
        return switch (tc) {
            .Authority => "Authority",
            .Term => "Term",
            .Class => "Class",
            .Neither => "Neither",
        };
    }

    fn title(tc: TermClass) []const u8 {
        return switch (tc) {
            .Authority => "AuthorityTitle",
            .Term => "TermTitle",
            .Class => "ClassTitle",
            .Neither => "",
        };
    }
};

pub const Entry = struct {
    typ: TermClass,
    depth: u8,
    node: xml.xmlNodePtr,
    label: ?[:0]const u8,
};

fn makeLabel(ally: Allocator, curr: xml.xmlNodePtr, tc: TermClass) ?[:0]const u8 {
    const itemno = xml.xmlGetProp(curr, "itemno");
    const title = node.childN(curr, tc.title(), 0);
    if (itemno == null and title == null) return null;
    if (itemno == null) return node.xmlStrDup(ally, xml.xmlNodeGetContent(title.?)) catch null;
    if (title == null) return node.xmlStrDup(ally, itemno) catch null;
    return node.xmlStrJoin(ally, &.{ itemno, xml.xmlNodeGetContent(title.?) }, " ") catch null;
}

fn add(ally: Allocator, list: *std.ArrayList(Entry), curr: xml.xmlNodePtr, depth: u8) !void {
    var current_node: xml.xmlNodePtr = curr;
    while (current_node != null) : (current_node = current_node.*.next) {
        const tc = TermClass.fromStr(current_node.*.name);
        if (current_node.*.type == xml.XML_ELEMENT_NODE and tc != .Neither) {
            const label = makeLabel(ally, current_node, tc);
            try list.append(.{
                .typ = tc,
                .depth = depth,
                .node = current_node,
                .label = label,
            });
        }
        if (tc == .Authority or tc == .Term) try add(ally, list, current_node.*.children, depth + 1);
    }
}

pub fn refresh(ally: Allocator, list: *std.ArrayList(Entry), doc: xml.xmlDocPtr) !void {
    free(ally, list);
    const root: xml.xmlNodePtr = xml.xmlDocGetRootElement(doc);
    try add(ally, list, root, 0);
}

pub fn free(ally: Allocator, list: *std.ArrayList(Entry)) void {
    for (list.items) |e| {
        if (e.label) |l| ally.free(l);
    }
    list.resize(0) catch unreachable;
}
