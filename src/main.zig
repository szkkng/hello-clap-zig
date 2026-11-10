const std = @import("std");
const clap = @import("clap_zig");
const allocator = std.heap.page_allocator;
const gain_param_id = 0;
const gain_param_suffix = " dB";

const GainPlugin = struct {
    plugin: clap.Plugin,
    host: *const clap.Host,
    gain_db: std.atomic.Value(f32) = .init(0.0),
};

export const clap_entry: clap.PluginEntry = .{
    .init = struct {
        fn f(plugin_path: [*:0]const u8) callconv(.c) bool {
            _ = plugin_path;
            return true;
        }
    }.f,

    .deinit = struct {
        fn f() callconv(.c) void {}
    }.f,

    .getFactory = struct {
        fn f(factory_id: [*:0]const u8) callconv(.c) ?*const anyopaque {
            if (std.mem.eql(u8, std.mem.span(factory_id), clap.factory.plugin.id[0..])) {
                return @ptrCast(&plugin_factory);
            }

            return null;
        }
    }.f,
};

const plugin_factory: clap.factory.plugin.Factory = .{
    .getPluginCount = struct {
        fn f(factory: *const clap.factory.plugin.Factory) callconv(.c) u32 {
            _ = factory;
            return 1;
        }
    }.f,

    .getPluginDescriptor = struct {
        fn f(
            factory: *const clap.factory.plugin.Factory,
            index: u32,
        ) callconv(.c) ?*const clap.Plugin.Descriptor {
            _ = factory;
            return if (index == 0) &plugin_descriptor else null;
        }
    }.f,

    .createPlugin = struct {
        fn f(
            factory: *const clap.factory.plugin.Factory,
            host: *const clap.Host,
            plugin_id: [*:0]const u8,
        ) callconv(.c) ?*const clap.Plugin {
            _ = factory;

            if (!host.clap_version.isCompatible()) {
                return null;
            }

            if (!std.mem.eql(
                u8,
                std.mem.span(plugin_id),
                std.mem.span(plugin_descriptor.id),
            )) {
                return null;
            }

            const plug = allocator.create(GainPlugin) catch return null;
            plug.* = .{
                .plugin = gain_plugin,
                .host = host,
            };
            plug.plugin.plugin_data = plug;

            return &plug.plugin;
        }
    }.f,
};

const plugin_descriptor: clap.Plugin.Descriptor = .{
    .id = "dev.kengo.helloclapzig",
    .name = "HelloClapZig",
    .vendor = "kengo",
    .url = "https://kengo.dev",
    .manual_url = "https://kengo.dev",
    .support_url = "https://kengo.dev",
    .version = "1.0.0",
    .description = "Hello, CLAP!",
    .features = &.{
        clap.plugin_feature.audio_effect,
        clap.plugin_feature.stereo,
    },
};

