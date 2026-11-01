import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 录音面板：底部紧凑卡片，实时音浪 + 计时 + 停止。
///
/// [levels] 是最近若干次的归一化音量（0..1），由外部订阅
/// `AudioRecorder.onAmplitudeChanged` 后追加。
class AudioRecorderPanel extends StatelessWidget {
  final String timeText;
  final List<double> levels;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const AudioRecorderPanel({
    super.key,
    required this.timeText,
    required this.levels,
    required this.onStop,
    required this.onCancel,
  });

  static const _barCount = 40;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(
            color: Color(0x222B2724),
            blurRadius: 34,
            offset: Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: const BoxDecoration(
              color: AppColors.lineStrong,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
          Row(
            children: [
              const _PulseDot(),
              const SizedBox(width: 8),
              Text(
                '录音中',
                style: AppText.caption.copyWith(color: AppColors.ink2),
              ),
              const Spacer(),
              Text(
                timeText,
                style: const TextStyle(
                  fontFamily: AppFonts.serif,
                  fontFamilyFallback: AppFonts.serifFallback,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  letterSpacing: 0.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 15),
              GestureDetector(
                onTap: onCancel,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  '取消',
                  style: AppText.caption.copyWith(color: AppColors.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 54, child: _wave()),
          const SizedBox(height: 13),
          GestureDetector(
            onTap: onStop,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.clay,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44BF5B3B),
                    blurRadius: 16,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '停止录音',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wave() {
    // 对齐到最近 _barCount 条；不足时在左侧补 0，形成从左向右推进的观感
    final tail = levels.length > _barCount
        ? levels.sublist(levels.length - _barCount)
        : levels;
    final pad = _barCount - tail.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _barCount; i++) ...[
          if (i > 0) const SizedBox(width: 2.6),
          _bar(i < pad ? 0.0 : tail[i - pad], i),
        ],
      ],
    );
  }

  Widget _bar(double level, int index) {
    // 中间高、两端低的包络，视觉上更像真实声波
    final env = 0.3 + 0.7 * math.sin(index / (_barCount - 1) * math.pi);
    final h = 6.0 + (level.clamp(0.0, 1.0) * env) * 46;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      width: 3,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.clay.withValues(alpha: 0.55 + env * 0.45),
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}

/// 呼吸感的红点，表示正在录音
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.clay,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
