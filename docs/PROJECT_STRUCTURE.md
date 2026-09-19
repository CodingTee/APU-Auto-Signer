# APU Auto Signer - 项目结构说明

> 本文档详细解释每个代码文件的职责和功能，帮助你理解 Flutter App 的文件结构。

---

## 📁 整体目录结构

```
lib/                          ← 所有 Dart 代码都在这里
├── main.dart                 ← 入口：启动 app、初始化数据库
├── models/                   ← 数据模型：定义"数据结构"
│   ├── student.dart
│   └── sign_in_result.dart
├── services/                 ← 业务逻辑：与外部服务通信
│   ├── auth_service.dart
│   ├── attendance_service.dart
│   └── database_service.dart
├── screens/                  ← 页面/界面：用户看到的每个屏幕
│   ├── home_screen.dart
│   ├── add_student_screen.dart
│   └── student_list_screen.dart
└── widgets/                  ← 组件：可复用的 UI 片段
    ├── student_tile.dart
    └── result_dialog.dart
```

---

## 🔑 核心文件说明

### main.dart — 程序入口
**职责：** 启动整个 App，初始化数据库，设置主题。

```
main()                         ← 第一个运行的函数
    ↓
初始化 SQLite 数据库           ← 打开数据库连接
    ↓
runApp(ApuAutoSignerApp())    ← 启动 Flutter UI
```

**做了什么：**
- 打开 `apu_auto_signer.db` 数据库
- 设置 Material 3 主题（蓝色系）
- 打开首页 HomeScreen

---

### models/ — 数据模型

#### student.dart — 学生账号模型
**职责：** 定义一个"学生账号"长什么样。

```dart
class Student {
  int? id;              // 数据库自增 ID
  String userId;        // 学号，如 "tp087051"
  String token;         // 考勤 Token（服务器给的"通行证"）
  String displayName;   // 显示名称
  DateTime createdAt;   // 何时添加
  DateTime? lastUsedAt; // 最后使用时间（可空）
  bool isActive;        // 是否启用
}
```

**关键点：** 这个文件只负责"定义数据结构"，不负责存取。

#### sign_in_result.dart — 签到结果模型
**职责：** 定义一次签到尝试的结果。

```dart
class SignInResult {
  SignInStatus status;  // 枚举：success / noClass / tokenExpired / networkError / unknownError
  String message;       // 给用户看的文字
  Map? classInfo;       // 成功时才有：班级、日期、时间等信息
}
```

---

### services/ — 业务逻辑层

#### auth_service.dart — 认证服务
**职责：** 处理登录认证流程。

```
用户操作          AuthService 做的事
───────────────────────────────
打开登录页   →   buildOAuthUrl()     生成微软登录 URL
用户登录后   →   extractCodeFromUrl()  从回调 URL 提取授权码
               exchangeCodeForToken()  用授权码换 Token
```

**关键点：** 只负责"换 Token"，不存储。

#### attendance_service.dart — 考勤服务
**职责：** 调用 APU 考勤 API 完成签到。

```dart
signIn(student, otp)        ← 单个学生签到
    ↓
发送 HTTP POST 到 https://attendix.apu.edu.my/graphql
    ↓
解析返回数据
    ↓
返回 SignInResult

batchSignIn(students, otp)  ← 多个学生并发签到
    ↓
Future.wait([signIn(s1), signIn(s2), ...])
    ↓
所有结果一起返回
```

**关键点：** 用 `Future.wait()` 实现真正的并发——所有学生同时签到，速度快。

#### database_service.dart — 数据库服务
**职责：** 用 SQLite 存储学生账号数据。

```
数据库表结构 students:
┌──────────┬──────────────┬─────────────────────────────┐
│ 字段名   │ 类型         │ 说明                         │
├──────────┼──────────────┼─────────────────────────────┤
│ id       │ INTEGER PK   │ 自增主键                     │
│ user_id  │ TEXT UNIQUE  │ 学号                         │
│ token    │ TEXT         │ 考勤 Token                   │
│ display_name │ TEXT   │ 显示名                       │
│ created_at │ TEXT     │ 添加时间                     │
│ last_used_at │ TEXT   │ 最后使用时间                 │
│ is_active │ INTEGER    │ 是否启用（1=启用）            │
└──────────┴──────────────┴─────────────────────────────┘

常用方法：
insertStudent()    ← 添加学生
getAllStudents()   ← 读取所有学生
updateToken()      ← 更新 Token（重新登录后）
deleteStudent()    ← 删除学生
```

**关键点：** Token 存储在本地 SQLite，不用每次都重新登录。

---

### screens/ — 页面层

#### home_screen.dart — 首页
**职责：** 用户每天使用的界面。

