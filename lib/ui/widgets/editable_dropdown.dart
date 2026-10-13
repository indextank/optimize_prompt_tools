/// 可编辑下拉框（对齐基准项目 qfluentwidgets `EditableComboBox` 语义）。
///
/// - 文本框可自由键入（手动编辑）；
/// - 下拉按钮打开的菜单**始终全量展示所有预设项**，绝不按当前文本过滤。
///
/// 用于替代 fluent_ui `AutoSuggestBox`——后者按输入文本过滤候选，
/// 在预填默认值时会把不匹配的合法预设项隐藏（智谱/Kimi 多地址、
/// Kimi 4 模型只显示 2 个即此根因）。
library;

import 'package:fluent_ui/fluent_ui.dart';

class EditableDropdown extends StatelessWidget {
  const EditableDropdown({
    super.key,
    required this.controller,
    required this.options,
    this.placeholder = '',
    this.dropdownKey,
    this.textKey,
    this.onChanged,
    this.onSelected,
  });

  /// 文本控制器（持有当前值；外部可读写）
  final TextEditingController controller;

  /// 全部预设选项（下拉菜单恒全量展示）
  final List<String> options;

  final String placeholder;

  /// 下拉按钮的 Key（测试定位）
  final Key? dropdownKey;

  /// 文本框的 Key（测试定位）
  final Key? textKey;

  /// 文本编辑回调（手动键入时触发）
  final ValueChanged<String>? onChanged;

  /// 选中预设项回调
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextBox(
          key: textKey,
          controller: controller,
          placeholder: placeholder,
          onChanged: onChanged,
        ),
      ),
      const SizedBox(width: 6),
      DropDownButton(
        key: dropdownKey,
        items: [
          for (final o in options)
            MenuFlyoutItem(
              text: Text(o, style: const TextStyle(fontSize: 12.5)),
              onPressed: () {
                controller.text = o;
                controller.selection =
                    TextSelection.collapsed(offset: o.length);
                onSelected?.call(o);
              },
            ),
        ],
        buttonBuilder: (context, onOpen) => IconButton(
          icon: const Icon(FluentIcons.chevron_down, size: 10),
          onPressed: options.isEmpty ? null : onOpen,
        ),
      ),
    ]);
  }
}
