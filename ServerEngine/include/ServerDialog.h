#pragma once
#include "ServerDialogPreset.h"

// ── 간단한 로그 버퍼 ──────────────────────────────────────────────────────────
struct LogBuffer
{
	std::vector<std::string> lines;
	bool scrollToBottom = true;

	void add(const char* fmt, ...)
	{
		char buf[512];
		va_list args;
		va_start(args, fmt);
		vsnprintf(buf, sizeof(buf), fmt, args);
		va_end(args);

		time_t t = time(nullptr);
		char timebuf[16];
		strftime(timebuf, sizeof(timebuf), "%H:%M:%S", localtime(&t));

		lines.push_back(std::string("[") + timebuf + "] " + buf);
		if (lines.size() > 256)
			lines.erase(lines.begin());
		scrollToBottom = true;
	}

	void draw(const char* title)
	{
		ImGui::SetNextWindowSize(ImVec2(700, 250), ImGuiCond_FirstUseEver);
		if (!ImGui::Begin(title)) { ImGui::End(); return; }

		if (ImGui::Button("Clear")) lines.clear();
		ImGui::SameLine();
		ImGui::Text("%zu lines", lines.size());
		ImGui::Separator();

		ImGui::BeginChild("scrollregion", ImVec2(0, 0), false, ImGuiWindowFlags_HorizontalScrollbar);
		for (const auto& l : lines)
			ImGui::TextUnformatted(l.c_str());
		if (scrollToBottom)
		{
			ImGui::SetScrollHereY(1.0f);
			scrollToBottom = false;
		}
		ImGui::EndChild();
		ImGui::End();
	}
};

inline void GlfwErrorCallback(int error, const char* description)
{
	::fprintf(stderr, "GLFW Error %d: %s\n", error, description);
}

template<class T>
class server_dialog_base : public singleton<T>
{
public:
	bool init() override
	{
		pre_init_impl();

		::glfwSetErrorCallback(GlfwErrorCallback);
		if (!::glfwInit())
			return false;

		::glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, _info.glfw_version.major);
		::glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, _info.glfw_version.minor);

		_window = ::glfwCreateWindow(
			_info.window_size.width,
			_info.window_size.height,
			_info.title.c_str(), nullptr, nullptr);
		if (!_window) 
		{ 
			::glfwTerminate();
			return false; 
		}

		::glfwMakeContextCurrent(_window);
		::glfwSwapInterval(_info.swap_interval);
		IMGUI_CHECKVERSION();
		ImGui::CreateContext();
		ImGuiIO& io = ImGui::GetIO();
		io.ConfigFlags |= _info.imgui_config_flags;

		ImGui::StyleColorsDark();

		::ImGui_ImplGlfw_InitForOpenGL(_window, true);
		::ImGui_ImplOpenGL3_Init(_info.glsl_version.c_str());

		return init_impl();
	}

	int run()
	{
		log.add("TestServer started");

		// ── 메인 루프 ─────────────────────────────────────────────────────────────
		while (!glfwWindowShouldClose(_window))
		{
			render_begin();
			ImGuiIO& io = ImGui::GetIO();

			for (auto item : _items)
				item.second->draw();

			// ── 서버 컨트롤 패널 ──────────────────────────────────────────────────
			ImGui::SetNextWindowPos(ImVec2(10, 30), ImGuiCond_FirstUseEver);
			ImGui::SetNextWindowSize(ImVec2(300, 180), ImGuiCond_FirstUseEver);
			if (ImGui::Begin("Server Control"))
			{
				ImGui::Text("Port:");
				ImGui::SameLine();
				ImGui::SetNextItemWidth(80);
				ImGui::InputText("##port", portBuf, sizeof(portBuf),
					serverRunning ? ImGuiInputTextFlags_ReadOnly : 0);

				ImGui::Spacing();

				if (!serverRunning)
				{
					if (ImGui::Button("Start Server", ImVec2(120, 30)))
					{
						serverRunning = true;
						log.add("Server listening on port %s", portBuf);
					}
				}
				else
				{
					ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.7f, 0.1f, 0.1f, 1.0f));
					if (ImGui::Button("Stop Server", ImVec2(120, 30)))
					{
						serverRunning = false;
						activeConnections = 0;
						log.add("Server stopped");
					}
					ImGui::PopStyleColor();
				}

				ImGui::Spacing();
				ImGui::Separator();

				ImVec4 stateColor = serverRunning
					? ImVec4(0.2f, 0.9f, 0.2f, 1.0f)
					: ImVec4(0.7f, 0.7f, 0.7f, 1.0f);
				ImGui::TextColored(stateColor, "Status: %s",
					serverRunning ? "RUNNING" : "STOPPED");
			}
			ImGui::End();

			// ── 통계 패널 ─────────────────────────────────────────────────────────
			ImGui::SetNextWindowPos(ImVec2(320, 30), ImGuiCond_FirstUseEver);
			ImGui::SetNextWindowSize(ImVec2(300, 180), ImGuiCond_FirstUseEver);
			if (ImGui::Begin("Statistics"))
			{
				ImGui::Text("Active Connections : %d", activeConnections);
				ImGui::Text("Packets / sec      : %.1f", packetsPerSec);
				ImGui::Text("Bytes In  / sec    : %.1f KB", bytesInPerSec / 1024.0f);
				ImGui::Text("Bytes Out / sec    : %.1f KB", bytesOutPerSec / 1024.0f);
				ImGui::Separator();
				ImGui::Text("Frame %.3f ms (%.1f FPS)",
					1000.0f / io.Framerate, io.Framerate);
			}
			ImGui::End();

			// ── 로그 패널 ─────────────────────────────────────────────────────────
			ImGui::SetNextWindowPos(ImVec2(10, 220), ImGuiCond_FirstUseEver);
			log.draw("Log");

			render_end();
		}
		return 0;
	}

	void terminate() override
	{
		::ImGui_ImplOpenGL3_Shutdown();
		::ImGui_ImplGlfw_Shutdown();
		::ImGui::DestroyContext();
		::glfwDestroyWindow(_window);
		::glfwTerminate();
	}

	void close_dialog()
	{
		::glfwSetWindowShouldClose(_window, true);
	}

