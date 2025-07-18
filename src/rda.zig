const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const node = @import("node.zig");
const menu = @import("menu.zig");
const xml = @import("xml");

const max_file = 100 * 1_048_576; //100MB
const srnsw_schema = @embedFile("rda_schema");

const srnsw_blank = "<Authority xmlns=\"http://www.records.nsw.gov.au/schemas/RDA\"></Authority>";

pub const RDASession = struct {
    allocator: Allocator,
    schema: xml.xmlSchemaPtr,
    docs: std.ArrayList(*RDADoc),

    pub fn init(allocator: Allocator) !*RDASession {
        const schema_ctx: xml.xmlSchemaParserCtxtPtr = xml.xmlSchemaNewMemParserCtxt(srnsw_schema, srnsw_schema.len);
        defer xml.xmlSchemaFreeParserCtxt(schema_ctx);
        const ptr = try allocator.create(RDASession);
        ptr.* = .{
            .allocator = allocator,
            .schema = xml.xmlSchemaParse(schema_ctx),
            .docs = std.ArrayList(*RDADoc).init(allocator),
        };
        return ptr;
    }

    pub fn load(self: *RDASession, path: []const u8) !usize {
        const doc = try RDADoc.load(self, path);
        try self.docs.append(doc);
        return self.docs.items.len - 1;
    }

    pub fn get(self: *RDASession, index: usize) *RDADoc {
        return self.docs.items[index];
    }

    pub fn deinit(self: *RDASession) void {
        xml.xmlSchemaFree(self.schema);
        self.docs.deinit();
        self.allocator.destroy(self);
        xml.xmlCleanupParser();
    }
};

pub const RDADoc = struct {
    session: *RDASession,
    doc: xml.xmlDocPtr,
    entries: std.ArrayList(menu.Entry),
    current: usize, // index into the entries array

    pub fn load(session: *RDASession, path: []const u8) !*RDADoc {
        const b = try std.fs.cwd().readFileAlloc(session.allocator, path, max_file);
        defer session.allocator.free(b);
        const d = xml.xmlReadMemory(b.ptr, @intCast(b.len), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
        const ptr = try session.allocator.create(RDADoc);
        ptr.* = .{
            .session = session,
            .doc = d,
            .entries = std.ArrayList(menu.Entry).init(session.allocator),
            .current = 0,
        };
        try ptr.refresh();
        return ptr;
    }

    pub fn deinit(self: *RDADoc) void {
        xml.xmlFreeDoc(self.doc);
        menu.free(self.session.allocator, &self.entries);
        self.entries.deinit();
        self.session.allocator.destroy(self);
    }

    pub fn refresh(self: *RDADoc) !void {
        try menu.refresh(self.session.allocator, &self.entries, self.doc);
    }

    pub fn print(self: *RDADoc) void {
        for (self.entries.items) |e| {
            if (e.label) |label| {
                std.debug.print("{s} - {s} - {d}\n", .{ e.typ.toStr(), label, e.depth });
            } else {
                std.debug.print("{s} - {d}\n", .{ e.typ.toStr(), e.depth });
            }
        }
    }

    pub fn transform(self: *RDADoc, stylesheet_path: [*c]const u8, output_path: [*c]const u8) bool {
        xml.exsltCommonRegister();
        const stylesheet: xml.xsltStylesheetPtr = xml.xsltParseStylesheetFile(stylesheet_path);
        defer xml.xsltFreeStylesheet(stylesheet);
        const result: xml.xmlDocPtr = xml.xsltApplyStylesheet(stylesheet, self.doc, null);
        defer xml.xmlFreeDoc(result);
        _ = xml.xsltSaveResultToFilename(output_path, result, stylesheet, 0);
        return true;
    }

    pub fn valid(self: *RDADoc) bool {
        const schema_valid: xml.xmlSchemaValidCtxtPtr = xml.xmlSchemaNewValidCtxt(self.session.schema.?);
        defer xml.xmlSchemaFreeValidCtxt(schema_valid);
        const v: i32 = xml.xmlSchemaValidateDoc(schema_valid, self.doc);
        return v == 0;
    }
};

const example = "data/SRNSW_example.xml";

test "validate" {
    const session = try RDASession.init(testing.allocator);
    defer session.deinit();
    const idx = try session.load(example);
    const rda_doc = session.get(idx);
    defer rda_doc.deinit();
    try testing.expect(rda_doc.valid());
}

test "menu" {
    const session = try RDASession.init(testing.allocator);
    defer session.deinit();
    const rda_doc = try RDADoc.load(session, example);
    defer rda_doc.deinit();
    try testing.expect(rda_doc.entries.items.len == 7);
    // rda_doc.print();
}

test "transform" {
    const session = try RDASession.init(testing.allocator);
    defer session.deinit();
    const rda_doc = try RDADoc.load(session, example);
    defer rda_doc.deinit();
    try testing.expect(rda_doc.transform("data/stylesheets/preview_index.xsl", "test.html"));
}
