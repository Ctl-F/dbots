const std = @import("std");
const assets = @import("assets.zig");

pub const StringWalker = struct {
    const This = @This();

    data: []const u8,
    view: []const u8,
    nextpos: usize,

    pub fn init(str: []const u8) This {
        return StringWalker{ .data = str, .view = str[0..0], .nextpos = 0 };
    }

    fn walk(this: *This, comptime predicate: *const fn (char: u8) bool) bool {
        if (this.ended()) return false;

        const start = this.nextpos;
        while (this.nextpos < this.data.len) : (this.nextpos += 1) {
            const char = this.data[this.nextpos];
            if (predicate(char)) {
                break;
            }
        }

        this.view = this.data[start..this.nextpos];
        return this.view.len > 0;
    }

    fn predicate_linebreak(char: u8) bool {
        return char == '\n';
    }
    fn predicate_whitespace(char: u8) bool {
        return char > ' ';
    }
    fn predicate_not_whitespace(char: u8) bool {
        return !predicate_whitespace(char);
    }
    fn predicate_number(char: u8) bool {
        return !('0' <= char and char <= '9');
    }

    pub fn walk_lines(this: *This) bool {
        return this.walk(&predicate_linebreak);
    }

    pub fn walk_whitespace(this: *This) bool {
        return this.walk(&predicate_whitespace);
    }

    pub fn walk_non_whitespace(this: *This) bool {
        return this.walk(&predicate_not_whitespace);
    }

    pub fn walk_integer(this: *This) bool {
        return this.walk(&predicate_number);
    }

    pub inline fn ended(this: *This) bool {
        return this.nextpos >= this.data.len;
    }

    pub fn consume(this: *This, literal: []const u8) void {
        if (this.ended() or !std.mem.startsWith(u8, this.data[this.nextpos..], literal)) return;
        this.nextpos += literal.len;
    }

    pub inline fn expect(this: *This, blob: []const u8) bool {
        return !this.ended() and std.mem.startsWith(u8, this.data[this.nextpos..], blob);
    }

    pub fn walk_number(this: *This) bool {
        if (this.ended()) {
            return false;
        }
        const start = this.nextpos;

        const has_neg = this.expect("-");

        if (has_neg) {
            this.nextpos += 1;
        }

        var found_number = this.walk(&predicate_number);

        const has_decimal = this.expect(".");
        if (has_decimal) {
            this.nextpos += 1;
        }

        found_number = this.walk(&predicate_number) or found_number;

        if (!found_number) {
            this.nextpos = start;
            return false;
        }

        this.view = this.data[start..this.nextpos];
        return true;
    }
};
