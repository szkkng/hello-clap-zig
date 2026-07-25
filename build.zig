const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const clap = b.dependency("clap_zig", .{});

    const plugin = b.addLibrary(.{
        .name = "HelloClapZig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    plugin.root_module.addImport("clap_zig", clap.module("clap_zig"));

    const install_step = b.getInstallStep();
    switch (target.result.os.tag) {
        .macos => {
            const bundle_subpath = b.fmt("{s}.clap/Contents/MacOS", .{plugin.name});
            const install_bundle = b.addInstallArtifact(plugin, .{
                .dest_dir = .{ .override = .{ .custom = bundle_subpath } },
                .dest_sub_path = plugin.name,
            });
            const install_plist = b.addInstallFileWithDir(
                b.path("res/Info.plist"),
                .prefix,
                b.fmt("{s}.clap/Contents/Info.plist", .{plugin.name}),
            );
            install_plist.step.dependOn(&install_bundle.step);
            install_step.dependOn(&install_plist.step);
        },
        else => {
            const install_plugin = b.addInstallArtifact(plugin, .{
                .dest_dir = .{ .override = .prefix },
                .dest_sub_path = b.fmt("{s}.clap", .{plugin.name}),
            });
            install_step.dependOn(&install_plugin.step);
        },
    }
}
