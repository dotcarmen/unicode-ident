// pub extern fn is_xid_start(ch: u21) bool;
// pub extern fn is_xid_continue(ch: u21) bool;

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const unicode = std.unicode;

pub const ffi = struct {
    pub const isXIDContinue = @extern(
        *const fn (ch: u32) callconv(.c) bool,
        .{
            .name = "is_xid_continue",
            .library_name = "unicode_ident",
        },
    );

    pub const isXIDStart = @extern(
        *const fn (ch: u32) callconv(.c) bool,
        .{
            .name = "is_xid_start",
            .library_name = "unicode_ident",
        },
    );
};

pub fn isXIDContinue(cp: u21) bool {
    return ffi.isXIDContinue(cp);
}

pub fn isXIDStart(cp: u21) bool {
    return ffi.isXIDStart(cp);
}

fn codepoint(bytes: anytype) u21 {
    return switch (bytes.len) {
        1 => bytes[0],
        2 => unicode.utf8Decode2(bytes.*) catch unreachable,
        3 => unicode.utf8Decode3(bytes.*) catch unreachable,
        4 => unicode.utf8Decode4(bytes.*) catch unreachable,
        else => unreachable,
    };
}

test isXIDContinue {
    inline for (.{
        "a",  "b",  "c",  "A",  "B",  "C",
        "ä", "ö", "ü", "Ä", "Ö", "Ü",
        "ø", "î", "é", "ß", "Î", "å",
        "_",  "æ", "ç", "ƒ",
    }) |bytes| {
        const cp = codepoint(bytes);
        testing.expect(isXIDContinue(cp)) catch |err| {
            std.debug.print("expected XID_Continue: {u}\n", .{cp});
            return err;
        };
    }

    inline for (.{
        "∂", "≈", "=",
    }) |bytes| {
        const cp: u21 = codepoint(bytes);
        testing.expect(!isXIDContinue(cp)) catch |err| {
            std.debug.print("unexpected XID_Continue: {u}\n", .{cp});
            return err;
        };
    }
}

test isXIDStart {
    inline for (.{
        "a",  "b",  "c",  "A",  "B",  "C",
        "ä", "ö", "ü", "Ä", "Ö", "Ü",
        "ø", "î", "é", "ß", "Î", "å",
        "æ", "ç", "ƒ",
    }) |bytes| {
        const cp: u21 = codepoint(bytes);
        testing.expect(isXIDStart(cp)) catch |err| {
            std.debug.print("expected XID_Start: {u}\n", .{cp});
            return err;
        };
    }

    inline for (.{
        "_", "∂", "≈", "=",
    }) |bytes| {
        const cp: u21 = codepoint(bytes);
        testing.expect(!isXIDStart(cp)) catch |err| {
            std.debug.print("unexpected XID_Start: {u}\n", .{cp});
            return err;
        };
    }
}
