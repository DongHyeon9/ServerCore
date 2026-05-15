#include "ServerDlgUtil.h"

namespace dialog
{
	namespace interface
	{
		void event::event_impl()
		{
			if (_event)
				_event();
		}
	}

	void menu_item::draw()
	{
		if (ImGui::MenuItem(_label.c_str()))
			event_impl();
	}

	void menu_bar::draw()
	{
		if (ImGui::BeginMenu(_label.c_str()))
		{
			for (auto menu_item : _items)
				menu_item->draw();
			ImGui::EndMenu();
		}
	}

	void main_menu::draw()
	{
		if (ImGui::BeginMainMenuBar())
		{
			for (auto menu_bar : _items)
				menu_bar->draw();
			ImGui::EndMainMenuBar();
		}
	}

	namespace panel_item
	{
		void multiple_item::draw()
		{
			for (auto item : _items)
			{
				item->draw();
				ImGui::SameLine();
			}
		}

		void button::draw()
		{
			if (ImGui::Button(_label.c_str(), _size))
				event_impl();
		}

		void text::draw()
		{
			ImGui::Text(_text.c_str());
		}

		void editable_text::draw()
		{
			ImGui::InputText(_label.c_str(), _text.data(), _text.size(), _flags);
		}

		void rich_text::draw()
		{
			ImGui::PushStyleColor(ImGuiCol_Text, _color);
			ImGui::TextUnformatted(_text.c_str());
			ImGui::PopStyleColor();
		}
	}

	void panel::draw()
	{
		ImGui::SetNextWindowPos(_desc._pos._point, _desc._pos._cond);
		ImGui::SetNextWindowSize(_desc._size._point, _desc._size._cond);
		if (ImGui::Begin(_label.c_str()))
		{
			for (auto child : _items)
				child->draw();
		}
		ImGui::End();
	}
}