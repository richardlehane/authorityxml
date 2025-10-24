const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const node = @import("node.zig");
const tree = @import("tree.zig");
const xml = @import("xml");
const miniz = @import("miniz");
const Session = @import("Session.zig");

const Document = @This();
const max_file = 100 * 1_048_576; //100MB

const srnsw_blank =
    \\<Authority xmlns="http://www.records.nsw.gov.au/schemas/RDA">
    \\  <Term itemno="1.0.0" type="function">
    \\    <Term itemno="1.1.0" type="activity">
    \\      <Class itemno="1.1.1">
    \\        <Disposal />
    \\      </Class>
    \\    </Term>
    \\  </Term>
    \\</Authority> 
;

// Document fields
session: *Session,
doc: xml.xmlDocPtr,
tree_menu: std.ArrayList(u8),
current: xml.xmlNodePtr,

fn loadMem(session: *Session, bytes: []const u8, len: usize) !*Document {
    const d = xml.xmlReadMemory(bytes.ptr, @intCast(len), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
    const ptr = try session.allocator.create(Document);
    ptr.* = .{
        .session = session,
        .doc = d,
        .tree_menu = .empty,
        .current = 0,
    };
    return ptr;
}

pub fn empty(
    session: *Session,
) !*Document {
    return loadMem(session, srnsw_blank, srnsw_blank.len);
}

pub fn load(session: *Session, path: []const u8) !*Document {
    const b = try std.fs.cwd().readFileAlloc(session.allocator, path, max_file);
    defer session.allocator.free(b);
    return loadMem(session, b, b.len);
}

pub fn deinit(self: *Document) void {
    xml.xmlFreeDoc(self.doc);
    self.tree_menu.deinit(self.session.allocator);
    self.session.allocator.destroy(self);
}

pub fn refreshTree(self: *Document) !void {
    try tree.refresh(&self.tree_menu, self.session.allocator, self.doc);
}

pub fn toStr(self: *Document) [*c]u8 {
    var char: [*c]xml.xmlChar = undefined;
    var len: c_int = 0;
    xml.xmlDocDumpMemory(self.doc, &char, &len);
    return char;
}

pub fn freeStr(ptr: [*c]u8) void {
    const freefn = xml.xmlFree orelse unreachable;
    freefn(ptr);
}

pub fn transform(self: *Document, stylesheet_path: [*c]const u8, output_path: [*c]const u8) bool {
    xml.exsltCommonRegister();
    const stylesheet: xml.xsltStylesheetPtr = xml.xsltParseStylesheetFile(stylesheet_path);
    defer xml.xsltFreeStylesheet(stylesheet);
    const result: xml.xmlDocPtr = xml.xsltApplyStylesheet(stylesheet, self.doc, null);
    defer xml.xmlFreeDoc(result);
    _ = xml.xsltSaveResultToFilename(output_path, result, stylesheet, 0);
    return true;
}

pub fn valid(self: *Document) bool {
    const schema_valid: xml.xmlSchemaValidCtxtPtr = xml.xmlSchemaNewValidCtxt(self.session.schema.?);
    defer xml.xmlSchemaFreeValidCtxt(schema_valid);
    const v: i32 = xml.xmlSchemaValidateDoc(schema_valid, self.doc);
    return v == 0;
}

const example = "data/SRNSW_example.xml";

test "validate" {
    const session = try Session.init(testing.allocator);
    defer session.deinit();
    const idx = try session.load(example);
    const doc = session.get(idx);
    defer doc.deinit();
    try testing.expect(doc.valid());
}

test "empty" {
    const session = try Session.init(testing.allocator);
    defer session.deinit();
    const doc = try Document.empty(session);
    defer doc.deinit();
    try doc.refreshTree();
    try testing.expectEqual(doc.tree_menu.items.len, 28);
}

test "toStr" {
    const session = try Session.init(testing.allocator);
    defer session.deinit();
    const doc = try Document.empty(session);
    defer doc.deinit();
    const str = doc.toStr();
    try testing.expectEqual(std.mem.sliceTo(str, 49).len, 15);
    freeStr(str);
}

test "tree" {
    const session = try Session.init(testing.allocator);
    defer session.deinit();
    const doc = try Document.load(session, example);
    defer doc.deinit();
    try doc.refreshTree();
    try testing.expectEqual(doc.tree_menu.items.len, 293);
}

test "transform" {
    const session = try Session.init(testing.allocator);
    defer session.deinit();
    const rda_doc = try Document.load(session, example);
    defer rda_doc.deinit();
    try testing.expect(rda_doc.transform("data/stylesheets/preview_index.xsl", "test.html"));
    try std.fs.cwd().deleteFile("test.html");
}
