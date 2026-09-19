# 用 ADB 在手机上测试 App —— 完整说明

> 生成时间：2026-09-13 12:15 GMT+8
> 项目：APU Auto Signer（包名 `com.apu.apu_auto_signer`）

---

## 一、ADB 是什么

**ADB = Android Debug Bridge（安卓调试桥）**

它是一个命令行工具，让你的**电脑通过数据线（或 WiFi）直接指挥手机**。

你可以把它理解成一根"智能数据线"：通过它，电脑可以给手机下命令——
装 App、卸载 App、看运行日志、传文件、截图、模拟点击，等等。

它属于 Android SDK 的 `platform-tools`，你的电脑里已经装好了：
- 位置：`C:\Users\gayso\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- 版本：`1.0.41 (36.0.2)`

---

## 二、"用 adb 在手机上测试"是什么意思

意思是：**不用手动把 APK 传到手机上点击安装**，而是电脑用数据线连上手机，
敲一行命令，App 就自动装好并且跑起来了。

和"手动拷贝 APK"相比的好处：

| | 手动拷贝 APK | 用 adb |
|---|---|---|
| 安装方式 | 传到手机 → 文件管理器点安装 | 电脑一行命令 |
| 看日志 | 看不到 | 实时看得到（出问题能直接定位） |
| 改代码见效 | 要重新构建 + 重新传 | 热重载，秒级生效 |
| 调试 | 困难 | 可以打断点、单步 |

所以开发阶段大家都用 adb，效率高很多。

---

## 三、完整操作步骤

### 第 1 步：手机开启「开发者选项」和「USB 调试」

1. 打开手机 **设置 → 关于手机**
2. 连续点击 **"版本号"** 7 次 → 提示"你已进入开发者模式"
3. 返回 **设置 → 系统 → 开发者选项**
4. 打开 **"USB 调试"** 开关
5. （部分手机还需要打开 **"USB 安装"**）

> 不同品牌路径略有差异：
> - 小米：设置 → 我的设备 → 全部参数 → 连点 MIUI 版本
> - 华为：设置 → 关于手机 → 连点版本号
> - 三星：设置 → 关于手机 → 软件信息 → 连点版本号

### 第 2 步：数据线连接电脑

用数据线把手机插到电脑上。手机屏幕会弹出：

> **"是否允许 USB 调试？"**
> 指纹：XXXX

勾选 **"始终允许使用这台计算机进行调试"** → 点 **允许**。

### 第 3 步：验证连接

```powershell
adb devices
```

正常会显示：
```
List of devices attached
1A2B3C4D        device
```

**注意看最后那个状态词：**

| 状态 | 含义 | 怎么办 |
|------|------|--------|
| `device` | ✅ 正常 | 继续 |
| `unauthorized` | ⚠️ 手机还没点"允许" | 看手机屏幕点允许；或 `adb kill-server` 再 `adb devices` |
| `offline` | ⚠️ 连接异常 | 重新插拔数据线，或换根线 |
| （空白） | ❌ 没检测到 | 检查驱动/数据线/是否开了 USB 调试 |

### 第 4 步：装 App / 运行

**方式 A —— 开发调试（推荐）**

```powershell
cd "C:\Users\gayso\Desktop\APU Auto Signer"
flutter run -d <设备ID>
```

如果只插了一台手机，直接 `flutter run` 就行，它会自动选。

特点：装上去 + 自动打开 + 实时日志 + **热重载**（改代码按 `r` 立即生效）。

**方式 B —— 安装已经构建好的 APK**

```powershell
adb install -r "build\app\outputs\flutter-apk\app-release.apk"
```

- `-r` = replace，覆盖安装（保留数据）
- 如果报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，先卸载：`adb uninstall com.apu.apu_auto_signer`

---

## 四、常用 ADB 命令速查

```powershell
adb devices                          # 列出已连接设备
adb install -r app.apk               # 安装/覆盖安装
adb uninstall com.apu.apu_auto_signer # 卸载
adb logcat                           # 看实时日志（Ctrl+C 退出）
adb logcat *:E                       # 只看 Error 级别
adb logcat | Select-String "apu"     # 只看含关键词的日志
adb shell                            # 进入手机命令行
adb pull /sdcard/xx.txt .            # 从手机拉文件到电脑
adb push xx.txt /sdcard/             # 从电脑推文件到手机
adb reboot                           # 重启手机
```

---

## 五、无线调试（不想插线时用）

Android 11+ 支持：

1. 手机 开发者选项 → **无线调试** → 打开
2. 手机和电脑连**同一个 WiFi**
3. 手机上点"使用配对码配对设备"，会显示 IP + 端口 + 配对码
4. 电脑执行：
```powershell
adb pair <手机IP>:<配对端口>      # 输入配对码
adb connect <手机IP>:<调试端口>
```
之后 `adb devices` 就能看到无线设备了。

---

## 六、你现在的情况

| 项目 | 状态 |
|------|------|
| adb 是否安装 | ✅ 已安装（platform-tools） |
| 当前是否有手机连接 | ❌ 没有（`adb devices` 为空） |
| App 包名 | `com.apu.apu_auto_signer` |

**下一步：** 插上手机 → 开 USB 调试 → 允许授权 → `adb devices` 看到设备 → 就能 `flutter run` 或 `adb install` 了。

---

## 七、一句话总结

> **adb = 电脑用命令行遥控手机的工具。**
> "用 adb 测试" = 数据线连手机，一条命令把 App 装上去并跑起来，同时能实时看日志。
> 比手动传 APK 快得多，是开发阶段的标准操作。

---

## 八、常见问题

### Q: 在 platform-tools 目录里敲 `adb` 提示 "not recognized"？

原因：**PowerShell 默认不从当前目录执行程序**，即使你就站在 adb.exe 旁边。

三种解法：
1. 加 `.\`：`\.\adb devices`
2. 用完整路径：`C:\Users\gayso\AppData\Local\Android\Sdk\platform-tools\adb.exe devices`
3. **（推荐，已配置）** 把 platform-tools 加进 PATH，然后**开新窗口**即可直接用 `adb`

> 环境变量只对**新开的**终端生效，旧窗口需重开。

### Q: PATH 里已经加了，老窗口还是不行？

环境变量改动不会影响已经打开的终端。关掉重开一个即可。
