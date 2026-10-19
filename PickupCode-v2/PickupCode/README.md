# 取件码灵动岛 App（PickupCode）

把快递取件码变成**灵动岛 + 锁屏实时活动（Live Activity）**：收到取件短信后，快捷指令自动唤起本 App，取件码以大号字常驻灵动岛与锁屏，一键复制、一键"已取件"，超过 8 小时自动消失。

- **主路径（第一章）**：本地 Xcode + 免费 Apple ID 真机编译安装 —— 不需要付费开发者账号
- **备选附录**：GitHub Actions 云端编译（仅验证可编译，产物不能直接安装）、付费账号增强（App Group / 一年签名）

---

## 第一章 · 本地 Xcode 编译安装（主路径）

适用环境：Mac（macOS 13 或更高）+ iPhone（iOS 16.1+；灵动岛需 iPhone 14 Pro 及以上机型，锁屏实时活动支持更多机型）。全程使用**免费 Apple ID**，无需付 99 美元。

### 1.1 安装 Xcode

1. 打开 Mac 上的 App Store，搜索 **Xcode**，安装（约 10GB+，需要一些时间）。
2. 安装完成后启动一次 Xcode，同意许可协议；如提示安装"additional components"，点 **Install**。
3. 验证：终端执行 `xcodebuild -version`，能看到 `Xcode 15.x`（或更高）即成功。

> 若 App Store 下载太慢，也可在 Apple Developer 网站下载 `.xip` 安装包：https://developer.apple.com/download/applications/ （用免费 Apple ID 登录即可下载，不需要付费账号）。

### 1.2 解压并打开工程

1. 把 `PickupCode.zip` 解压（双击即可），得到 `PickupCode` 文件夹。
2. 打开 `PickupCode` 文件夹，双击 **`PickupCode.xcodeproj`**，Xcode 会自动打开工程。

### 1.3 添加免费 Apple ID 开发者账号

1. Xcode 菜单栏：**Xcode → Settings…（或 Preferences）→ Accounts** 标签页。
2. 点左下角 **`+`** → 选 **Apple ID** → 登录你的 Apple ID（就是手机上用的那个）。
3. 登录后，右侧会显示一行你的账号，"Team" 一栏显示为 **你的姓名 (Personal Team)**——这就是免费的开发者团队。

### 1.4 给两个 target 选择开发团队

本工程有两个 target：主 App（`PickupCode`）和灵动岛扩展（`PickupCodeWidget`），**两个都要设置团队**：

1. 点 Xcode 左侧顶部的工程名 **PickupCode**（蓝色图标）进入工程设置页。
2. 中栏 **TARGETS** 列表选 **PickupCode** → 顶部 **Signing & Capabilities** 标签。
3. 勾选 **Automatically manage signing**。
4. **Team** 下拉框选择你的 **Personal Team（你的姓名）**。
   - 如果出现 "Failed to register bundle identifier" 报错：说明 `com.yourteam.pickupcode` 这个标识被别人占用了，把 Bundle Identifier 改成你自己的（见 1.5）。
5. 回到 TARGETS 列表选 **PickupCodeWidget** → 同样勾选 **Automatically manage signing** → **Team** 选同一个 Personal Team。
   - 若同样报 identifier 占用，按 1.5 把 widget 的 Bundle Identifier 一起改掉。

### 1.5 （仅当报错时）修改 Bundle Identifier

默认标识是 `com.yourteam.pickupcode`（主 App）和 `com.yourteam.pickupcode.widget`（扩展）。若报"identifier 不可用"，改成你自己的唯一标识，例如：

- 主 App：`com.你的名字.pickup2026`
- 扩展：`com.你的名字.pickup2026.widget`（保持 ".widget" 后缀，且前缀与主 App 一致）

改法：TARGETS → 选 target → Signing & Capabilities → Bundle Identifier 输入框直接改。

### 1.6 连接 iPhone 并编译安装

1. 用数据线把 iPhone 连到 Mac，首次连接在手机上点 **信任此电脑**。
2. iPhone 上：**设置 → 隐私与安全性 → 开发者模式**（如果没有这一项，跳过；连接 Xcode 编译一次后会出现）→ 打开（需重启手机）。
3. 回到 Xcode：顶部工具栏 scheme 选 **PickupCode**，旁边的设备选择器选你的 **iPhone**（而不是模拟器）。
4. 按 **`⌘R`**（或点左上角 ▶ 运行）。首次编译签名时 Xcode 可能会弹窗提示"未受信任的开发者"，这是正常的。

### 1.7 手机上信任开发者

首次安装后，App 图标点开会提示"不受信任的开发者"，需要：

1. iPhone **设置 → 通用 → VPN与设备管理**。
2. 找到你的 **Apple ID 开发者描述文件**，点 **信任**。
3. 回到桌面打开取件码 App，正常启动即安装完成。

### 1.8 验证灵动岛（可选，立即可测）

不配置快捷指令也能立刻验证：用 Safari 打开下面这条链接（可先复制到备忘录，长按 → 打开）：

```
pickupcode://show?code=886677&station=菜鸟驿站&courier=顺丰&expiry=2026-10-18T22:00:00+08:00
```

灵动岛/锁屏立即出现取件码 886677。日常自动触发请按《快捷指令配置指南》（工程根目录 `SHORTCUTS.md`）配置。

### 1.9 关于 7 天有效期

免费 Apple ID 签名的 App **每 7 天过期**，过期后 App 打不开（灵动岛活动也会随之消失）。处理方式：

