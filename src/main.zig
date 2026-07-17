const std = @import("std");
const clap = @import("clap");
const allocator = std.heap.page_allocator;
const gain_param_id = 0;
const gain_param_suffix = " dB";

const GainPlugin = struct {
    plugin: clap.clap_plugin,
    host: *const clap.clap_host,
    gain_db: std.atomic.Value(f32) = .init(0.0),
};

export const clap_entry: clap.clap_plugin_entry = .{
    .clap_version = clap.CLAP_VERSION,

    .init = struct {
        fn init(plugin_path: [*c]const u8) callconv(.c) bool {
            _ = plugin_path;
            return true;
        }
    }.init,

    .deinit = struct {
        fn deinit() callconv(.c) void {}
    }.deinit,

    .get_factory = struct {
        fn getFactory(factory_id: [*c]const u8) callconv(.c) ?*const anyopaque {
            if (std.mem.eql(u8, std.mem.span(factory_id), clap.CLAP_PLUGIN_FACTORY_ID[0..])) {
                return @ptrCast(&plugin_factory);
            }

            return null;
        }
    }.getFactory,
};

const plugin_factory: clap.clap_plugin_factory = .{
    .get_plugin_count = struct {
        fn getPluginCount(factory: [*c]const clap.clap_plugin_factory) callconv(.c) u32 {
            _ = factory;
            return 1;
        }
    }.getPluginCount,

    .get_plugin_descriptor = struct {
        fn getPluginDescriptor(
            factory: [*c]const clap.clap_plugin_factory,
            index: u32,
        ) callconv(.c) [*c]const clap.clap_plugin_descriptor {
            _ = factory;
            return if (index == 0) &plugin_descriptor else null;
        }
    }.getPluginDescriptor,

    .create_plugin = struct {
        fn createPlugin(
            factory: [*c]const clap.clap_plugin_factory,
            host: [*c]const clap.clap_host,
            plugin_id: [*c]const u8,
        ) callconv(.c) [*c]const clap.clap_plugin {
            _ = factory;

            if (!clap.clap_version_is_compatible(host.*.clap_version)) {
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
    }.createPlugin,
};

const plugin_descriptor: clap.clap_plugin_descriptor = .{
    .clap_version = clap.CLAP_VERSION,
    .id = "dev.kengo.helloclapzig",
    .name = "HelloClapZig",
    .vendor = "kengo",
    .url = "https://kengo.dev",
    .manual_url = "https://kengo.dev",
    .support_url = "https://kengo.dev",
    .version = "1.0.0",
    .description = "Hello, CLAP!",
    .features = &[_][*c]const u8{
        clap.CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
        clap.CLAP_PLUGIN_FEATURE_STEREO,
        null,
    },
};

const gain_plugin: clap.clap_plugin = .{
    .desc = &plugin_descriptor,
    .plugin_data = null,

    .init = struct {
        fn init(plugin: [*c]const clap.clap_plugin) callconv(.c) bool {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.*.plugin_data));
            _ = plug;
            return true;
        }
    }.init,

    .destroy = struct {
        fn destroy(plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.*.plugin_data));
            allocator.destroy(plug);
        }
    }.destroy,

    .activate = struct {
        fn activate(
            plugin: [*c]const clap.clap_plugin,
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
    }.activate,

    .deactivate = struct {
        fn deactivate(plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            _ = plugin;
        }
    }.deactivate,

    .start_processing = struct {
        fn startProcessing(plugin: [*c]const clap.clap_plugin) callconv(.c) bool {
            _ = plugin;
            return true;
        }
    }.startProcessing,

    .stop_processing = struct {
        fn stopProcessing(plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            _ = plugin;
        }
    }.stopProcessing,

    .reset = struct {
        fn reset(plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            _ = plugin;
        }
    }.reset,

    .process = struct {
        fn processFn(
            plugin: [*c]const clap.clap_plugin,
            process: [*c]const clap.clap_process,
        ) callconv(.c) clap.clap_process_status {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.*.plugin_data));
            var gain_db = plug.gain_db.load(.monotonic);
            const in_events = process.*.in_events;
            const num_events = in_events.*.size.?(in_events);
            const num_frames = process.*.frames_count;
            var event_index: u32 = 0;
            var next_event_frame: u32 = if (num_events > 0) 0 else num_frames;

            var i: usize = 0;
            while (i < num_frames) {
                while (event_index < num_events and next_event_frame == i) {
                    const header = in_events.*.get.?(in_events, @intCast(event_index));

                    if (header.*.time != i) {
                        next_event_frame = header.*.time;
                        break;
                    }

                    if (header.*.space_id == clap.CLAP_CORE_EVENT_SPACE_ID and
                        header.*.type == clap.CLAP_EVENT_PARAM_VALUE)
                    {
                        const event_param_value: *const clap.clap_event_param_value = @ptrCast(@alignCast(header));
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
                    const in_l = process.*.audio_inputs[0].data32[0][i];
                    const in_r = process.*.audio_inputs[0].data32[1][i];

                    const out_l = in_l * gain_linear;
                    const out_r = in_r * gain_linear;

                    process.*.audio_outputs[0].data32[0][i] = out_l;
                    process.*.audio_outputs[0].data32[1][i] = out_r;
                }
            }

            plug.gain_db.store(gain_db, .monotonic);

            return clap.CLAP_PROCESS_CONTINUE;
        }
    }.processFn,

    .get_extension = struct {
        fn getExtension(
            plugin: [*c]const clap.clap_plugin,
            id: [*c]const u8,
        ) callconv(.c) ?*const anyopaque {
            _ = plugin;

            if (std.mem.eql(u8, std.mem.span(id), clap.CLAP_EXT_PARAMS[0..])) {
                return @ptrCast(&extension_params);
            }

            if (std.mem.eql(u8, std.mem.span(id), clap.CLAP_EXT_AUDIO_PORTS[0..])) {
                return @ptrCast(&extension_audio_ports);
            }

            if (std.mem.eql(u8, std.mem.span(id), clap.CLAP_EXT_STATE[0..])) {
                return @ptrCast(&extension_state);
            }

            return null;
        }
    }.getExtension,

    .on_main_thread = struct {
        fn onMainThread(plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            _ = plugin;
        }
    }.onMainThread,
};

