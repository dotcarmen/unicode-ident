const native = @import("c-api");
const testing = @import("std").testing;

pub const ascii = struct {
    pub fn is_xid_continue(c: u8) bool {
        return native.is_xid_continue(@intCast(c));
    }

    pub fn is_xid_start(c: u8) bool {
        return native.is_xid_start(@intCast(c));
    }
};

pub const utf8 = struct {
    pub fn is_xid_continue(c: u21) bool {
        return native.is_xid_continue(@intCast(c));
    }

    pub fn is_xid_start(c: u21) bool {
        return native.is_xid_start(@intCast(c));
    }
};

test ascii {
    try testing.expect(ascii.is_xid_continue('a'));
    try testing.expect(ascii.is_xid_start('a'));

    try testing.expect(!ascii.is_xid_start('_'));
    try testing.expect(!ascii.is_xid_start('0'));
    try testing.expect(!ascii.is_xid_start(' '));
}

test utf8 {
    try testing.expect(utf8.is_xid_continue('a'));
    try testing.expect(utf8.is_xid_start('a'));

    try testing.expect(!utf8.is_xid_start('_'));
    try testing.expect(!utf8.is_xid_start('0'));
    try testing.expect(!utf8.is_xid_start(' '));

    try testing.expect(!utf8.is_xid_continue('😂'));
    try testing.expect(utf8.is_xid_continue('ñ'));
}