```
┌─────────────────────────────────┐
│  APU Auto Signer    [👤] [➕]  │  ← 顶栏（导航）
├─────────────────────────────────┤
│         Enter OTP Code          │
│            [ 1 2 3 ]            │  ← OTP 输入框（3位）
├─────────────────────────────────┤
│ Students (3/5)  [全选] [清空]   │  ← 学生选择区
│ ┌─────────────────────────────┐ │
│ │ ☑ TP01  张三                │ │  ← 可勾选的学生列表
│ │ ☑ TP02  李四                │ │
│ │ ☐ TP03  王五                │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│      [ ⚡ Sign In (3) ]         │  ← 一键签到按钮
└─────────────────────────────────┘
```

**做了什么：**
- 展示 OTP 输入框（只允许输入 3 位数字）
- 显示学生列表，支持勾选/取消勾选
- 点击"Sign In"后调用 `AttendanceService.batchSignIn()`
- 签到完成后弹出结果对话框

#### add_student_screen.dart — 添加学生页面
**职责：** 通过 WebView 让用户完成微软 OAuth 登录。

```
┌─────────────────────────────────┐
│ ✕ Add Student                  │  ← 关闭按钮
├─────────────────────────────────┤
│                                 │
│   ┌─────────────────────────┐   │
│   │  Microsoft 登录页面      │   │  ← WebView 内嵌浏览器
│   │  (用户输入邮箱密码)      │   │
│   │                          │   │
│   │  用户登录成功            │   │
│   │  → 跳转到 auth.apu.edu  │   │  ← 拦截这个 URL
│   │  → 提取 code            │   │
│   │  → 换 Token             │   │
│   │  → 保存到数据库          │   │
│   └─────────────────────────┘   │
│                                 │
│   状态: 正在交换 Token...       │  ← 状态提示
└─────────────────────────────────┘
```

**关键点：** WebView 拦截 `auth.apu.edu.my/auth_token?code=xxx`，静默完成 Token 交换。

#### student_list_screen.dart — 学生管理页面
**职责：** 查看、删除已保存的学生账号。

```
┌─────────────────────────────────┐
│  Manage Students                │
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ (T1) 张三    tp087051  [🗑] │ │  ← 头像、学号、删除
│ │      Last used: 2h ago      │ │
│ ├─────────────────────────────┤ │
│ │ (T2) 李四    tp087052  [🗑] │ │
│ │      Last used: 1d ago      │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

---

### widgets/ — 可复用组件

#### student_tile.dart — 学生列表项
**职责：** 一个可点击勾选的"学生卡片"。

```dart
StudentTile(
  student: student,       ← 显示哪个学生
  isSelected: true,       ← 是否被选中
  onTap: () => ...,       ← 点击时做什么
)
```

#### result_dialog.dart — 签到结果对话框
**职责：** 显示批量签到结果的弹窗。

```
✅ 3/5 Success           ← 汇总
├─ 张三  ✅ 签到成功        ← 可展开
│        Class: T1
│        Date: 2026-09-13
├─ 李四  ⚠️ 无课程          ← 颜色区分
└─ 王五  🔴 Token 失效      ← 需要重新登录
```

---

## 🔄 数据流向图

```
用户操作
    │
    ▼
screens/  (页面层)                    services/ (服务层)
───────────────                      ───────────────
用户输入 OTP                    ──→  AttendanceService
    │                                   signIn(student, otp)
勾选学生                            ──→  HTTP POST graphql
    │                                       ↓
点击"Sign In"                     ←  SignInResult
    │                                   │
    │                                   ▼
    │                              models/
    │                         SignInResult  ← 签到结果
    │                                   │
    ▼                                   ▼
显示结果弹窗 ◄─────────────────────── 返回
    │
    ▼
更新 last_used_at ──→ DatabaseService.updateLastUsed()

---

添加学生流程：
WebView 登录 ──→ 拦截 auth.apu.edu.my/auth_token ──→
extractCodeFromUrl() ──→ exchangeCodeForToken() ──→
insertStudent() ──→ 返回成功
```

---

## 📝 Flutter 项目结构规范

Flutter 有一个约定俗成的结构：

```
lib/
├── main.dart              ← 必须：入口文件
├── app.dart               ← 可选：App 配置（路由、主题等）
├── models/                ← 数据模型（对应后端的 Entity）
├── services/              ← 业务逻辑（对应后端的 Service）
├── repositories/          ← 数据访问（可选，介于 Model 和 DB 之间）
├── screens/               ← 页面/视图（对应后端的 Controller）
├── widgets/               ← 可复用 UI 组件（对应前端的 Component）
└── utils/ or helpers/     ← 工具函数
```

**为什么这样分？**
- **models/** — 只关心数据结构，不关心"怎么用"
- **services/** — 只关心"做什么"，不关心"怎么显示"
- **screens/** — 只关心"怎么显示"，不关心"怎么存"
- **widgets/** — 把 UI 拆成小积木，方便复用

这叫 **"关注点分离"（Separation of Concerns）**，是软件工程的核心原则。