const extension_params: clap.clap_plugin_params = .{
    .count = struct {
        fn count(plugin: [*c]const clap.clap_plugin) callconv(.c) u32 {
            _ = plugin;
            return 1;
        }
    }.count,

    .get_info = struct {
        fn getInfo(
            plugin: [*c]const clap.clap_plugin,
            param_index: u32,
            param_info: [*c]clap.clap_param_info,
        ) callconv(.c) bool {
            _ = plugin;

            if (param_index > 0) return false;

            param_info.*.id = gain_param_id;
            param_info.*.flags = clap.CLAP_PARAM_IS_AUTOMATABLE;
            _ = std.mem.printSentinel(param_info.*.name[0..], "{s}", .{"Gain"}, 0) catch unreachable;
            param_info.*.min_value = -60.0;
            param_info.*.max_value = 12.0;
            param_info.*.default_value = 0.0;

            return true;
        }
    }.getInfo,

    .get_value = struct {
        fn getValue(
            plugin: [*c]const clap.clap_plugin,
            param_id: clap.clap_id,
            out_value: [*c]f64,
        ) callconv(.c) bool {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.*.plugin_data));

            if (param_id == gain_param_id) {
                out_value.* = plug.gain_db.load(.monotonic);
                return true;
            }

            return false;
        }
    }.getValue,

    .value_to_text = struct {
        fn valueToText(
            plugin: [*c]const clap.clap_plugin,
            param_id: clap.clap_id,
            value: f64,
            out_buffer: [*c]u8,
            out_buffer_capacity: u32,
        ) callconv(.c) bool {
            _ = plugin;

            if (param_id == gain_param_id) {
                _ = std.mem.printSentinel(
                    out_buffer[0..out_buffer_capacity],
                    "{d:.1}{s}",
                    .{ value, gain_param_suffix },
                    0,
                ) catch return false;

                return true;
            }

            return true;
        }
    }.valueToText,

    .text_to_value = struct {
        fn textToValue(
            plugin: [*c]const clap.clap_plugin,
            param_id: clap.clap_id,
            param_value_text: [*c]const u8,
            out_value: [*c]f64,
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
    }.textToValue,

    .flush = struct {
        fn flush(
            plugin: [*c]const clap.clap_plugin,
            in: [*c]const clap.clap_input_events,
            out: [*c]const clap.clap_output_events,
        ) callconv(.c) void {
            _ = out;
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.*.plugin_data));

            var i: u32 = 0;
            while (i < in.*.size.?(in)) : (i += 1) {
                const event = in.*.get.?(in, i);

                if (event.*.space_id == clap.CLAP_CORE_EVENT_SPACE_ID and
                    event.*.type == clap.CLAP_EVENT_PARAM_VALUE)
                {
                    const event_param_value: *const clap.clap_event_param_value = @ptrCast(@alignCast(event));

                    if (event_param_value.param_id == gain_param_id) {
                        plug.gain_db.store(@floatCast(event_param_value.value), .monotonic);
                    }
                }
            }
        }
    }.flush,
};

