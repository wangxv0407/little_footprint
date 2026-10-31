import '../models/milestone_def.dart';

/// 预置里程碑库。
///
/// 依据 ASQ-3 与国内儿保常规观察项整理，仅用于提醒家长「可以关注什么」，
/// 不作诊断依据。monthMin/monthMax 为常见达成区间，个体差异属正常。
const List<MilestoneDef> kMilestoneSeed = <MilestoneDef>[
  // ---------- 大运动 ----------
  MilestoneDef(code: 'mg_head_up', category: MilestoneCategory.motorGross, name: '俯卧抬头', monthMin: 0, monthMax: 3, sortOrder: 1),
  MilestoneDef(code: 'mg_roll', category: MilestoneCategory.motorGross, name: '第一次翻身', monthMin: 3, monthMax: 6, sortOrder: 2),
  MilestoneDef(code: 'mg_sit', category: MilestoneCategory.motorGross, name: '独立坐稳', monthMin: 5, monthMax: 9, sortOrder: 3),
  MilestoneDef(code: 'mg_crawl', category: MilestoneCategory.motorGross, name: '爬行', monthMin: 6, monthMax: 10, sortOrder: 4),
  MilestoneDef(code: 'mg_stand', category: MilestoneCategory.motorGross, name: '扶物站立', monthMin: 8, monthMax: 13, sortOrder: 5),
  MilestoneDef(code: 'mg_walk', category: MilestoneCategory.motorGross, name: '独立行走', monthMin: 9, monthMax: 17, sortOrder: 6),
  MilestoneDef(code: 'mg_squat', category: MilestoneCategory.motorGross, name: '蹲下再站起', monthMin: 12, monthMax: 20, sortOrder: 7),
  MilestoneDef(code: 'mg_run', category: MilestoneCategory.motorGross, name: '会跑', monthMin: 15, monthMax: 24, sortOrder: 8),
  MilestoneDef(code: 'mg_stairs', category: MilestoneCategory.motorGross, name: '自己上下楼梯', monthMin: 18, monthMax: 30, sortOrder: 9),
  MilestoneDef(code: 'mg_kick', category: MilestoneCategory.motorGross, name: '踢球', monthMin: 18, monthMax: 30, sortOrder: 10),
  MilestoneDef(code: 'mg_jump', category: MilestoneCategory.motorGross, name: '双脚跳', monthMin: 20, monthMax: 30, sortOrder: 11),

  // ---------- 精细动作 ----------
  MilestoneDef(code: 'mf_grasp', category: MilestoneCategory.motorFine, name: '主动抓握', monthMin: 3, monthMax: 6, sortOrder: 1),
  MilestoneDef(code: 'mf_transfer', category: MilestoneCategory.motorFine, name: '两手传递物品', monthMin: 6, monthMax: 10, sortOrder: 2),
  MilestoneDef(code: 'mf_pincer', category: MilestoneCategory.motorFine, name: '拇食指捏取', monthMin: 8, monthMax: 12, sortOrder: 3),
  MilestoneDef(code: 'mf_spoon', category: MilestoneCategory.motorFine, name: '自己用勺子', monthMin: 12, monthMax: 24, sortOrder: 4),
  MilestoneDef(code: 'mf_page', category: MilestoneCategory.motorFine, name: '自己翻书', monthMin: 12, monthMax: 24, sortOrder: 5),
  MilestoneDef(code: 'mf_scribble', category: MilestoneCategory.motorFine, name: '握笔涂鸦', monthMin: 14, monthMax: 24, sortOrder: 6),
  MilestoneDef(code: 'mf_blocks', category: MilestoneCategory.motorFine, name: '叠积木', monthMin: 15, monthMax: 28, sortOrder: 7),
  MilestoneDef(code: 'mf_dress', category: MilestoneCategory.motorFine, name: '自己穿脱衣物', monthMin: 24, monthMax: 48, sortOrder: 8),
  MilestoneDef(code: 'mf_scissors', category: MilestoneCategory.motorFine, name: '会用剪刀', monthMin: 30, monthMax: 48, sortOrder: 9),

  // ---------- 语言 ----------
  MilestoneDef(code: 'lg_coo', category: MilestoneCategory.language, name: '咿呀发声', monthMin: 2, monthMax: 6, sortOrder: 1),
  MilestoneDef(code: 'lg_mama', category: MilestoneCategory.language, name: '有意识叫爸妈', monthMin: 9, monthMax: 15, sortOrder: 2),
  MilestoneDef(code: 'lg_first_word', category: MilestoneCategory.language, name: '说出第一个词', monthMin: 10, monthMax: 18, sortOrder: 3),
  MilestoneDef(code: 'lg_body', category: MilestoneCategory.language, name: '指认身体部位', monthMin: 15, monthMax: 24, sortOrder: 4),
  MilestoneDef(code: 'lg_short', category: MilestoneCategory.language, name: '说三字短句', monthMin: 14, monthMax: 24, sortOrder: 5),
  MilestoneDef(code: 'lg_sentence', category: MilestoneCategory.language, name: '说完整句子', monthMin: 24, monthMax: 36, sortOrder: 6),
  MilestoneDef(code: 'lg_song', category: MilestoneCategory.language, name: '会唱简单儿歌', monthMin: 24, monthMax: 48, sortOrder: 7),

  // ---------- 社交 ----------
  MilestoneDef(code: 'so_smile', category: MilestoneCategory.social, name: '社会性微笑', monthMin: 1, monthMax: 4, sortOrder: 1),
  MilestoneDef(code: 'so_recognize', category: MilestoneCategory.social, name: '认人', monthMin: 5, monthMax: 9, sortOrder: 2),
  MilestoneDef(code: 'so_stranger', category: MilestoneCategory.social, name: '怕生', monthMin: 6, monthMax: 12, sortOrder: 3),
  MilestoneDef(code: 'so_bye', category: MilestoneCategory.social, name: '挥手再见', monthMin: 9, monthMax: 15, sortOrder: 4),
  MilestoneDef(code: 'so_clap', category: MilestoneCategory.social, name: '拍手', monthMin: 9, monthMax: 15, sortOrder: 5),
  MilestoneDef(code: 'so_imitate', category: MilestoneCategory.social, name: '模仿大人动作', monthMin: 12, monthMax: 24, sortOrder: 6),
  MilestoneDef(code: 'so_thanks', category: MilestoneCategory.social, name: '会说谢谢', monthMin: 18, monthMax: 36, sortOrder: 7),
  MilestoneDef(code: 'so_play', category: MilestoneCategory.social, name: '和小朋友一起玩', monthMin: 24, monthMax: 48, sortOrder: 8),

  // ---------- 认知 ----------
  MilestoneDef(code: 'cg_track', category: MilestoneCategory.cognition, name: '目光追视', monthMin: 2, monthMax: 5, sortOrder: 1),
  MilestoneDef(code: 'cg_search', category: MilestoneCategory.cognition, name: '寻找掉落物品', monthMin: 5, monthMax: 9, sortOrder: 2),
  MilestoneDef(code: 'cg_object', category: MilestoneCategory.cognition, name: '客体永久性', monthMin: 8, monthMax: 12, sortOrder: 3),
  MilestoneDef(code: 'cg_name', category: MilestoneCategory.cognition, name: '认识常见物品', monthMin: 12, monthMax: 24, sortOrder: 4),
  MilestoneDef(code: 'cg_color', category: MilestoneCategory.cognition, name: '按颜色分类', monthMin: 24, monthMax: 36, sortOrder: 5),
  MilestoneDef(code: 'cg_count', category: MilestoneCategory.cognition, name: '会数数', monthMin: 30, monthMax: 48, sortOrder: 6),
];
