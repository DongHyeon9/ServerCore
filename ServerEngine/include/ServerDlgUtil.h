#pragma once
#include "ServerEngine.h"

namespace dialog
{
	class component_base
	{
	public:
		virtual void draw() = 0;
		inline void set_label(std::string Label){ _label = std::move(Label); }
		inline const std::string& get_label()const { return _label; }
		virtual ~component_base() = default;

	protected:
		std::string _label{};
	};

	namespace interface
	{
		class event
		{
		public:
			inline void set_event(std::function<void()> Event) { _event = std::move(Event); }
			virtual ~event() = default;

		protected:
			event() = default;
			void event_impl();

		protected:
			std::function<void()> _event{};
		};

		template<class T> requires std::is_base_of_v<component_base, T>
		class hierarchy
		{
		public:
			void add_item(std::shared_ptr<T> Item) { _items.emplace_back(Item); }
			const std::vector<std::shared_ptr<T>>& get_items()const { return _items; }
			void set_items(const std::vector<std::shared_ptr<T>>& Items) { _items = Items; }
			virtual ~hierarchy() = default;

		protected:
			hierarchy() = default;

		protected:
			std::vector<std::shared_ptr<T>> _items{};
		};
	}

	class menu_item 
		: public component_base
		, public interface::event
	{
	public:
		void draw() override;

	};

	class menu_bar 
		: public component_base
		, public interface::hierarchy<menu_item>
	{
	public:
		void draw() override;

	};

	class main_menu
		: public component_base
		, public interface::hierarchy<menu_bar>
	{
	public:
		void draw() override;

	};

	namespace pannel_item
	{
		class base : public component_base {};

		class mutiple_item
			: public base
			, public interface::hierarchy<base>
		{
		public:
			void draw() override;
		};

		class button
			: public base
			, interface::event
		{
		public:
			void draw() override;
			inline void set_size(ImVec2 Size) { _size = Size; }

		private:
			ImVec2 _size{};
		};

		class text
			: public base
		{
		public:
			void draw() override;
			inline void set_text(std::string Text) { _text = std::move(Text); }
			inline const std::string& get_text()const { return _text; }

		protected:
			std::string _text{};

		};

		class editable_text
			: public text
		{
		public:
			editable_text(std::size_t Buffer = 128) { _text.resize(Buffer); }
			void draw() override;
			void set_input_text_flags(ImGuiInputTextFlags_ NewFlags) { _flags = NewFlags; }
			void add_input_text_flags(ImGuiInputTextFlags_ Flags) { _flags = static_cast<ImGuiInputTextFlags_>(static_cast<uint32>(_flags) | static_cast<uint32>(Flags)); }
			void set_text(std::string) = delete;

		private:
			ImGuiInputTextFlags_ _flags{};
		};

		class rich_text
			: public text
		{
		public:
			void draw() override;
			inline void set_color(ImVec4 NewColor) { _color = NewColor; }

		private:
			ImVec4 _color{ 1.0f, 1.0f, 1.0f, 1.0f };
		};

		class spacing : public base { public: void draw() override { ImGui::Spacing(); } };
		class separator : public base { public: void draw() override { ImGui::Separator(); } };
	}

	class pannel
		: public component_base
		, public interface::hierarchy<pannel_item::base>
	{
	public:
		struct description
		{
			struct attribute
			{
				ImVec2 _point{};
				ImGuiCond_ _cond{};
			}_size, _pos;
		};

	public:
		void draw() override;
		inline void set_desc(const description& Desc) { _desc = Desc; }

		void add_spacing() { _items.emplace_back(std::make_shared<pannel_item::spacing>()); }
		void add_separator() { _items.emplace_back(std::make_shared<pannel_item::separator>()); }

	private:
		description _desc;

	};

	namespace util
	{
		template<class T> requires std::is_base_of_v<component_base,T>
		std::shared_ptr<T> create_component(std::string _label)
		{
			std::shared_ptr<T> comp{ std::make_shared<T>() };
			comp->set_label(std::move(_label));
			return comp;
		}
	}
}
