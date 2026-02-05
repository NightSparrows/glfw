project "GLFW"
	language "C"

	filter { "not options:build-shared" }
		kind "StaticLib"
		staticruntime "on"
	filter { "options:build-shared" }
		kind "SharedLib"
		staticruntime "off"
		defines "_GLFW_BUILD_DLL"
	filter {}
	
	targetdir ("bin/" .. outputdir .. "/%{prj.name}")
	objdir ("bin-int/" .. outputdir .. "/%{prj.name}")

	files
	{
		"include/GLFW/glfw3.h",
		"include/GLFW/glfw3native.h",
		"src/glfw_config.h",
		"src/context.c",
		"src/init.c",
		"src/input.c",
		"src/monitor.c",

		"src/null_init.c",
		"src/null_joystick.c",
		"src/null_monitor.c",
		"src/null_window.c",

		"src/platform.c",
		"src/vulkan.c",
		"src/window.c",
	}

	filter "system:linux"
		pic "On"

		systemversion "latest"
		-- 定義 GLFW 需要的所有協議 (名稱與路徑對應)
		local protocols = {
			{ name = "wayland", xml = "/usr/share/wayland/wayland.xml", is_core = true },
			{ name = "xdg-shell", xml = "stable/xdg-shell/xdg-shell.xml" },
			{ name = "xdg-decoration-unstable-v1", xml = "unstable/xdg-decoration/xdg-decoration-unstable-v1.xml" },
			{ name = "viewporter", xml = "stable/viewporter/viewporter.xml" },
			{ name = "relative-pointer-unstable-v1", xml = "unstable/relative-pointer/relative-pointer-unstable-v1.xml" },
			{ name = "pointer-constraints-unstable-v1", xml = "unstable/pointer-constraints/pointer-constraints-unstable-v1.xml" },
			{ name = "fractional-scale-v1", xml = "staging/fractional-scale/fractional-scale-v1.xml" },
			{ name = "xdg-activation-v1", xml = "staging/xdg-activation/xdg-activation-v1.xml" },
			{ name = "idle-inhibit-unstable-v1", xml = "unstable/idle-inhibit/idle-inhibit-unstable-v1.xml" }
		}

		local protocol_dir = "/usr/share/wayland-protocols/"
		
		for _, proto in ipairs(protocols) do
			local xml_path = proto.is_core and proto.xml or (protocol_dir .. proto.xml)
			
			-- 這裡是關鍵：對齊 GLFW 的 include 命名規則
			local client_header = "src/" .. proto.name .. "-client-protocol.h"
			local code_header   = "src/" .. proto.name .. "-client-protocol-code.h"

			-- 注意：這些生成的檔案現在都是 .h，所以不應該放進 files {} 裡讓編譯器直接編譯
			-- 它們會被 wl_init.c 等檔案 #include 進去


			print("Generating protocol: " .. proto.name)
			os.execute("wayland-scanner client-header " .. xml_path .. " " .. client_header)
			os.execute("wayland-scanner private-code " .. xml_path .. " " .. code_header)
			-- prebuildcommands {
			-- -- 生成定義標頭檔
			-- "wayland-scanner client-header " .. xml_path .. " " .. client_header,
			-- -- 生成實作標頭檔 (原本是 .c，現在改成 -code.h)
			-- "wayland-scanner private-code " .. xml_path .. " " .. code_header
			-- }
		end
		
		files
		{
			-- POSIX/Common
			"src/posix_time.c",
			"src/posix_poll.c",
			"src/posix_thread.c",
			"src/posix_module.c",
			"src/linux_joystick.c",
			"src/xkb_unicode.c",

			-- wayland
			"src/wl_init.c",
			"src/wl_monitor.c",
			"src/wl_window.c",

			-- X11
			"src/x11_init.c",
			"src/x11_monitor.c",
			"src/x11_window.c",
			"src/glx_context.c",

			-- Context
			"src/egl_context.c",
			"src/osmesa_context.c"
		}

		defines
		{
			"_GLFW_X11",
			"_GLFW_WAYLAND" -- 啟用 Wayland 支援
		}

	filter "system:macosx"
		pic "On"

		files
		{
			"src/cocoa_init.m",
			"src/cocoa_monitor.m",
			"src/cocoa_window.m",
			"src/cocoa_joystick.m",
			"src/cocoa_time.c",
			"src/nsgl_context.m",
			"src/posix_thread.c",
			"src/posix_module.c",
			"src/osmesa_context.c",
			"src/egl_context.c"
		}

		defines
		{
			"_GLFW_COCOA"
		}

	filter "system:windows"
		systemversion "latest"

		files
		{
			"src/win32_init.c",
			"src/win32_joystick.c",
			"src/win32_module.c",
			"src/win32_monitor.c",
			"src/win32_time.c",
			"src/win32_thread.c",
			"src/win32_window.c",
			"src/wgl_context.c",
			"src/egl_context.c",
			"src/osmesa_context.c"
		}

		defines 
		{ 
			"_GLFW_WIN32",
			"_CRT_SECURE_NO_WARNINGS"
		}

		links
		{
			"Dwmapi.lib"
		}

	filter "configurations:Debug"
		runtime "Debug"
		symbols "on"

	filter "configurations:Release"
		runtime "Release"
		optimize "on"

	filter "configurations:Dist"
		runtime "Release"
		optimize "on"
        	symbols "off"