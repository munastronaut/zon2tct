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
    const Time = packed struct(u16) {
        /// 0-29, raw seconds / 2
        double_seconds: u5,
        /// 0-59
        minutes: u6,
        /// 0-23
        hours: u5,

        /// Returns a DOS timestamp.
        pub fn fromTimestamp(timestamp: Io.Timestamp) Time {
            const raw_s = timestamp.toSeconds();
            const total_seconds: u17 = @intCast(@mod(raw_s, 86400));
            const day_s: std.time.epoch.DaySeconds = .{ .secs = total_seconds };

            const seconds = day_s.getSecondsIntoMinute();
            const minutes = day_s.getMinutesIntoHour();
            const hours = day_s.getHoursIntoDay();

            const double_seconds: u5 = @intCast(@divTrunc(seconds, 2));

            return .{
                .double_seconds = double_seconds,
                .minutes = minutes,
                .hours = hours,
            };
        }
    };

    const Date = packed struct(u16) {
        /// 1-31
        day: u5,
        /// 1-12
        month: u4,
        /// Offset from 1980, 1980-2107
        year_offset: u7,

        /// January 1, 1980
        pub const zero: Date = .{ .day = 1, .month = 1, .year_offset = 0 };

        /// Returns a DOS date or null.
        pub fn fromTimestamp(timestamp: Io.Timestamp) ?Date {
            const raw_s = timestamp.toSeconds();
            if (raw_s < 0) {
                return null;
            }

            const epoch_s: std.time.epoch.EpochSeconds = .{ .secs = @intCast(raw_s) };

            const epoch_day = epoch_s.getEpochDay();
            const year_and_day = epoch_day.calculateYearDay();
            const month_and_day = year_and_day.calculateMonthDay();

            const raw_offset = std.math.sub(u16, year_and_day.year, 1980) catch |err| switch (err) {
                error.Overflow => return null,
            };

            const year_offset = std.math.cast(u7, raw_offset) orelse return null;
            const month = month_and_day.month.numeric();
            const day = month_and_day.day_index + 1;

            return .{
                .day = day,
                .month = month,
                .year_offset = year_offset,
            };
        }

        test fromTimestamp {
            try std.testing.expectEqual(null, fromTimestamp(.{ .nanoseconds = 0 }));
        }
    };
};

comptime {
    // Run tests
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
        error.ReadFailed => return in.err.?,
        error.WriteFailed => return out.err.?,
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
    return archiveZipInner(allocator, in, out, original_name, timestamp) catch |err| switch (err) {
        error.WriteFailed => return out.err orelse err,
        else => |e| return e,
    };
}

pub fn archiveZipInner(
    allocator: Allocator,
    in: *Io.File.Reader,
    out: *Io.File.Writer,
    original_name: []const u8,
    timestamp: Io.Timestamp,
) !void {
    const last_mod_time: dos.Time = .fromTimestamp(timestamp);
    const last_mod_date: dos.Date = dos.Date.fromTimestamp(timestamp) orelse .zero;

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
        const bytes_read = in.interface.readSliceShort(&read_buf) catch |err| switch (err) {
            error.ReadFailed => return in.err.?,
        };
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

    try out.interface.writeStruct(local_header, .little);
    try out.interface.writeAll(original_name);
    try out.interface.writeAll(compressed_bytes.written());

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

    try out.interface.writeStruct(cd_header, .little);
    try out.interface.writeAll(original_name);

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

    try out.interface.writeStruct(eocd, .little);
}
