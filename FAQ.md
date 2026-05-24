# FAQ — 构建与调试常见问题

## 目录

1. [Gradle 下载失败 / 网络超时](#1-gradle-下载失败--网络超时)
2. [Maven 依赖下载失败](#2-maven-依赖下载失败)
3. [Dart SDK 版本过旧](#3-dart-sdk-版本过旧)
4. [flutter_tools.snapshot 不兼容](#4-flutter_toolssnapshot-不兼容)
5. [Flutter 包下载超时 (pub.dev)](#5-flutter-包下载超时-pubdev)
6. [SDK 路径含空格导致构建失败](#6-sdk-路径含空格导致构建失败)
7. [Kotlin 增量编译缓存损坏](#7-kotlin-增量编译缓存损坏)
8. [磁盘空间不足](#8-磁盘空间不足)
9. [Kotlin Gradle Plugin (KGP) 兼容性警告](#9-kotlin-gradle-plugin-kgp-兼容性警告)
10. [Flutter 命令指向旧 SDK](#10-flutter-命令指向旧-sdk)

---

### 1. Gradle 下载失败 / 网络超时

**现象**：Gradle 构建卡住，提示 `services.gradle.org` 连接超时。

**原因**：中国大陆网络无法稳定访问 Gradle 官方发行服务器。

**解决**：更换 Gradle wrapper 为国内镜像。

修改 `android/gradle/wrapper/gradle-wrapper.properties`：

```properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-8.10-all.zip
```

推荐镜像：
- **腾讯云**：`https://mirrors.cloud.tencent.com/gradle/`
- **华为云**：`https://repo.huaweicloud.com/gradle/`

---

### 2. Maven 依赖下载失败

**现象**：Gradle 构建中大量 `Could not resolve dependency` 错误，指向 `repo.maven.apache.org` 或 `dl.google.com`。

**原因**：Google Maven 和 Maven Central 在中国大陆访问不稳定。

**解决**：在 Gradle 脚本中配置阿里云 Maven 镜像。

`android/settings.gradle.kts` — pluginManagement 内添加：

```kotlin
repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
    maven { url = uri("https://maven.aliyun.com/repository/public") }
    maven { url = uri("https://maven.aliyun.com/repository/google") }
    maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
}
```

`android/build.gradle.kts` — allprojects 内添加：

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
    }
}
```

---

### 3. Dart SDK 版本过旧

**现象**：`flutter pub get` 或 `dart run build_runner` 报错 `The current Dart SDK version is 3.5.0, but this package requires ^3.12.0`。

**原因**：Flutter SDK 版本过旧，内置 Dart SDK 版本不够。

**解决**：更新 Flutter SDK 到最新稳定版。

```bash
# 切换到稳定分支并更新
git checkout stable
git pull

# 确认 Dart SDK 版本
dart --version
# 应为 Dart 3.12+ (Flutter 3.44+)
```

如果无法使用 `flutter upgrade`，可以手动切换 Flutter 的 git 分支：

```bash
cd <flutter-sdk-path>
git fetch --all --tags
git checkout tags/<latest-stable-tag>
```

---

### 4. flutter_tools.snapshot 不兼容

**现象**：运行 `flutter` 命令时出现 `Error: Snapshot not compatible` 或类似错误。

**原因**：Dart SDK 更新后，旧版的 `flutter_tools.snapshot` 与新 Dart VM 不兼容。

**解决**：删除旧 snapshot 并重新生成。

```bash
# 删除旧 snapshot
rm <flutter-sdk>/bin/cache/flutter_tools.snapshot

# 用新 Dart SDK 重新编译
dart --disable-dart-dev \
     --snapshot=<flutter-sdk>/bin/cache/flutter_tools.snapshot \
     --snapshot-kind=app-jit \
     <flutter-sdk>/packages/flutter_tools/bin/flutter_tools.dart

# 清理缓存后重新运行
flutter clean
```

---

### 5. Flutter 包下载超时 (pub.dev)

**现象**：`flutter pub get` 卡住或超时，无法从 `pub.dev` 下载依赖。

**原因**：中国大陆网络无法稳定访问 pub.dev。

**解决**：配置 PUB 镜像。

```bash
# 设置环境变量
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

---

### 6. SDK 路径含空格导致构建失败

**现象**：构建过程中出现 `'D:\\Program' 不是内部或外部命令` 或 `native assets` 相关错误，报错指向路径中 `Program Files (x86)` 带空格。

**原因**：Flutter 3.44+ 的 native assets 系统在调用 Dart SDK 时未正确处理含空格的路径，导致 `dart.exe` 路径被截断。

**解决**：将 Flutter SDK 和 Android SDK 迁移到不含空格的路径。

```bash
# 复制 SDK 到无空格路径
cp -r "D:\Program Files (x86)\flutter" "D:\sdk\flutter"
cp -r "D:\Program Files (x86)\android-sdk" "D:\sdk\android"

# 配置 Flutter 使用新路径
flutter config --android-sdk D:\sdk\android

# 更新环境变量
export FLUTTER_ROOT=D:\sdk\flutter
export ANDROID_HOME=D:\sdk\android
```

> 注：Windows 目录符号链接 (junction) 和 8.3 短文件名 (`PROGRA~2`) 对此问题均无效，必须使用不含空格的路径。

---

### 7. Kotlin 增量编译缓存损坏

**现象**：构建失败，错误包含 `Could not close incremental caches` 和 `this and base files have different roots`，指向插件源码路径（如 Pub 缓存）与项目根路径不一致。

**原因**：Kotlin 增量编译缓存记录了依赖的绝对路径（例如 pub 缓存目录），当 Gradle、Kotlin 版本或 SDK 路径发生变化时，这些缓存路径与当前项目根路径匹配失败。

**解决**：

```bash
# 1. 清理构建目录
flutter clean

# 2. 停止所有 Gradle/Kotlin 守护进程
# 在 Windows 上:
taskkill /F /IM java.exe

# 3. 在 android/gradle.properties 中禁用增量编译
echo "kotlin.incremental=false" >> android/gradle.properties

# 4. 重新构建
flutter build apk --debug
```

---

### 8. 磁盘空间不足

**现象**：Gradle 构建过程中出现 `java.io.IOException: 磁盘空间不足` 或 `ENOSPC: no space left on device`，错误可能出现在 `CompressAssetsWorkAction`、依赖下载等多个环节。

**原因**：Gradle 和 Kotlin 编译会占用大量磁盘缓存，C 盘空间不足时构建失败。

**解决**：

**方法一：配置 Gradle 用户目录到其他盘**

```bash
# 设置环境变量，将 Gradle 缓存迁移到其他盘
export GRADLE_USER_HOME=D:\sdk\.gradle
```

**方法二：清理 C 盘**

```bash
# Windows 磁盘清理
cleanmgr

# 或手动清理 Gradle 缓存
rm -rf C:\Users\<用户名>\.gradle\caches
```

**方法三：减小 JVM 内存分配**

在 `android/gradle.properties` 中降低内存限制：

```properties
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G
```

---

### 9. Kotlin Gradle Plugin (KGP) 兼容性警告

**现象**：构建输出出现警告：
```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
image_picker_android, objectbox_flutter_libs
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

**原因**：Flutter 3.44+ 开始内置 Kotlin 支持（Built-in Kotlin），插件通过 KGP 直接应用 Kotlin 的方式即将被弃用。

**影响**：当前构建正常，不影响功能。未来 Flutter 版本会强制要求插件迁移到 Built-in Kotlin。

**解决**：等待相关插件（`image_picker_android`、`objectbox_flutter_libs`）发布支持 Built-in Kotlin 的版本，然后更新插件。

---

### 10. Flutter 命令指向旧 SDK

**现象**：`flutter doctor` 输出警告：
```
! Warning: `flutter` on your path resolves to <旧路径>, which is not inside your current Flutter SDK checkout at <新路径>.
```

**原因**：PATH 环境变量仍指向旧的 Flutter SDK 路径，但你当前使用的是另一个路径的 Flutter SDK。

**解决**：更新 PATH 环境变量，移除旧 Flutter SDK 路径，添加新路径。

```bash
# 编辑 shell 配置文件，将旧路径替换为新路径
export PATH="<新flutter-sdk>/bin:$PATH"
```

在 Windows 上：系统环境变量 → Path → 编辑指向新路径。
