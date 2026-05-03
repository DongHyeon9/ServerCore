#pragma once
#include "ServerEngine.h"

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

void GlfwErrorCallback(int error, const char* description)
{
	fprintf(stderr, "GLFW Error %d: %s\n", error, description);
}

template<class T>
class server_dialog_base : public singleton<T>
{
public:
	bool init() override
	{
		::glfwSetErrorCallback(GlfwErrorCallback);
		if (!::glfwInit())
			return false;

		const char* glsl_version = "#version 130";
		::glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
		::glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);

		window = ::glfwCreateWindow(1280, 720, "TestServer Monitor 2", nullptr, nullptr);
		if (!window) { ::glfwTerminate(); return false; }

		::glfwMakeContextCurrent(window);
		::glfwSwapInterval(1);
		IMGUI_CHECKVERSION();
		ImGui::CreateContext();
		ImGuiIO& io = ImGui::GetIO();
		io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

		ImGui::StyleColorsDark();

		::ImGui_ImplGlfw_InitForOpenGL(window, true);
		::ImGui_ImplOpenGL3_Init(glsl_version);


		return init_impl();
	}

	int run()
	{
		::glfwSetWindowTitle(window, "TestServer Monitor 3");

		log.add("TestServer started");

		// ── 메인 루프 ─────────────────────────────────────────────────────────────
		while (!glfwWindowShouldClose(window))
		{
			::glfwPollEvents();
			if (::glfwGetWindowAttrib(window, GLFW_ICONIFIED) != 0)
			{
				::ImGui_ImplGlfw_Sleep(10);
				continue;
			}

			::ImGui_ImplOpenGL3_NewFrame();
			::ImGui_ImplGlfw_NewFrame();
			ImGui::NewFrame();
			ImGuiIO& io = ImGui::GetIO();

			// ── 메뉴 바 ───────────────────────────────────────────────────────────
			if (ImGui::BeginMainMenuBar())
			{
				if (ImGui::BeginMenu("Server"))
				{
					if (ImGui::MenuItem("Exit"))
						::glfwSetWindowShouldClose(window, true);
					ImGui::EndMenu();
				}
				ImGui::EndMainMenuBar();
			}

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

			// ── 렌더링 ────────────────────────────────────────────────────────────
			ImGui::Render();
			int display_w, display_h;
			::glfwGetFramebufferSize(window, &display_w, &display_h);
			::glViewport(0, 0, display_w, display_h);
			::glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
			::glClear(GL_COLOR_BUFFER_BIT);
			::ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

			::glfwSwapBuffers(window);
		}
		return 0;
	}

	void terminate() override
	{
		::ImGui_ImplOpenGL3_Shutdown();
		::ImGui_ImplGlfw_Shutdown();
		::ImGui::DestroyContext();
		::glfwDestroyWindow(window);
		::glfwTerminate();
	}

protected:
	virtual bool init_impl() = 0;

private:
	GLFWwindow* window{};

	// ── 상태 변수 ─────────────────────────────────────────────────────────────
	LogBuffer log;

	bool serverRunning = false;
	char portBuf[8] = "7777";
	int  activeConnections = 0;
	float packetsPerSec = 0.0f;
	float bytesInPerSec = 0.0f;
	float bytesOutPerSec = 0.0f;
};