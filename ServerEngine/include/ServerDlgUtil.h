#pragma once
#include "ServerEngine.h"

#define DIALOG_DECLARE_TYPE(enum_value)										\
public:																		\
static constexpr E_COMPONENT_TYPE _s_type_id{ enum_value };					\
E_COMPONENT_TYPE type_id() const noexcept override { return _s_type_id; }	\
private:

// component는 멀티스레드에 대한 고려가 안돼있음
// server_dialog_base를 상속받아 명령큐에 넣는 식으로 동작해야됨
namespace dialog
{
	enum class E_COMPONENT_TYPE : uint16
	{
		UNKNOWN,

		MENU_ITEM,
		MENU_BAR,
		MAIN_MENU,

		PANEL,
		PANEL_ITEM_BASE,
		PANEL_ITEM_MULTIPLE_ITEM,
		PANEL_ITEM_BUTTON,
		PANEL_ITEM_TEXT,
		PANEL_ITEM_EDITABLE_TEXT,
		PANEL_ITEM_RICH_TEXT,
		PANEL_ITEM_SPACING,
		PANEL_ITEM_SEPARATOR,
	};

	class component_base : public std::enable_shared_from_this<component_base>
	{
	public:
		virtual void draw() = 0;
		void set_label(std::string Label)
		{ 
			std::string before = std::move(_label);
			_label = std::move(Label);
			_on_label_change.broadcast(before, _label);
		}
		const std::string& get_label()const noexcept { return _label; }
		component_base() = default;
		component_base(const component_base&) = default;
		component_base& operator=(const component_base&) = default;
		virtual ~component_base() = default;
		virtual E_COMPONENT_TYPE type_id() const noexcept { return E_COMPONENT_TYPE::UNKNOWN; }

	public:
		on_label_change_delegate _on_label_change{};

	protected:
		std::string _label{};

	};

	namespace interface
	{
		class event
		{
		public:
			void set_event(std::function<void()> Event) { _event = std::move(Event); }
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
			bool add_item(std::shared_ptr<T> Item)
			{
				if (!Item)
					return false;

				const std::string& label{ Item->get_label() };

				// 빈 라벨은 맵에 등록하지 않지만, 벡터에는 추가 가능
				if (!label.empty() && _item_map.contains(label))
					return false;

				_items.emplace_back(Item);

				if (!label.empty())
					_item_map[label] = Item;

				// 라벨 변경 시 _item_map을 자동 동기화하는 콜백 등록
				// weak_ptr를 캡처해서 hierarchy가 먼저 파괴되어도 안전하게
				std::weak_ptr<T> weak_item = Item;
				delegate_handle handle = Item->_on_label_change.add(
					[this, weak_item](const std::string& Before, const std::string& After)
					{
						auto sp = weak_item.lock();
					
						if (!sp)
							return;

						// 이전 키 제거
						if (!Before.empty())
						{
							auto it = _item_map.find(Before);
							if (it != _item_map.end() && it->second == sp)
								_item_map.erase(it);
						}

						// 새 키 등록 (이미 다른 아이템이 차지하고 있다면 등록하지 않음)
						if (!After.empty() && !_item_map.contains(After))
							_item_map[After] = sp;
					});

				// 나중에 콜백을 해제하기 위해 핸들 보관
				_label_change_handles[Item.get()] = handle;
				return true;
			}

			std::shared_ptr<T> find_item(const std::string& Label)
			{
				auto it = _item_map.find(Label);
				return it == _item_map.end() ? nullptr : it->second;
			}

			const std::vector<std::shared_ptr<T>>& get_items() const noexcept { return _items; }

			void set_items(std::vector<std::shared_ptr<T>> Items)
			{
				// 기존 아이템들의 콜백 모두 해제
				clear_label_callbacks();

				_items.clear();
				_item_map.clear();

				// 새 아이템들을 add_item으로 재등록 (콜백 포함)
				for (auto& item : Items)
					add_item(std::move(item));
			}

			bool remove_item(const std::string& Label)
			{
				auto map_it = _item_map.find(Label);
				if (map_it == _item_map.end())
					return false;

				std::shared_ptr<T> target = map_it->second;
				_item_map.erase(map_it);

				// 벡터에서 제거
				auto vec_it = std::find(_items.begin(), _items.end(), target);
				if (vec_it != _items.end())
					_items.erase(vec_it);

				// 라벨 변경 콜백 해제
				unregister_label_callback(target.get());
				return true;
			}

			bool remove_item(std::shared_ptr<T> Item)
			{
				if (!Item)
					return false;

				auto vec_it = std::find(_items.begin(), _items.end(), Item);
				if (vec_it == _items.end())
					return false;

				_items.erase(vec_it);

				// 맵에서도 제거 (라벨이 비어있을 수 있으니 값으로 검색)
				for (auto it = _item_map.begin(); it != _item_map.end(); )
				{
					if (it->second == Item)
						it = _item_map.erase(it);
					else
						++it;
				}

				unregister_label_callback(Item.get());
				return true;
			}

