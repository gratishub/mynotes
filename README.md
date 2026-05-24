# mynotes

离线图文日记应用 —— 基于 Flutter + ObjectBox + Riverpod 构建。

## 技术栈

| 组件 | 用途 |
|------|------|
| Flutter 3.44+ | 跨平台 UI 框架 |
| ObjectBox | 本地 NoSQL 数据库 (Local-First) |
| Riverpod | 响应式状态管理 |
| path_provider | 文件系统路径管理 |

## 项目结构

```
lib/
├── main.dart                   # 应用入口
├── models/                     # 数据实体
│   ├── tag.dart                # 标签
│   ├── post.dart               # 日记帖子
│   └── image_meta.dart         # 图片元数据
└── services/
    └── objectbox_store.dart    # 数据库单例 (CRUD)
```

## 数据模型关系

```
Post ──ToMany── Tag         (多对多)
Post ──ToMany── ImageMeta   (一对多, 反向引用)
```

## 环境要求

- Flutter SDK 3.44+
- Java 21 (OpenJDK)
- Android SDK 36 + BuildTools 28.0.3

## 快速开始

```bash
# 安装依赖
flutter pub get

# 生成 ObjectBox 代码 (修改实体后需重新运行)
dart run build_runner build

# 运行分析
flutter analyze

# 运行应用
flutter run
```

## 构建 APK

### Debug 构建

```bash
flutter build apk --debug
```

构建产物位置：`build/app/outputs/flutter-apk/app-debug.apk`

### Release 构建

```bash
flutter build apk --release
```

构建产物位置：`build/app/outputs/flutter-apk/app-release.apk`

> Release 构建需要配置签名密钥，详见 `internal/KEYS.md`（如存在）。

## 在安卓设备上调试

### 前置条件

1. 手机开启 **开发者选项** 和 **USB 调试**
   - 设置 → 关于手机 → 连续点击"版本号"7 次
   - 设置 → 系统 → 开发者选项 → 打开 USB 调试
2. USB 数据线连接手机到电脑
3. 手机上允许 USB 调试授权

### 运行调试

```bash
# 检查设备是否识别
flutter devices

# 启动调试（自动 build + 安装 + 启动）
flutter run
```

### 调试常用命令

| 按键 | 功能 |
|------|------|
| `r` | 热重载（刷新 UI，保留状态） |
| `R` | 热重启（重启应用） |
| `q` | 退出调试 |
| `h` | 查看所有快捷键 |

## 网络镜像配置（中国大陆）

由于网络限制，在中国大陆构建时推荐配置国内镜像：

| 镜像 | 用途 |
|------|------|
| `pub.flutter-io.cn` | Dart 包镜像 |
| `storage.flutter-io.cn` | Flutter 引擎 / 构件镜像 |
| `mirrors.cloud.tencent.com/gradle` | Gradle 发行版镜像 |
| `maven.aliyun.com/repository/public` | Maven 依赖镜像 |
| `maven.aliyun.com/repository/google` | Google Maven 镜像 |
| `maven.aliyun.com/repository/gradle-plugin` | Gradle 插件镜像 |

配置方式参考 `internal/SETUP.md`（如存在）。

## FAQ

构建和调试过程中遇到的常见问题见 [FAQ.md](./FAQ.md)。

## 开发约定

- 软删除：帖子删除使用 `isDeleted` 标记，支持回收站功能
- 单例模式：ObjectBoxStore 全局只有一个数据库实例
- 标签名称唯一，插入重复名称会触发异常