const gain_plugin: clap.Plugin = .{
    .desc = &plugin_descriptor,
    .plugin_data = null,

    .init = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) bool {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.plugin_data));
            _ = plug;
            return true;
        }
    }.f,

    .destroy = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) void {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.plugin_data));
            allocator.destroy(plug);
        }
    }.f,

    .activate = struct {
        fn f(
            plugin: *const clap.Plugin,
            sampleRate: f64,
            minimum_frames_count: u32,
            maximum_frames_count: u32,
        ) callconv(.c) bool {
            _ = plugin;
            _ = sampleRate;
            _ = minimum_frames_count;
            _ = maximum_frames_count;
            return true;
        }
    }.f,

    .deactivate = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) void {
            _ = plugin;
        }
    }.f,

    .startProcessing = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) bool {
            _ = plugin;
            return true;
        }
    }.f,

    .stopProcessing = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) void {
            _ = plugin;
        }
    }.f,

    .reset = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) void {
            _ = plugin;
        }
    }.f,

    .process = struct {
        fn f(
            plugin: *const clap.Plugin,
            process: *const clap.Process,
        ) callconv(.c) clap.Process.Status {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.plugin_data));
            var gain_db = plug.gain_db.load(.monotonic);
            const in_events = process.in_events;
            const num_events = in_events.size(in_events);
            const num_frames = process.frames_count;
            var event_index: u32 = 0;
            var next_event_frame: u32 = if (num_events > 0) 0 else num_frames;

            var i: usize = 0;
            while (i < num_frames) {
                while (event_index < num_events and next_event_frame == i) {
                    const header = in_events.get(in_events, @intCast(event_index));

                    if (header.time != i) {
                        next_event_frame = header.time;
                        break;
                    }

                    if (header.space_id == clap.event.core.space_id and
                        header.type == @backingInt(clap.event.core.Type.param_value))
                    {
                        const event_param_value: *const clap.event.ParamValue = @ptrCast(@alignCast(header));
                        if (event_param_value.param_id == gain_param_id) {
                            gain_db = @floatCast(event_param_value.value);
                        }
                    }
                    event_index += 1;

                    if (event_index == num_events) {
                        next_event_frame = num_frames;
                        break;
                    }
                }

                const gain_linear = std.math.pow(f32, 10.0, gain_db * 0.05);

                while (i < next_event_frame) : (i += 1) {
                    const in_l = process.audio_inputs.?[0].data32.?[0][i];
                    const in_r = process.audio_inputs.?[0].data32.?[1][i];

                    const out_l = in_l * gain_linear;
                    const out_r = in_r * gain_linear;

                    process.audio_outputs.?[0].data32.?[0][i] = out_l;
                    process.audio_outputs.?[0].data32.?[1][i] = out_r;
                }
            }

            plug.gain_db.store(gain_db, .monotonic);

            return .@"continue";
        }
    }.f,

    .getExtension = struct {
        fn f(plugin: *const clap.Plugin, id: [*:0]const u8) callconv(.c) ?*const anyopaque {
            _ = plugin;

            if (std.mem.eql(u8, std.mem.span(id), clap.ext.params.id)) {
                return @ptrCast(&extension_params);
            }

            if (std.mem.eql(u8, std.mem.span(id), clap.ext.audio_ports.id)) {
                return @ptrCast(&extension_audio_ports);
            }

            if (std.mem.eql(u8, std.mem.span(id), clap.ext.state.id)) {
                return @ptrCast(&extension_state);
            }

            return null;
        }
    }.f,

    .onMainThread = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) void {
            _ = plugin;
        }
    }.f,
};

