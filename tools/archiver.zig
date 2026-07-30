const std = @import("std");
const fatal = std.process.fatal;
const Io = std.Io;
const Build = std.Build;
const mem = std.mem;
const Allocator = mem.Allocator;

// We must take in the following:
// * The path to the executable file; the input
// * The desired archive path; the output
pub fn main(init: std.process.Init) !void {
    const arena_instance = init.arena;
    const arena = arena_instance.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3) {
        fatal("expected '{s} <input> <output>'", .{args[0]});
    }

    const input_path = args[1];
    const output_path = args[2];

    const archive_kind: Kind = if (mem.endsWith(u8, output_path, ".tar.gz"))
        .tarball
    else if (mem.endsWith(u8, output_path, ".zip"))
        .zip
    else
        fatal("unrecognized extension", .{});

    const cwd: Io.Dir = .cwd();

    if (Io.Dir.path.dirname(output_path)) |dir| {
        try cwd.createDirPath(io, dir);
    }

    var input_file = try cwd.openFile(io, input_path, .{});
    defer input_file.close(io);

    var output_file = try cwd.createFileAtomic(io, output_path, .{
        .make_path = true,
        .replace = true,
    });
    defer output_file.deinit(io);

    var fw_buf: [4096]u8 = undefined;
    var fw = output_file.file.writer(io, &fw_buf);

    var fr_buf: [4096]u8 = undefined;
    var fr = input_file.reader(io, &fr_buf);

    const original_name = Io.Dir.path.basename(input_path);

    switch (archive_kind) {
        .tarball => try archiveTar(&fr, &fw, original_name),
        .zip => try archiveZip(arena, &fr, &fw, original_name, .now(io, .real)),
    }

    try fw.flush();
    try output_file.replace(io);
}

const Kind = enum {
    tarball,
    zip,
};

