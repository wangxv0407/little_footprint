import 'package:flutter/material.dart';

/// 标签流式布局组件（自动换行）
class TagWrap extends StatelessWidget {
  final List<String> tags;
  final ValueChanged<String>? onDelete;
  final Color background;
  final Color foreground;

  const TagWrap({
    super.key,
    required this.tags,
    this.onDelete,
    this.background = const Color(0xFFF0F0F0),
    this.foreground = const Color(0xFF707070),
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tag, style: TextStyle(fontSize: 12, color: foreground)),
              if (onDelete != null)
                GestureDetector(
                  onTap: () => onDelete!(tag),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 14, color: Color(0xFFB0B0B0)),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
