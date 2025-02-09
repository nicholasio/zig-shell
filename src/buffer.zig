const Buffer = @This();
const std = @import("std");
const expect = std.testing.expect;

const MAX_BUFFER_SIZE = 1024;

buffer: [1024]u8 = undefined,
len: usize = 0,

pub fn init() Buffer {
    return Buffer{
        .len = 0,
    };
}

pub fn reset(self: *Buffer) void {
    self.len = 0;
}

pub fn putChar(self: *Buffer, c: u8, position: usize) void {
    // do not let add to a position bigger than the max buffer
    // do not let the buffer grew bigger than the max buffer
    // do not let put a chat at a position bigger than the current len which would lead to undefined slice
    if (position >= MAX_BUFFER_SIZE or self.len >= MAX_BUFFER_SIZE or position > self.len) {
        return;
    }

    if (position == self.len) {
        self.buffer[position] = c;
    } else {
        // move things to make up space for position
        var i: usize = self.len;
        while (i > position) : (i -= 1) {
            self.buffer[i] = self.buffer[i - 1];
        }
        self.buffer[position] = c;
    }

    self.len += 1;
}

pub fn removeChar(self: *Buffer, position: usize) void {
    if (position >= self.len) {
        return;
    }

    var i: usize = position;
    while (i < self.len) : (i += 1) {
        self.buffer[i] = self.buffer[i + 1];
    }

    self.len -= 1;
}

pub fn getChar(self: *Buffer, position: usize) u8 {
    return self.buffer[position];
}

pub fn getSliceRange(self: *Buffer, start: usize, end: usize) []const u8 {
    return self.buffer[start..end];
}

pub fn getSlice(self: *Buffer) []const u8 {
    return self.getSliceRange(0, self.len);
}

pub fn append(self: *Buffer, c: u8) void {
    self.putChar(c, self.len);
}

pub fn appendSlice(self: *Buffer, slice: []const u8) void {
    @memcpy(self.buffer[self.len .. self.len + slice.len], slice);
    self.len += slice.len;
}

test "appends chars correcttly" {
    var b = Buffer.init();
    b.append('a');
    b.append('b');
    b.append('c');

    try expect(std.mem.eql(u8, b.getSlice(), "abc"));

    b.append('d');
    b.append('e');
    try expect(std.mem.eql(u8, b.getSlice(), "abcde"));
}

test "inserts chars at any position" {
    var b = Buffer.init();
    b.append('a');
    b.append('b');
    b.append('c');

    b.putChar('e', 0);
    try expect(std.mem.eql(u8, b.getSlice(), "eabc"));

    b.putChar('f', 1);
    try expect(std.mem.eql(u8, b.getSlice(), "efabc"));

    b.putChar('z', 4);
    try expect(std.mem.eql(u8, b.getSlice(), "efabzc"));
}

test "it does not let put a char at a position bigger than the current len" {
    var b = Buffer.init();
    b.append('a');
    b.append('b');
    b.append('c');

    // this should be ignored
    b.putChar('e', 4);
    try expect(std.mem.eql(u8, b.getSlice(), "abc"));
}

test "it appends a slice" {
    var b = Buffer.init();
    b.append('a');
    b.append('b');
    b.append('c');

    b.appendSlice("def");
    try expect(std.mem.eql(u8, b.getSlice(), "abcdef"));
    try expect(b.len == 6);

    b.putChar('z', 2);
    try expect(std.mem.eql(u8, b.getSlice(), "abzcdef"));
}

test "it resets the buffer" {
    var b = Buffer.init();
    b.append('a');
    b.append('b');
    b.append('c');

    b.reset();
    try expect(b.len == 0);
    try expect(std.mem.eql(u8, b.getSlice(), ""));
}

test "it removes char" {
    var b = Buffer.init();
    b.append('a');
    b.append('b');
    b.append('c');

    b.removeChar(2);
    try expect(std.mem.eql(u8, b.getSlice(), "ab"));
    try expect(b.len == 2);

    b.removeChar(0);
    try expect(std.mem.eql(u8, b.getSlice(), "b"));
    try expect(b.len == 1);
}
