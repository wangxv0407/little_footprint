import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../models/baby_info.dart';

/// 标准白底卡片（1px 描边，不用重投影）
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color color;
  final BoxBorder? border;
  final VoidCallback? onTap;

  /// 需要把内容严格裁在圆角内时传 [Clip.antiAlias]。
  /// 默认不裁：绝大多数卡片内容不会超出，裁一层多一次 saveLayer。
  final Clip clipBehavior;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.margin,
    this.radius = AppRadius.lg,
    this.color = AppColors.card,
    this.border,
    this.onTap,
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: AppColors.line, width: 1),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

/// 小节标题：西文 eyebrow + 可选中文标题
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
        AppSpace.pageX, AppSpace.xl, AppSpace.pageX, AppSpace.xs),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: AppText.eyebrow),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 圆形/圆角筛选标签
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dashed;

  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.clay
              : dashed
                  ? Colors.transparent
                  : AppColors.card,
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: selected ? AppColors.clay : AppColors.lineStrong,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            color: selected ? Colors.white : AppColors.ink2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 里程碑 / 类型徽标
class AppBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.label,
    this.background = AppColors.pineLight,
    this.foreground = AppColors.pine,
    this.icon,
  });

  const AppBadge.pine(this.label, {super.key, this.icon})
      : background = AppColors.pineLight,
        foreground = AppColors.pine;

  const AppBadge.clay(this.label, {super.key, this.icon})
      : background = AppColors.clayLight,
        foreground = AppColors.clayDark;

  const AppBadge.gold(this.label, {super.key, this.icon})
      : background = AppColors.goldLight,
        foreground = const Color(0xFF8A6118);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: foreground,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.lineStrong),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.ink2, height: 1.6),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 宝宝头像：有照片显示照片，无照片显示手绘简笔婴儿脸。
///
/// 默认头像刻意用 [CustomPainter] 绘制而非首字文字——文字依赖字体族，
/// 在中文字体缺失或 fallback 失败时会渲染成方框/问号。
class BabyAvatar extends StatelessWidget {
  final BabyInfo baby;
  final double size;
  final double radius;
  final String? absolutePath;

  const BabyAvatar({
    super.key,
    required this.baby,
    this.size = 48,
    this.radius = 16,
    this.absolutePath,
  });

  @override
  Widget build(BuildContext context) {
    final path = (absolutePath ?? baby.avatarPath).trim();
    final palette = _AvatarPalette.of(baby.gender);

    Widget fallback = CustomPaint(
      size: Size.square(size),
      painter: _BabyFacePainter(palette),
    );

    if (path.isNotEmpty) {
      fallback = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: fallback),
    );
  }
}

/// 默认头像配色：按性别做轻微色相区分，整体仍在暖色系内。
class _AvatarPalette {
  final Color background;
  final Color face;
  final Color accent;
  final Color ink;

  const _AvatarPalette(this.background, this.face, this.accent, this.ink);

  factory _AvatarPalette.of(int gender) {
    switch (gender) {
      case 1: // 男孩：浅松绿
        return const _AvatarPalette(Color(0xFFE4EDE7), Color(0xFFFFFDFB),
            Color(0xFF2E5245), Color(0xFF2B2724));
      case 2: // 女孩：浅藕粉
        return const _AvatarPalette(Color(0xFFFAE7EC), Color(0xFFFFFDFB),
            Color(0xFFC4788F), Color(0xFF2B2724));
      default: // 未填：浅陶土
        return const _AvatarPalette(Color(0xFFF7E8E1), Color(0xFFFFFDFB),
            Color(0xFFBF5B3B), Color(0xFF2B2724));
    }
  }
}

class _BabyFacePainter extends CustomPainter {
  final _AvatarPalette p;

  const _BabyFacePainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final u = w < h ? w : h; // 以较短边为基准，保证非正方形也不变形

    // 底色
    canvas.drawRect(Offset.zero & size, Paint()..color = p.background);

    final cx = w / 2;
    final faceCenter = Offset(cx, h * 0.56);
    final faceR = u * 0.29;

    // 胎毛：先于脸绘制，被脸盖住根部，只在头顶露出一点，像一撮呆毛
    canvas.drawPath(
      Path()
        ..moveTo(cx - u * 0.070, h * 0.310)
        ..quadraticBezierTo(
            cx + u * 0.010, h * 0.130, cx + u * 0.070, h * 0.310),
      Paint()
        ..color = p.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.052
        ..strokeCap = StrokeCap.round,
    );

    // 脸
    canvas.drawCircle(faceCenter, faceR, Paint()..color = p.face);

    // 腮红：叠在脸上（若先于脸绘制会被完全遮住）
    final blush = Paint()..color = p.accent.withValues(alpha: 0.20);
    canvas.drawCircle(Offset(cx - u * 0.160, h * 0.690), u * 0.070, blush);
    canvas.drawCircle(Offset(cx + u * 0.160, h * 0.690), u * 0.070, blush);

    // 眼睛（婴儿比例：眼睛位于脸部中线偏下）
    final eye = Paint()..color = p.ink;
    canvas.drawCircle(Offset(cx - u * 0.105, h * 0.585), u * 0.042, eye);
    canvas.drawCircle(Offset(cx + u * 0.105, h * 0.585), u * 0.042, eye);

    // 微笑
    canvas.drawPath(
      Path()
        ..moveTo(cx - u * 0.072, h * 0.678)
        ..quadraticBezierTo(cx, h * 0.745, cx + u * 0.072, h * 0.678),
      Paint()
        ..color = p.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.034
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BabyFacePainter old) => old.p != p;
}

/// 统一的行内图标按钮，保证 44 命中区
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final String? tooltip;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color = AppColors.ink2,
    this.tooltip,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: 44,
      height: 44,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Icon(icon, size: size, color: color),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// 顶部返回条：左返回 + 标题 + 右操作
class PageTopBar extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool showBack;

  const PageTopBar({
    super.key,
    required this.title,
    this.trailing,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.xs, 4, AppSpace.xs, AppSpace.sm),
      child: Row(
        children: [
          if (showBack)
            AppIconButton(
              icon: Icons.arrow_back_ios_new,
              size: 18,
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
