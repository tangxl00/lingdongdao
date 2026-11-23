# 此刻（PickupCode / Floaty 开源版）

把**取件码、火车票、机票、待办**放进**锁屏 + 灵动岛 + 主屏小组件**：收到短信或邮件后自动识别成卡片，锁屏常驻显示，一键完成、一键复制。

本工程是 iOS 应用 **浮现 Floaty（com.enjoyio.floaty 1.1.0）** 的功能等价开源实现，**无订阅、无内购、无付费墙**。

- **主路径（第一章）**：本地 Xcode + 免费 Apple ID 真机编译安装 —— 不需要付费开发者账号
- **备选附录**：GitHub Actions 云端编译（仅验证可编译，产物不能直接安装）、付费账号增强（App Group / 一年签名）

---

## 第一章 · 本地 Xcode 编译安装（主路径）

适用环境：Mac（macOS 13 或更高）+ iPhone（iOS 17.0+；灵动岛需 iPhone 14 Pro 及以上机型，锁屏实时活动支持更多机型）。全程使用**免费 Apple ID**，无需付 99 美元。

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

本工程有两个 target：主 App（`PickupCode`）和扩展（`PickupCodeWidget`），**两个都要设置团队**：

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
3. 回到桌面打开 App，正常启动即安装完成。

### 1.8 立即验证（不配快捷指令也能测）

用 Safari 打开下面任意一条链接（可先复制到备忘录，长按 → 打开）：

```
floaty://show?kind=pickup&title=886677&station=菜鸟驿站&courier=顺丰&expiry=2026-10-18T22:00:00+08:00
floaty://show?kind=train&title=G9527&from=北京南&to=上海虹桥&departure=2026-10-24T14:30:00+08:00&seat=12A&car=05&gate=B12
floaty://show?kind=flight&title=CA9527&from=PEK&to=PVG&departure=2026-10-24T08:15:00+08:00&seat=32A&gate=C12&terminal=T3
floaty://show?kind=todo&title=取快递&note=放门口&due=2026-10-24T20:00:00+08:00
```

锁屏看板立即出现对应卡片。日常自动触发请按《快捷指令配置指南》（工程根目录 `SHORTCUTS.md`）配置。

### 1.9 关于 7 天有效期

免费 Apple ID 签名的 App **每 7 天过期**，过期后 App 打不开（锁屏活动也会随之消失）。处理方式：

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
| 锁屏没出现卡片 | 确认机型为 iPhone 14 Pro+；锁屏下拉通知中心查看；iOS 设置 → 本 App → 实时活动 已开启 |
| App 打不开（装了一周后） | 7 天签名到期，重新连接 Mac 编译（见 1.9） |

---

## 第二章 · 工程结构速览

```
PickupCode/
├── PickupCode.xcodeproj          # 工程定义（双 target）
├── PickupCodeKit/                # 主 App 与 Widget 共享的模型层（12 个文件）
│   ├── FloatyKind.swift          # 四类内容 + 看板过滤枚举
│   ├── FloatyItem.swift          # 内容实体 + 清单子项
│   ├── FloatyDate.swift          # ISO8601 / 出发时间 / 剩余时间工具
│   ├── FloatyAttributes.swift    # 看板 Live Activity 属性 + 卡片模型
│   ├── FloatySettings.swift      # 显示 / 自动添加 / 看板 / 外观设置
│   ├── FloatyBoard.swift         # 看板过滤、排序、分页、页码/聚焦状态
│   ├── FloatyRepository.swift    # UserDefaults + Codable 持久化
│   ├── FloatyStorage.swift       # 存储常量与协议
│   ├── FloatyURL.swift           # floaty:// URL 契约解析
│   ├── RecognitionTemplate.swift # 识别模板 + 12 条内置正则
│   ├── RecognitionEngine.swift   # 本机正则识别引擎
│   └── ProAccess.swift           # 能力开关（恒为免费，无付费墙）
├── PickupCodeApp/                # 主 App target（13 个文件）
│   ├── FloatyApp.swift           # @main 入口 + scenePhase 对账
│   ├── FloatyAppDelegate.swift   # 主屏快捷方式（UIApplicationShortcutItems）
│   ├── FloatyStore.swift         # 全局状态中心（ObservableObject）
│   ├── ContentView.swift         # 「此刻」列表 + 空态引导 + URL 处理
│   ├── AddItemView.swift         # 四类内容的添加表单
│   ├── HistoryView.swift         # 历史记录（复制 / 删除 / 完成 / 清空）
│   ├── SettingsView.swift        # 设置（显示 / 看板 / 自动添加 / 模板 / 外观）
│   ├── TemplatesView.swift       # 识别模板管理与样例测试
│   ├── RecognitionTestView.swift # 识别测试台
│   ├── BoardActivityManager.swift # 锁屏看板 Live Activity 启停与刷新
│   ├── AutoAddEngine.swift       # 短信 / 邮件 / 通知 / 剪贴板自动添加
│   ├── ReminderScheduler.swift   # 待办截止提醒 + 每日取件提醒
│   ├── FloatyIntents.swift       # 19 个 App Intents + 5 个快捷指令短语
│   └── Assets.xcassets / Info.plist / PickupCodeApp.entitlements
├── PickupCodeWidget/             # Widget Extension target（3 个文件）
│   ├── PickupCodeWidgetBundle.swift # @main 入口
│   ├── BoardLiveActivity.swift   # 锁屏看板 + 灵动岛布局
│   ├── FloatyWidget.swift        # 主屏小组件
│   └── Assets.xcassets / Info.plist / PickupCodeWidget.entitlements
├── scripts/verify_project.mjs    # 工程静态一致性自检（node 运行）
├── SHORTCUTS.md                  # 快捷指令配置指南
└── ../.github/workflows/build.yml # 附录 A 云端编译
```