const dos = struct {
    /// January 1, 2108, 00:00:00, in seconds since the Unix epoch.
    pub const limit = 4354819200;

    pub const DateAndTime = struct {
        time: Time,
        date: Date,

        /// January 1, 1980, 00:00:00
        pub const zero: DateAndTime = .{ .time = .zero, .date = .zero };

        /// Returns *either* a DOS timestamp and date *or* null, given an Io.Timestamp.
        /// If the timestamp takes place before the DOS epoch, returns null.
        pub fn fromTimestamp(timestamp: Io.Timestamp) ?DateAndTime {
            return fromSeconds(timestamp.toSeconds());
        }

        /// Returns *either* a DOS timestamp and date *or* null, given the amount of seconds since the Unix epoch.
        /// If the timestamp takes place before the DOS epoch, returns null.
        pub fn fromSeconds(seconds: i64) ?DateAndTime {
            const time = Time.fromSeconds(seconds) orelse return null;
            const date = Date.fromSeconds(seconds) orelse return null;

            return .{
                .time = time,
                .date = date,
            };
        }

        test fromSeconds {
            try std.testing.expectEqual(null, fromSeconds(0));
            try std.testing.expectEqual(null, fromSeconds(std.time.epoch.dos - 1));
            try std.testing.expectEqual(zero, fromSeconds(std.time.epoch.dos));
            try std.testing.expectEqual(null, fromSeconds(limit)); // January 1, 2108, 00:00:00
            try std.testing.expect(fromSeconds(limit - 1) != null);
        }
    };

    pub const Time = packed struct(u16) {
        /// 0-29, raw seconds / 2
        double_seconds: u5,
        /// 0-59
        minutes: u6,
        /// 0-23
        hours: u5,

        /// 00:00:00
        pub const zero: Time = .{ .double_seconds = 0, .minutes = 0, .hours = 0 };

        /// Returns a DOS timestamp or null, given an Io.Timestamp.
        /// If the timestamp takes place before the DOS epoch, returns null.
        pub fn fromTimestamp(timestamp: Io.Timestamp) ?Time {
            return fromSeconds(timestamp.toSeconds());
        }

        /// Returns a DOS timestamp or null, given the amount of seconds since the Unix epoch.
        /// If the timestamp takes place before the DOS epoch, returns null.
        pub fn fromSeconds(seconds: i64) ?Time {
            if (seconds < std.time.epoch.dos or seconds >= limit) {
                return null;
            }

            const total_seconds: u17 = @intCast(@mod(seconds, 86400));
            const day_s: std.time.epoch.DaySeconds = .{ .secs = total_seconds };

            const double_seconds: u5 = @intCast(@divTrunc(day_s.getSecondsIntoMinute(), 2));
            const minutes = day_s.getMinutesIntoHour();
            const hours = day_s.getHoursIntoDay();

            return .{
                .double_seconds = double_seconds,
                .minutes = minutes,
                .hours = hours,
            };
        }

        test fromSeconds {
            try std.testing.expectEqual(null, fromSeconds(0));
            try std.testing.expectEqual(null, fromSeconds(std.time.epoch.dos - 1));
            try std.testing.expectEqual(zero, fromSeconds(std.time.epoch.dos));
            try std.testing.expectEqual(null, fromSeconds(limit)); // January 1, 2108, 00:00:00
            try std.testing.expect(fromSeconds(limit - 1) != null);
        }
    };

    pub const Date = packed struct(u16) {
        /// 1-31
        day: u5,
        /// 1-12
        month: u4,
        /// Offset from 1980, 1980-2107
        year_offset: u7,

        /// January 1, 1980
        pub const zero: Date = .{ .day = 1, .month = 1, .year_offset = 0 };

        /// Returns a DOS date or null, given an Io.Timestamp.
        /// If the timestamp takes place before the DOS epoch, returns null.
        pub fn fromTimestamp(timestamp: Io.Timestamp) ?Date {
            return fromSeconds(timestamp.toSeconds());
        }

        /// Returns a DOS date or null, given the amount of seconds since the Unix epoch.
        /// If the timestamp takes place before the DOS epoch, returns null.
        pub fn fromSeconds(seconds: i64) ?Date {
            if (seconds < std.time.epoch.dos or seconds >= limit) {
                return null;
            }

            const epoch_s: std.time.epoch.EpochSeconds = .{ .secs = @intCast(seconds) };

            const epoch_day = epoch_s.getEpochDay();
            const year_and_day = epoch_day.calculateYearDay();
            const month_and_day = year_and_day.calculateMonthDay();

            const year_offset: u7 = @intCast(year_and_day.year - 1980);
            const month = month_and_day.month.numeric();
            const day = month_and_day.day_index + 1;

            return .{
                .day = day,
                .month = month,
                .year_offset = year_offset,
            };
        }

        test fromSeconds {
            try std.testing.expectEqual(null, fromSeconds(0));
            try std.testing.expectEqual(null, fromSeconds(std.time.epoch.dos - 1));
            try std.testing.expectEqual(zero, fromSeconds(std.time.epoch.dos));
            try std.testing.expectEqual(null, fromSeconds(limit)); // January 1, 2108, 00:00:00
            try std.testing.expect(fromSeconds(limit - 1) != null);
        }
    };
};

comptime {
    // Run tests
    _ = dos.DateAndTime;
    _ = dos.Time;
    _ = dos.Date;
}

pub const ArchiveTarError = Io.File.Writer.Error || Io.File.Reader.Error || std.tar.Writer.WriteFileError;

pub fn archiveTar(
    in: *Io.File.Reader,
    out: *Io.File.Writer,
    original_name: []const u8,
) ArchiveTarError!void {
    var compressor_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var compressor = std.compress.flate.Compress.init(
        &out.interface,
        &compressor_buf,
        .gzip,
        .level_9,
    ) catch |err| switch (err) {
        error.WriteFailed => return out.err.?,
    };

    var archiver: std.tar.Writer = .{ .underlying_writer = &compressor.writer };
    archiver.writeFile(original_name, in, 0) catch |err| switch (err) {
        error.WriteFailed => return out.err.?,
        error.ReadFailed => return in.err.?,
        else => |e| return e,
    };

    compressor.finish() catch |err| switch (err) {
        error.WriteFailed => return out.err.?,
    };
}

