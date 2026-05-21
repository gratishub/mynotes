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

## 开发约定

- 软删除：帖子删除使用 `isDeleted` 标记，支持回收站功能
- 单例模式：ObjectBoxStore 全局只有一个数据库实例
- 标签名称唯一，插入重复名称会触发异常