const extension_audio_ports: clap.clap_plugin_audio_ports = .{
    .count = struct {
        fn count(plugin: [*c]const clap.clap_plugin, is_input: bool) callconv(.c) u32 {
            _ = plugin;
            _ = is_input;
            return 1;
        }
    }.count,

    .get = struct {
        fn get(
            plugin: [*c]const clap.clap_plugin,
            index: u32,
            is_input: bool,
            info: [*c]clap.clap_audio_port_info,
        ) callconv(.c) bool {
            _ = plugin;

            if (index > 0) return false;

            info.*.id = 0;
            info.*.channel_count = 2;
            info.*.flags = clap.CLAP_AUDIO_PORT_IS_MAIN;
            info.*.port_type = clap.CLAP_PORT_STEREO[0..];
            info.*.in_place_pair = clap.CLAP_INVALID_ID;
            _ = std.mem.printSentinel(
                info.*.name[0..],
                "{s}",
                .{if (is_input) "Audio Input" else "Audio Output"},
                0,
            ) catch unreachable;

            return true;
        }
    }.get,
};

const extension_state: clap.clap_plugin_state = .{
    .save = struct {
        fn save(
            plugin: [*c]const clap.clap_plugin,
            stream: [*c]const clap.clap_ostream,
        ) callconv(.c) bool {
            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.*.plugin_data));
            var gain_db = plug.gain_db.load(.monotonic);
            const data = std.mem.asBytes(&gain_db);

            var offset: usize = 0;
            while (offset < data.len) {
                const bytes_written = stream.*.write.?(
                    stream,
                    data.ptr + offset,
                    data.len - offset,
                );
                if (bytes_written <= 0) return false;
                offset += @intCast(bytes_written);
            }

            return true;
        }
    }.save,

    .load = struct {
        fn load(
            plugin: [*c]const clap.clap_plugin,
            stream: [*c]const clap.clap_istream,
        ) callconv(.c) bool {
            var gain_db: f32 = undefined;
            const data = std.mem.asBytes(&gain_db);

            var offset: usize = 0;
            while (offset < data.len) {
                const bytes_read = stream.*.read.?(
                    stream,
                    data.ptr + offset,
                    data.len - offset,
                );
                if (bytes_read <= 0) return false;
                offset += @intCast(bytes_read);
            }

            const plug: *GainPlugin = @ptrCast(@alignCast(plugin.*.plugin_data));
            plug.gain_db.store(gain_db, .monotonic);
            return true;
        }
    }.load,
};