pub const ArchiveZipError = Allocator.Error || Io.Writer.Error || Io.File.Writer.Error || Io.File.Reader.Error;

pub fn archiveZip(
    allocator: Allocator,
    in: *Io.File.Reader,
    out: *Io.File.Writer,
    original_name: []const u8,
    timestamp: Io.Timestamp,
) ArchiveZipError!void {
    return archiveZipInner(allocator, &in.interface, &out.interface, original_name, timestamp) catch |err| switch (err) {
        error.WriteFailed => |e| return out.err orelse e,
        error.ReadFailed => return in.err.?,
        else => |e| return e,
    };
}

pub fn archiveZipInner(
    allocator: Allocator,
    in: *Io.Reader,
    out: *Io.Writer,
    original_name: []const u8,
    timestamp: Io.Timestamp,
) !void {
    const date_time: dos.DateAndTime = dos.DateAndTime.fromTimestamp(timestamp) orelse .zero;

    const last_mod_time = date_time.time;
    const last_mod_date = date_time.date;

    var compressed_bytes: Io.Writer.Allocating = try .initCapacity(allocator, 16);
    defer compressed_bytes.deinit();

    var uncompressed_size: u32 = 0;
    var crc: std.hash.Crc32 = .init();

    var compressor_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(
        &compressed_bytes.writer,
        &compressor_buf,
        .raw,
        .level_9,
    );

    var read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try in.readSliceShort(&read_buf);
        if (bytes_read == 0) break;

        const slice = read_buf[0..bytes_read];
        uncompressed_size += @intCast(bytes_read);
        crc.update(slice);
        try compressor.writer.writeAll(slice);
    }
    try compressor.finish();

    const compressed_size: u32 = @intCast(compressed_bytes.written().len);
    const crc_final = crc.final();

    const local_header: std.zip.LocalFileHeader = .{
        .signature = std.zip.local_file_header_sig,
        .version_needed_to_extract = 20,
        .flags = .{ .encrypted = false, ._ = 0 },
        .compression_method = .deflate,
        .last_modification_time = @backingInt(last_mod_time),
        .last_modification_date = @backingInt(last_mod_date),
        .crc32 = crc_final,
        .compressed_size = compressed_size,
        .uncompressed_size = uncompressed_size,
        .filename_len = @intCast(original_name.len),
        .extra_len = 0,
    };

    try out.writeStruct(local_header, .little);
    try out.writeAll(original_name);
    try out.writeAll(compressed_bytes.written());

    const cd_offset: u32 = @intCast(@sizeOf(std.zip.LocalFileHeader) + original_name.len + compressed_size);

    const cd_header: std.zip.CentralDirectoryFileHeader = .{
        .signature = std.zip.central_file_header_sig,
        .version_made_by = 20,
        .version_needed_to_extract = 20,
        .flags = .{ .encrypted = false, ._ = 0 },
        .compression_method = .deflate,
        .last_modification_time = @backingInt(last_mod_time),
        .last_modification_date = @backingInt(last_mod_date),
        .crc32 = crc_final,
        .compressed_size = compressed_size,
        .uncompressed_size = uncompressed_size,
        .filename_len = @intCast(original_name.len),
        .extra_len = 0,
        .comment_len = 0,
        .disk_number = 0,
        .internal_file_attributes = 0,
        .external_file_attributes = 0,
        .local_file_header_offset = 0,
    };

    try out.writeStruct(cd_header, .little);
    try out.writeAll(original_name);

    const cd_size: u32 = @intCast(@sizeOf(std.zip.CentralDirectoryFileHeader) + original_name.len);

    const eocd: std.zip.EndRecord = .{
        .signature = std.zip.end_record_sig,
        .disk_number = 0,
        .central_directory_disk_number = 0,
        .record_count_disk = 1,
        .record_count_total = 1,
        .central_directory_size = cd_size,
        .central_directory_offset = cd_offset,
        .comment_len = 0,
    };

    try out.writeStruct(eocd, .little);
}