			void clear()
			{
				clear_label_callbacks();
				_items.clear();
				_item_map.clear();
			}

			virtual ~hierarchy()
			{
				// hierarchy가 파괴될 때 모든 아이템의 콜백 해제
				// (아이템이 hierarchy보다 오래 살아남는 경우 dangling this 방지)
				clear_label_callbacks();
			}

		protected:
			hierarchy() = default;

		private:
			void unregister_label_callback(T* RawItem)
			{
				auto it = _label_change_handles.find(RawItem);
				if (it != _label_change_handles.end())
				{
					// 아이템이 아직 살아있다면 콜백 해제
					// (raw pointer로 보관 중이므로 _items/_item_map에서 찾아 확인)
					for (const auto& item : _items)
					{
						if (item.get() == RawItem)
						{
							item->_on_label_change.remove(it->second);
							break;
						}
					}
					_label_change_handles.erase(it);
				}
			}

			void clear_label_callbacks()
			{
				for (const auto& item : _items)
				{
					if (!item)
						continue;
					auto it = _label_change_handles.find(item.get());
					if (it != _label_change_handles.end())
						item->_on_label_change.remove(it->second);
				}
				_label_change_handles.clear();
			}

		protected:
			std::vector<std::shared_ptr<T>> _items{};
			std::unordered_map<std::string, std::shared_ptr<T>> _item_map{};

		private:
			// 아이템별 라벨 변경 콜백 핸들 (raw pointer를 키로 사용)
			std::unordered_map<T*, delegate_handle> _label_change_handles{};
		};
	}

	class menu_item 
		: public component_base
		, public interface::event
	{
		DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::MENU_ITEM);
	public:
		void draw() override;

	};

	class menu_bar 
		: public component_base
		, public interface::hierarchy<menu_item>
	{
		DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::MENU_BAR);
	public:
		void draw() override;

	};

	class main_menu
		: public component_base
		, public interface::hierarchy<menu_bar>
	{
		DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::MAIN_MENU);
	public:
		void draw() override;

	};

	namespace panel_item
	{
		class base : public component_base { DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_BASE); };

		class multiple_item
			: public base
			, public interface::hierarchy<base>
		{
			DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_MULTIPLE_ITEM);
		public:
			void draw() override;
		};

		class button
			: public base
			, public interface::event
		{
			DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_BUTTON);
		public:
			void draw() override;
			void set_size(ImVec2 Size) { _size = Size; }

		private:
			ImVec2 _size{};
		};

		class text
			: public base
		{
			DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_TEXT);
		public:
			void draw() override;
			void set_text(std::string Text) { _text = std::move(Text); }
			const std::string& get_text()const noexcept { return _text; }

		protected:
			std::string _text{};

		};

		class editable_text
			: public text
		{
			DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_EDITABLE_TEXT);
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
			DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_RICH_TEXT);
		public:
			void draw() override;
			void set_color(ImVec4 NewColor) { _color = NewColor; }

		private:
			ImVec4 _color{ 1.0f, 1.0f, 1.0f, 1.0f };
		};

		class spacing : public base { DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_SPACING); public: void draw() override { ImGui::Spacing(); } };
		class separator : public base { DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL_ITEM_SEPARATOR); public: void draw() override { ImGui::Separator(); } };
	}

	class panel
		: public component_base
		, public interface::hierarchy<panel_item::base>
	{
		DIALOG_DECLARE_TYPE(E_COMPONENT_TYPE::PANEL);
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
		void set_desc(const description& Desc) { _desc = Desc; }

		void add_spacing() { add_item(std::make_shared<panel_item::spacing>()); }
		void add_separator() { add_item(std::make_shared<panel_item::separator>()); }

	private:
		description _desc;

	};

	namespace util
	{
		template<class T, class... ARGS> requires std::is_base_of_v<component_base,T>
		std::shared_ptr<T> create_component(std::string Label, ARGS&&... Args)
		{
			std::shared_ptr<T> comp{ std::make_shared<T>(std::forward<ARGS>(Args)...) };
			comp->set_label(std::move(Label));
			return comp;
		}

		template<class DERIVED, class BASE> requires std::is_base_of_v<component_base, BASE> && std::is_base_of_v<component_base, DERIVED>
		DERIVED* Cast(BASE* Ptr) noexcept
		{
			return (Ptr && Ptr->type_id() == DERIVED::_s_type_id) ? static_cast<DERIVED*>(Ptr) : nullptr;
		}

		template<class DERIVED, class BASE> requires std::is_base_of_v<component_base, BASE>&& std::is_base_of_v<component_base, DERIVED>
		std::shared_ptr<DERIVED> Cast(std::shared_ptr<BASE> Ptr) noexcept
		{
			return (Ptr && Ptr->type_id() == DERIVED::_s_type_id) ? std::static_pointer_cast<DERIVED>(Ptr) : nullptr;
		}
	}
}
