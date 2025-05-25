const std = @import("std");
const testing = std.testing;
const rda = @import("rda.zig");
const xml = @import("xml");

const max_file = 100 * 1_048_576; //100MB

const srnsw_schema = @embedFile("rda_schema");
export const schema_sz: u16 = @sizeOf(Schema);
const Schema = extern struct {
    schema: xml.xmlSchemaPtr,
};

fn asSchema(ptr: *anyopaque) *Schema {
    const sptr: *Schema = @ptrCast(@alignCast(ptr));
    return sptr;
}

export fn schema_init(ptr: *anyopaque) void {
    const schema_ctx: xml.xmlSchemaParserCtxtPtr = xml.xmlSchemaNewMemParserCtxt(srnsw_schema, srnsw_schema.len);
    defer xml.xmlSchemaFreeParserCtxt(schema_ctx);
    asSchema(ptr).schema = xml.xmlSchemaParse(schema_ctx);
}

export fn validate(sptr: *anyopaque, dptr: *anyopaque) u8 {
    const schema_valid: xml.xmlSchemaValidCtxtPtr = xml.xmlSchemaNewValidCtxt(asSchema(sptr).schema);
    defer xml.xmlSchemaFreeValidCtxt(schema_valid);
    const v: i32 = xml.xmlSchemaValidateDoc(schema_valid, asDoc(dptr).doc);
    if (v == 0) return 0;
    return 1;
}

export const doc_sz: u16 = @sizeOf(Doc);
const Doc = extern struct {
    doc: xml.xmlDocPtr,
};

fn asDoc(ptr: *anyopaque) *Doc {
    const dptr: *Doc = @ptrCast(@alignCast(ptr));
    return dptr;
}

export fn doc_load(ptr: *anyopaque, path: [*c]const u8) u8 {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    const b = std.fs.cwd().readFileAlloc(allocator, std.mem.span(path), max_file) catch return 1;
    defer allocator.free(b);
    const d = xml.xmlReadMemory(b.ptr, @intCast(b.len), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
    asDoc(ptr).doc = d;
    return 0;
}

const Session = extern struct {
    rda: ?*anyopaque = null,
};

fn asRDA(ptr: ?*anyopaque) *rda.RDASession {
    const rptr: *rda.RDASession = @ptrCast(@alignCast(ptr.?));
    return rptr;
}

export fn rda_init(ptr: *Session) u8 {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    ptr.rda = rda.RDASession.init(allocator) catch return 1;
    return 0;
}

export fn parrot(str: [*c]const u8) [*:0]const u8 {
    const s = std.mem.span(str);
    return s;
}

export fn load_doc(ptr: *Session, path: [*c]const u8) u8 {
    // var file = std.fs.cwd().createFile("authority.txt", .{}) catch unreachable;
    //   defer file.close();
    //  file.writeAll(std.mem.span(path)) catch return 99;

    const ret = asRDA(ptr.rda).load(std.mem.span(path)) catch return 255;
    return @intCast(ret);
}

export fn menu_sz(ptr: *Session, doc: u8) u8 {
    const d = asRDA(ptr.rda).get(doc);
    return @intCast(d.entries.items.len);
}

pub const RDA = rda.RDADoc;
test {
    std.testing.refAllDecls(@This());
}

test "menu_sz" {
    var sess: Session = .{};
    try testing.expect(rda_init(&sess) == 0);
    _ = load_doc(&sess, "data/SRNSW_example.xml");
    try testing.expect(menu_sz(&sess, 0) == 7);
    asRDA(sess.rda).get(0).print();
}

test "validate" {
    var dbuf: [doc_sz]u8 = undefined;
    const dptr: *anyopaque = @ptrCast(&dbuf);
    var sbuf: [schema_sz]u8 = undefined;
    const sptr: *anyopaque = @ptrCast(&sbuf);
    _ = doc_load(dptr, "data/SRNSW_example.xml");
    schema_init(sptr);
    try testing.expect(validate(dptr, sptr) == 0);
}
