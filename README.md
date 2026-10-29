# 小脚印成长记（Little Footprint）

本地优先、局域网手动同步的宝宝成长记录 App。**仅限夫妻两台安卓手机使用，无云端、无外网访问、无第三方服务。**

- 记录：照片（压缩图参与同步）、录音（AAC，参与同步）、短视频（仅本机，不同步）、文字日记、标签、身高/体重/头围。
- 首页：按「今天 / 昨天 / 本周 / 本月 / 更早」分组的时间线，支持「全部 / 照片 / 录音 / 视频」筛选，自动计算宝宝月龄。
- 同步：两台手机连**同一个 WiFi**，手动输入对方 IP，通过 TCP（端口 `58888`）增量双向合并；冲突策略为“时间戳大者覆盖”，删除采用软删除。
- 备份：一键打包数据库 + 压缩媒体为 ZIP，保存到手机 Download 目录；原图/原视频建议定期手动拷贝到移动硬盘。

---

## 技术栈

| 模块 | 方案 |
| ---- | ---- |
| 语言/框架 | Flutter（纯安卓） |
| 本地数据库 | sqflite（SQLite） |
| 媒体压缩 | `image`（JPEG 预览图）、`record`（AAC 录音）、`video_player`（播放） |
| 局域网通信 | `dart:io` Socket（TCP）+ `network_info_plus` |
| 图表 | `fl_chart` |
| 备份 | `archive`（ZIP） |

## 目录结构

```
D:\PeachProject\
├── pubspec.yaml                    依赖清单
├── analysis_options.yaml           静态分析配置
├── android\app\src\main\AndroidManifest.xml   安卓权限（需覆盖到生成壳中）
└── lib\
    ├── main.dart                   入口，预初始化数据库
    ├── theme.dart                  全局主题（奶油白 + 松石绿）
    ├── models\                     5 张表的数据模型
    ├── db\app_database.dart        SQLite 建表 + 全部 CRUD
    ├── utils\                      月龄计算、时间线分组
    ├── services\                   媒体管理 / 局域网同步 / ZIP 备份
    ├── widgets\                    时间线卡片、媒体预览、标签流、音频播放器
    └── pages\                      启动/宝宝信息/时间线/新增/详情/媒体浏览/成长档案/同步/设置
```

---

## 快速开始

> 前置：已安装 Flutter SDK（含 Android 工具链）。

本项目只提供了 `lib/` 源码与 `pubspec.yaml`，**未包含安卓原生壳**（android 目录仅有一个权限清单）。请先在项目根目录执行：

```bash
flutter create --platforms=android --org com.yourfamily --project-name little_footprint .
```

> 说明：`flutter create` 会生成完整的 `android/` 壳工程。生成后**用本项目 `android/app/src/main/AndroidManifest.xml` 覆盖同名文件**，以获得局域网同步所需的全部权限。

然后安装依赖并运行：

```bash
flutter pub get
flutter analyze      # 静态检查
flutter run          # 连接安卓设备或模拟器运行
```

两台手机安装同一份 APK 后：
1. 首次启动各设置一次「宝宝信息 + 本机身份（爸爸/妈妈）」。
2. 一方在「局域网同步」页点【开启同步服务】。
3. 另一方输入对方 IP，点【连接并开始同步】。
4. 完成后各自刷新首页即可看到合并后的记录。

---

## 数据流与关键设计

### 同步协议（端口 58888）
1. 客户端 TCP 连接服务端。
2. 双方交换 `changeset`（基于上次同步时间戳的增量，含软删除标记）。
3. 各自对比 UUID：
   - 对方有、本机无 → 拉取记录 + 压缩媒体；
   - 双方都有 → 保留 `last_modify_ts` 更大的版本；
   - 对方标记删除 → 本地软删除。
4. 文件传输前以 MD5 去重。
5. 完成后双方写入 `sync_log`，记录本次同步时间，作为下次增量起点。

### 媒体分流
- 录音：完整参与同步（存 `records/compressed/`）。
- 照片：生成长边 1200px 压缩预览图参与同步；原图保留在手机相册，不复制进 App。
- 视频：MVP 仅保存在本机（`records/origin/`，`is_origin=1`，不参与跨机同步）。

---

## 已知限制（重要）

1. **本机未安装 Flutter/Dart，本项目代码未经过 `flutter analyze` / 编译验证**，仅通过括号与 import 静态校验。请在装有 Flutter 的机器上运行 `flutter pub get && flutter analyze` 并按提示修正。
2. **同步协议为 MVP 骨架实现**，未在真实双机环境联调，可能存在报文时序细节需微调。首次联调建议先传输少量数据验证。
3. MVP 使用**手动输入对方 IP** 连接；自动扫描局域网设备为二期功能。
4. 视频不跨机同步、无外网访问、无后台自动同步、无冲突人工选择——均为方案定稿时的主动取舍。
5. `saveToGallery`、`exportBackupZip` 使用公共目录路径，不同安卓版本对公共目录的写权限可能有差异，如遇问题需按 `permission_handler` 回调动态处理。

---

## 二期迭代候选

- 自动检测家庭 WiFi 并提醒同步
- 冲突双副本保留 + 人工选择
- 局域网设备自动扫描
- 相册合集 / “去年今日” / 疫苗台账
