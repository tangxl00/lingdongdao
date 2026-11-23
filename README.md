# lingdongdao · 此刻（Floaty 开源版）

把**取件码 / 火车票 / 机票 / 待办**放进锁屏、灵动岛和主屏小组件。

本工程是 iOS 应用 **浮现 Floaty（com.enjoyio.floaty 1.1.0）** 的功能等价开源实现：
逆向其二进制与 App Intents 元数据后，在同一套 Xcode 工程里重新实现了全部能力，
并**移除了 RevenueCat 订阅付费墙** —— 全部功能永久免费、无内购、无订阅。

- 工程目录：[`PickupCode-v2/PickupCode/`](PickupCode-v2/PickupCode)
- 快捷指令配置：[`PickupCode-v2/PickupCode/SHORTCUTS.md`](PickupCode-v2/PickupCode/SHORTCUTS.md)
- 编译安装说明：[`PickupCode-v2/PickupCode/README.md`](PickupCode-v2/PickupCode/README.md)
- 云端编译：`.github/workflows/build.yml`（push 到 `main` 自动跑无签名编译并上传 artifact）

## 功能一览

| 能力 | 说明 |
| --- | --- |
| 四类内容 | 取件码 / 待办（含清单子项）/ 火车票 / 机票 |
| 锁屏看板 | 锁屏 Live Activity 展示当前页卡片，支持翻页、聚焦切换、类型过滤（仅显示 / 排除） |
| 灵动岛 | 展开 / 紧凑 / 最小三种布局 |
| 主屏小组件 | 小 / 中 / 大三档尺寸速览「此刻」内容 |
| 自动添加 | 短信、邮件、通知、剪贴板、快捷指令 → 本机正则识别 → 自动入库 |
| 识别模板 | 内置 12 条正则模板（中英文取件码 / 火车 / 机票 / 待办），可增删改、可样例测试 |
| App Intents | 19 个 Intent（添加、识别、看板控制、翻页聚焦、完成、勾选子项），5 个语音/快捷指令短语 |
| 提醒 | 待办截止提醒 + 每日取件提醒 |
| 隐私 | 全部识别在本机完成，文本不上传、不联网 |

## 与 Floaty 的差异

| 项目 | Floaty | 本工程 |
| --- | --- | --- |
| 付费 | RevenueCat（Lifetime / Monthly / Yearly + 试用），**自动添加为 Pro 专属** | **无付费墙**，能力判定收敛到单点 `ProAccess.isPro`（恒为 `true`） |
| 依赖 | 静态链接 RevenueCat SDK + StoreKit | 无任何第三方二进制依赖，全部系统框架 |
| 购买 UI | Paywall / Customer Center / 恢复购买 | 无 |

其余能力（手动添加、锁屏与灵动岛展示、完成 / 复制 / 删除 / 排序 / 提醒 / 模板管理）本来就是免费的，本工程保持一致。

## 编译

- **本地**：见 [`PickupCode-v2/PickupCode/README.md`](PickupCode-v2/PickupCode/README.md) 第一章（免费 Apple ID 即可真机安装）。
- **云端**：push 到 `main` → GitHub Actions 自动 `xcodebuild archive`（无签名），artifact 名 `PickupCode-unsigned-ipa`。

## 许可

本仓库代码按 MIT 许可开源。Floaty 是一款独立商业应用，本工程为**独立实现**，不含其任何二进制、代码或素材。