数据流：短信 / 邮件 → 快捷指令调 `RecognizeTextIntent`（或 `floaty://add?text=`）→ `RecognitionEngine` 本机正则匹配 → `FloatyRepository` 入库 → `BoardActivityManager` 刷新锁屏看板 Live Activity → 锁屏 / 灵动岛 / 小组件渲染 → 点"完成"深链 `floaty://done?id=...` 回主 App 更新状态。

### URL 契约

```
floaty://show?kind=<pickup|todo|train|flight>&title=<主标题>&station=<地点>&courier=<快递公司>
              &from=<起点>&to=<终点>&departure=<ISO8601>&arrival=<ISO8601>&expiry=<ISO8601>
              &seat=<座位>&car=<车厢>&gate=<检票口/登机口>&terminal=<航站楼>&note=<备注>
floaty://done?id=<UUID>
floaty://add?text=<原始文本>&source=<sms|mail|notification|clipboard>
```

- 兼容旧契约 `pickupcode://show?code=...&station=...`
- 时间字段接受 ISO 8601 与 Unix 秒/毫秒时间戳；非法值忽略
- `floaty://add` 走自动识别链路（命中模板才入库）

### App Intents 一览（19 个）

| 分类 | Intent |
| --- | --- |
| 添加 | `ComposeAttentionIntent(kind)`、`AddPickupCodeIntent`、`AddTodoIntent`、`AddTrainTicketIntent`、`AddFlightTicketIntent`、`ComposePickerIntent` |
| 识别 | `RecognizeTextIntent(text, shortcutID, shortcutVersion, mode)`、`RecognizeTextListIntent(texts[], …)` |
| 看板 | `ShowLockScreenBoardIntent(kinds, filter)`、`HideLockScreenBoardIntent(kinds)`、`DismissBoardIntent`、`PageHomeBoardListIntent(delta)`、`FocusHomeBoardIntent(delta)`、`FocusAttentionIntent(delta)`、`ComposeControlIntent(show)` |
| 完成 | `CompleteAttentionIntent`、`CompleteBoardItemIntent(itemID)`、`CompletePickupLineIntent(itemID)`、`CheckChecklistLineIntent(entryID, itemID)`、`CheckBoardChecklistLineIntent(entryID, itemID)` |

App 快捷指令短语（`FloatyShortcuts`）：添加取件码 / 添加待办 / 添加火车票 / 添加机票 / 识别文本。

---

## 第三章 · 关于付费：永久免费

本工程**没有付费墙、没有订阅、没有内购**。

逆向 Floaty 1.1.0 可确认其付费模型为 RevenueCat（`PaywallPresenter` / `presentPaywallIfNeeded` / `requiredEntitlementIdentifier` / `CustomerInfo.entitlements`），**唯一被付费墙拦截的能力是「短信与邮件自动添加」**（原版文案：「Manual adding and Lock Screen display are always free.」「Upgrade to Floaty Pro to add items automatically.」）。

本工程把这层判定收敛到单点 `ProAccess`：

```swift
enum ProAccess {
    static let isPro: Bool = true        // 恒为 true
    static let autoAddEnabled: Bool = true
    static let showsPaywall: Bool = false
}
```

同时**整块删除**了 RevenueCat SDK 与 StoreKit 依赖（工程内零第三方二进制依赖）。手动添加、锁屏与灵动岛展示、模板管理等能力与原版一致，全部免费。

---

## 附录 A · GitHub Actions 云端编译（备选，非主路径）

仓库根 `.github/workflows/build.yml` 保留：push 到 main 或手动触发时在 macOS runner 上先跑 `node PickupCode-v2/PickupCode/scripts/verify_project.mjs` 静态自检，再做**无签名**编译验证并上传未签名 archive 产物。

- 用途：验证代码可编译，不需要任何 Mac 与证书。
- 限制：产物**未签名，不能装进 iPhone**；如需真机安装仍走第一章本地编译。

## 附录 B · 付费开发者账号增强（可选）

99 美元/年的 Apple Developer Program 可解锁（**全部为可选项**，免费方案已有兜底）：

1. **一年有效期签名**：编译安装后 App 一年不用重签。
2. **App Group 数据共享**：主 App 与 Widget 真正共享存储，锁屏"完成"状态实时同步（免费账号靠深链唤起主 App 同步，效果接近）。启用步骤：
   - 两个 target 的 Signing & Capabilities → `+ Capability` → 各加 **App Groups** → 勾选/新建 `group.com.yourteam.pickupcode`（名字与代码中一致）；
   - 在 https://developer.apple.com/account 的 Identifiers 里为两个 App ID 勾选 App Groups 能力。

## 附录 C · 已知限制

- 免费账号签名 7 天有效，需定期重连 Mac 编译（数据不丢）。
- 灵动岛仅 iPhone 14 Pro 及以上机型；其他机型走锁屏实时活动。
- Live Activity 系统展示上限约 8 小时。
- 通知自动添加依赖系统级能力，iOS 17~26 需通过快捷指令读取通知内容实现；本工程预留了 `notification` 来源与 Intent 参数。
- App Group 相关状态同步在免费账号下采用启发式对账，不影响核心展示功能。
