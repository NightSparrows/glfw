const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "build-shared", "build shared lib") orelse false;

    const mod = b.addModule("glfw", .{
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });
    const os = target.result.os.tag;
    mod.addIncludePath(b.path("include"));
    mod.addIncludePath(b.path("src"));
    // 基礎通用檔案
    mod.addCSourceFiles(.{
        .files = &[_][]const u8{
            "src/context.c",
            "src/init.c",
            "src/input.c",
            "src/monitor.c",
            "src/platform.c",
            "src/vulkan.c",
            "src/window.c",
            "src/egl_context.c",
            "src/osmesa_context.c",

            // null backend
            "src/null_init.c",
            "src/null_joystick.c",
            "src/null_monitor.c",
            "src/null_window.c",
        },
        .flags = &[_][]const u8{
            "-std=c99",
        },
    });
    // ==========================================
    // LINUX / POSIX 平台基礎
    // ==========================================
    if (os != .windows and os != .macos) {
        mod.addCMacro("_DEFAULT_SOURCE", "1"); // 避免 -std=c99 停用 _GNU_SOURCE/POSIX 函數

        mod.addCSourceFiles(.{
            .files = &[_][]const u8{
                "src/posix_time.c",
                "src/posix_poll.c",
                "src/posix_thread.c",
                "src/posix_module.c",
                "src/linux_joystick.c",
                "src/xkb_unicode.c",
            },
            .flags = &[_][]const u8{"-std=c99"},
        });

        // 同時啟用 X11 與 Wayland 後端
        mod.addCMacro("_GLFW_X11", "1");
        mod.addCMacro("_GLFW_WAYLAND", "1");

        mod.addCSourceFiles(.{
            .files = &[_][]const u8{
                // X11
                "src/x11_init.c",
                "src/x11_monitor.c",
                "src/x11_window.c",
                "src/glx_context.c",
                // Wayland
                "src/wl_init.c",
                "src/wl_monitor.c",
                "src/wl_window.c",
            },
            .flags = &[_][]const u8{"-std=c99"},
        });

        mod.addCMacro("HAVE_MEMFD_CREATE", "1");

        // 系統庫連結 (不論是否 shared，編譯靜態庫時也需要知道相依性)
        mod.linkSystemLibrary("X11", .{});
        mod.linkSystemLibrary("Xrandr", .{});
        mod.linkSystemLibrary("Xinerama", .{});
        mod.linkSystemLibrary("Xcursor", .{});
        mod.linkSystemLibrary("Xi", .{});
        mod.linkSystemLibrary("dl", .{});
        mod.linkSystemLibrary("m", .{});
        mod.linkSystemLibrary("rt", .{});
        mod.linkSystemLibrary("xkbcommon", .{});
        mod.linkSystemLibrary("wayland-client", .{});
        mod.linkSystemLibrary("wayland-cursor", .{});
        mod.linkSystemLibrary("wayland-egl", .{});
    }

    // ==========================================
    // WINDOWS 平台配置
    // ==========================================
    if (os == .windows) {
        mod.addCMacro("_GLFW_WIN32", "1");
        mod.addCMacro("UNICODE", "1");
        mod.addCMacro("_UNICODE", "1");
        mod.addCMacro("_CRT_SECURE_NO_WARNINGS", "1");

        mod.addCSourceFiles(.{
            .files = &[_][]const u8{
                "src/win32_init.c",
                "src/win32_joystick.c",
                "src/win32_monitor.c",
                "src/win32_time.c",
                "src/win32_thread.c",
                "src/win32_window.c",
                "src/win32_module.c",
                "src/wgl_context.c",
            },
            .flags = &[_][]const u8{},
        });

        mod.linkSystemLibrary("gdi32", .{});
        mod.linkSystemLibrary("user32", .{});
        mod.linkSystemLibrary("kernel32", .{});
    }

    // ==========================================
    // MACOS 平台配置
    // ==========================================
    if (os == .macos) {
        mod.addCMacro("_GLFW_COCOA", "1");

        mod.addCSourceFiles(.{
            .files = &[_][]const u8{
                "src/cocoa_init.m",
                "src/cocoa_joystick.m",
                "src/cocoa_monitor.m",
                "src/cocoa_window.m",
                "src/macos_time.c",
                "src/posix_thread.c",
                "src/posix_module.c",
                "src/nsgl_context.m",
            },
            .flags = &[_][]const u8{},
        });
    }

    if (shared) {
        mod.addCMacro("_GLFW_BUILD_DLL", "1");
        if (os != .windows) {
            mod.pic = true;
            mod.addCSourceFiles(.{ .files = &[_][]const u8{}, .flags = &[_][]const u8{"-fvisibility=hidden"} });
        }
    }

    // 建立最終的 Library
    const lib = b.addLibrary(.{
        .name = "glfw",
        .linkage = if (shared) .dynamic else .static,
        .root_module = mod, // 這裡完美對接你的 Module
    });

    // macOS Framework 連結必須在 lib 實體上操作
    if (os == .macos) {
        mod.linkFramework("Cocoa", .{});
        mod.linkFramework("IOKit", .{});
        mod.linkFramework("QuartzCore", .{});
        mod.linkFramework("CoreFoundation", .{});
    }

    // ==========================================
    // Wayland 協議自動生成 (修正編譯器識別問題)
    // ==========================================
    if (os != .windows and os != .macos) {
        const protocols = [_][]const u8{
            "wayland",
            "viewporter",
            "xdg-shell",
            "idle-inhibit-unstable-v1",
            "pointer-constraints-unstable-v1",
            "relative-pointer-unstable-v1",
            "fractional-scale-v1",
            "xdg-activation-v1",
            "xdg-decoration-unstable-v1",
        };

        for (protocols) |proto| {
            // GLFw 自帶
            const xml_path = b.fmt("deps/wayland/{s}.xml", .{proto});

            // 1. 生成 client-header
            const header_cmd = b.addSystemCommand(&[_][]const u8{ "wayland-scanner", "client-header" });
            header_cmd.addFileArg(b.path(xml_path));
            const actual_header = header_cmd.addOutputFileArg(b.fmt("{s}-client-protocol.h", .{proto}));

            // 2. 生成 private-code
            const code_cmd = b.addSystemCommand(&[_][]const u8{ "wayland-scanner", "private-code" });
            code_cmd.addFileArg(b.path(xml_path));
            const actual_code = code_cmd.addOutputFileArg(b.fmt("{s}-client-protocol-code.h", .{proto}));

            // 讓模組找得到標頭檔目錄
            mod.addIncludePath(actual_header.dirname());
            mod.addIncludePath(actual_code.dirname());
        }
    }
    b.installArtifact(lib);
}