protected:
	// 기본 초기화 이후 서버 대화상자 고유의 초기화 작업을 수행하기 위한 함수
	virtual bool init_impl() = 0;
	//dialog_info 설정 등 GLFW 초기화 전에 필요한 작업을 수행하기 위한 함수
	virtual void pre_init_impl() = 0;

private:
	void render_begin()
	{
		::glfwPollEvents();
		if (::glfwGetWindowAttrib(_window, GLFW_ICONIFIED) != 0)
		{
			::ImGui_ImplGlfw_Sleep(10);
			return;
		}

		::ImGui_ImplOpenGL3_NewFrame();
		::ImGui_ImplGlfw_NewFrame();
		ImGui::NewFrame();
	}

	void render_end()
	{
		ImGui::Render();
		int display_w, display_h;
		::glfwGetFramebufferSize(_window, &display_w, &display_h);
		::glViewport(0, 0, display_w, display_h);
		::glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
		::glClear(GL_COLOR_BUFFER_BIT);
		::ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

		::glfwSwapBuffers(_window);
	}

public:
	struct dialog_info
	{
		struct window_size
		{
			int32 width{ 1280 };
			int32 height{ 720 };
		} window_size;

		struct glfw_version
		{
			int major{ 3 };
			int minor{ 0 };
		} glfw_version;

		int32 swap_interval{ 1 };

		ImGuiConfigFlags imgui_config_flags{ ImGuiConfigFlags_NavEnableKeyboard };

		std::string glsl_version{ "#version 130" };
		std::string title{ "server dialog" };
	};

protected:
	dialog_info _info{};
	std::unordered_map<std::string, std::shared_ptr<dialog::component_base>> _items{};

private:
	GLFWwindow* _window{};

	// ── 상태 변수 ─────────────────────────────────────────────────────────────
	LogBuffer log;

	bool serverRunning = false;
	char portBuf[8] = "7777";
	int  activeConnections = 0;
	float packetsPerSec = 0.0f;
	float bytesInPerSec = 0.0f;
	float bytesOutPerSec = 0.0f;
};