const extension_params: clap.ext.params.Plugin = .{
    .count = struct {
        fn f(plugin: *const clap.Plugin) callconv(.c) u32 {
            _ = plugin;
            return 1;
        }
    }.f,

    .getInfo = struct {
        fn f(
            plugin: *const clap.Plugin,
            param_index: u32,
            param_info: *clap.ext.params.Info,
        ) callconv(.c) bool {
            _ = plugin;

            if (param_index > 0) return false;

            param_info.id = gain_param_id;
            param_info.flags = .{ .is_automatable = true };
            _ = std.fmt.bufPrintSentinel(param_info.name[0..], "{s}", .{"Gain"}, 0) catch unreachable;
            param_info.min_value = -60.0;
            param_info.max_value = 12.0;
            param_info.default_value = 0.0;

            return true;
        }
    }.f,

    .getValue = struct {
        fn f(plugin: *const clap.Plugin, param_id: clap.Id, out_value: *f64) callconv(.c) bool {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.plugin_data));

            if (param_id == gain_param_id) {
                out_value.* = plug.gain_db.load(.monotonic);
                return true;
            }

            return false;
        }
    }.f,

    .valueToText = struct {
        fn f(
            plugin: *const clap.Plugin,
            param_id: clap.Id,
            value: f64,
            out_buffer: [*]u8,
            out_buffer_capacity: u32,
        ) callconv(.c) bool {
            _ = plugin;

            if (param_id == gain_param_id) {
                _ = std.fmt.bufPrintSentinel(
                    out_buffer[0..out_buffer_capacity],
                    "{d:.1}{s}",
                    .{ value, gain_param_suffix },
                    0,
                ) catch return false;

                return true;
            }

            return false;
        }
    }.f,

    .textToValue = struct {
        fn f(
            plugin: *const clap.Plugin,
            param_id: clap.Id,
            param_value_text: [*:0]const u8,
            out_value: *f64,
        ) callconv(.c) bool {
            _ = plugin;

            if (param_id == gain_param_id) {
                var text = std.mem.trim(u8, std.mem.span(param_value_text), " \t\r\n");

                if (std.mem.endsWith(u8, text, gain_param_suffix)) {
                    text = std.mem.trim(u8, text[0 .. text.len - gain_param_suffix.len], " \t\r\n");
                }

                const value = std.fmt.parseFloat(f64, text) catch return false;
                out_value.* = value;
                return true;
            }

            return false;
        }
    }.f,

    .flush = struct {
        fn f(
            plugin: *const clap.Plugin,
            in: *const clap.event.InputEvents,
            out: *const clap.event.OutputEvents,
        ) callconv(.c) void {
            _ = out;
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.plugin_data));

            var i: u32 = 0;
            while (i < in.size(in)) : (i += 1) {
                const event = in.get(in, i);

                if (event.space_id == clap.event.core.space_id and
                    event.type == @backingInt(clap.event.core.Type.param_value))
                {
                    const event_param_value: *const clap.event.ParamValue = @ptrCast(@alignCast(event));

                    if (event_param_value.param_id == gain_param_id) {
                        plug.gain_db.store(@floatCast(event_param_value.value), .monotonic);
                    }
                }
            }
        }
    }.f,
};

const extension_audio_ports: clap.ext.audio_ports.Plugin = .{
    .count = struct {
        fn f(plugin: *const clap.Plugin, is_input: bool) callconv(.c) u32 {
            _ = plugin;
            _ = is_input;
            return 1;
        }
    }.f,

    .get = struct {
        fn f(
            plugin: *const clap.Plugin,
            index: u32,
            is_input: bool,
            info: *clap.ext.audio_ports.Info,
        ) callconv(.c) bool {
            _ = plugin;

            if (index > 0) return false;

            info.id = 0;
            info.channel_count = 2;
            info.flags = .{ .is_main = true };
            info.port_type = clap.ext.audio_ports.port_type.stereo;
            info.in_place_pair = clap.invalid_id;
            _ = std.fmt.bufPrintSentinel(
                info.name[0..],
                "{s}",
                .{if (is_input) "Audio Input" else "Audio Output"},
                0,
            ) catch unreachable;

            return true;
        }
    }.f,
};

const extension_state: clap.ext.state.Plugin = .{
    .save = struct {
        fn f(plugin: *const clap.Plugin, stream: *const clap.OStream) callconv(.c) bool {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.plugin_data));
            var gain_db = plug.gain_db.load(.monotonic);
            const data = std.mem.asBytes(&gain_db);

            var offset: usize = 0;
            while (offset < data.len) {
                const bytes_written = stream.write(
                    stream,
                    data.ptr + offset,
                    data.len - offset,
                );
                if (bytes_written <= 0) return false;
                offset += @intCast(bytes_written);
            }

            return true;
        }
    }.f,

    .load = struct {
        fn f(plugin: *const clap.Plugin, stream: *const clap.IStream) callconv(.c) bool {
            var gain_db: f32 = undefined;
            const data = std.mem.asBytes(&gain_db);

            var offset: usize = 0;
            while (offset < data.len) {
                const bytes_read = stream.read(
                    stream,
                    data.ptr + offset,
                    data.len - offset,
                );
                if (bytes_read <= 0) return false;
                offset += @intCast(bytes_read);
            }

            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.plugin_data));
            plug.gain_db.store(gain_db, .monotonic);
            return true;
        }
    }.f,
};