- 到期前后把手机连上 Mac，重新按 1.6 按 `⌘R` 编译一次即可，数据（历史记录）保留在手机本地不受影响。
- 每台设备最多同时装 3 个免费签名的 App，重新编译不会占用新名额。
- 若希望一年签一次（99 美元/年 开发者账号），见附录 C——**这不是必需的**。

### 1.10 常见报错速查

| 报错/现象 | 原因与处理 |
| --- | --- |
| `Failed to register bundle identifier` | 标识被占用，按 1.5 改 Bundle Identifier |
| `Signing for "PickupCodeWidget" requires a development team` | 只给主 App 设了团队；按 1.4 给 widget 也设上 |
| 手机上点开 App 提示"不受信任" | 按 1.7 信任描述文件 |
| 编译报 `Unsupported Swift version` / 工具链错误 | Xcode 版本太旧，升级到 15.0+ |
| `iPhone is busy / preparing debugger` | 等几分钟再运行；手机保持解锁 |
| 灵动岛没出现 | 确认机型为 iPhone 14 Pro+；锁屏下拉通知中心查看锁屏卡片；iOS 设置 → 取件码 App → 实时活动 已开启 |
| App 打不开（装了一周后） | 7 天签名到期，重新连接 Mac 编译（见 1.9） |

---

## 第二章 · 工程结构速览

```
PickupCode/
├── PickupCode.xcodeproj          # 工程定义（双 target）
├── PickupCodeKit/                # 主 App 与 Widget 共享的模型层
│   ├── PickupCodeAttributes.swift   # ActivityKit 静态属性/ContentState
│   ├── PickupCode.swift             # 取件码实体 + 日期工具
│   └── PickupCodeStoreProtocol.swift# 存储常量与协议
├── PickupCodeApp/                # 主 App target
│   ├── PickupCodeApp.swift       # 入口：onOpenURL / scenePhase 对账
│   ├── ContentView.swift         # 当前取件码卡片 + 空态引导
│   ├── HistoryView.swift         # 历史列表（复制/删除/已取件/清空）
│   ├── HistoryStore.swift        # UserDefaults + Codable 历史存储
│   ├── LiveActivityManager.swift # ActivityKit 启动/更新/结束 + 超时兜底
│   ├── URLSchemeHandler.swift    # pickupcode:// URL 解析与校验
│   ├── Assets.xcassets / Info.plist / PickupCodeApp.entitlements
├── PickupCodeWidget/             # Widget Extension target
│   ├── PickupCodeWidgetBundle.swift  # @main 入口
│   ├── PickupCodeLiveActivity.swift  # ActivityConfiguration 定义
│   ├── DynamicIslandViews.swift      # 灵动岛四区域布局
│   ├── LockScreenView.swift         # 锁屏/横幅布局
│   ├── Assets.xcassets / Info.plist / PickupCodeWidget.entitlements
├── SHORTCUTS.md                 # 快捷指令配置指南
└── .github/workflows/ios-build.yml  # 附录 A 云端编译
```

数据流：短信 → 快捷指令组装 `pickupcode://show?...` URL → 唤起主 App → `URLSchemeHandler` 校验 → `HistoryStore` 入库 → `LiveActivityManager` 启动 Live Activity → 灵动岛/锁屏展示（Widget Extension 渲染）→ 点"已取件"深链 `pickupcode://done?code=...` 回主 App 结束。

URL 契约（唯一接口定义）：

```
pickupcode://show?code=<取件码>&station=<驿站名>&courier=<快递公司>&expiry=<ISO8601>&note=<备注>
```

- `code` 必填（空则静默忽略）；`station` 缺省为"未知驿站"；`expiry` 非法则忽略、已过期仍展示并橙色警示
- 长度限制：code ≤ 20、station ≤ 50、courier ≤ 20、note ≤ 100，超长截断
- 兼容容错：`carrier` 亦被接受（作为 `courier`）；`expire` 接受 Unix 秒/毫秒时间戳（作为 `expiry`）

---

## 附录 A · GitHub Actions 云端编译（备选，非主路径）

工程内 `.github/workflows/ios-build.yml` 保留：push 到 main 或手动触发时在 macOS runner 上做**无签名**编译验证，并上传构建日志与未签名 archive 产物。

- 用途：验证代码可编译，不需要任何 Mac 与证书。
- 限制：产物**未签名，不能装进 iPhone**；如需真机安装仍走第一章本地编译。
- 使用：把整个 `PickupCode/` 目录（含 `.github/`）推到 GitHub 仓库即可自动触发。

## 附录 B · 付费开发者账号增强（可选）

99 美元/年的 Apple Developer Program 可解锁（**全部为可选项**，免费方案已有兜底）：

1. **一年有效期签名**：编译安装后 App 一年不用重签。
2. **App Group 数据共享**：主 App 与 Widget 真正共享存储，灵动岛"已取件"状态实时同步（免费账号靠深链唤起主 App 同步，效果接近）。启用步骤：
   - 两个 target 的 Signing & Capabilities → `+ Capability` → 各加 **App Groups** → 勾选/新建 `group.com.yourteam.pickupcode`（名字与代码中一致）；
   - 在 https://developer.apple.com/account 的 Identifiers 里为两个 App ID 勾选 App Groups 能力。

## 附录 C · 已知限制

- 免费账号签名 7 天有效，需定期重连 Mac 编译（数据不丢）。
- 灵动岛仅 iPhone 14 Pro 及以上机型；其他机型走锁屏实时活动。
- Live Activity 系统展示上限约 8 小时（App 内有超时兜底与对账逻辑）。
- App Group 相关状态同步在免费账号下采用启发式对账，极端情况（如手动划掉灵动岛）会被记为"已取件"，不影响核心展示功能。
