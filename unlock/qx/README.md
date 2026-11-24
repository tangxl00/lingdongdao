# Quantumult X 重写脚本 —— Floaty Unlock

> **这是没有越狱设备时的推荐路线。**
> 不需要改 App、不需要重签、不需要电脑常开代理 —— 在你的 iPhone 上装个
> Quantumult X，把规则导进去就行。原版 Floaty 从 App Store 正常装。

---

## 0. 为什么这条路适合你

| 方案 | 要越狱 | 要重签 | 要电脑常开 | 能在普通 iPhone 上用 |
|---|---|---|---|---|
| **QX 重写（本文）** | ❌ | ❌ | ❌ | ✅ |
| mitmproxy（电脑做代理） | ❌ | ❌ | ✅ 必须 | ✅ 但要一直挂电脑 |
| dylib 注入 | ✅ 必须 | ✅ 必须 | ❌ | ❌ **不行** |

dylib 路线在普通设备上走不通，原因很硬：原版 entitlements 里的
`group.com.enjoyio.floaty` 绑死在开发者团队 `9GAL39B66Y` 下，你自己签名申请不到
这个 App Group → Live Activity / 灵动岛 / 小组件全部失效（也就是把核心功能废了）。
只有 TrollStore / ldid 假签能保住，而两者都需要越狱。

所以：**普通 iPhone → 用 QX 重写（本文）**。

---

## 1. 原理

Floaty 的付费判定完全由 RevenueCat 服务端下发的 JSON 决定：

```
Purchases.configure(apiKey)
  → GET https://api.revenuecat.com/v1/subscribers/{app_user_id}
  → CustomerInfo.entitlements[requiredEntitlementIdentifier].isActive
  → PaywallPresenter.presentPaywallIfNeeded()      ← 弹付费墙
```

`entitlements` 整个是服务端给的，客户端只读不算 → **在响应里改掉它就行**。

改写内容：

| 字段 | 原值 | 改后 |
|---|---|---|
| `entitlements.<id>.is_active` | `false` / 不存在 | `true` |
| `entitlements.<id>.expires_date` | 具体日期 / `null` | `2099-12-31T23:59:59Z` |
| `entitlements.<id>.will_renew` | `true`/`false` | `false` |
| `entitlements.<id>.verification` / `verification_data` | 存在 | **删除**（关键） |
| `active_entitlements` | `[]` | 填入全部权益 ID |
| HTTP 404（用户没注册） | 404 | 200 + 合成一份「已注册 + 永久有效」 |

**为什么要删 verification**：RevenueCat 的 enforced 模式会用服务端签名校验权益载荷，
我们改过 JSON 后签名必然对不上 → SDK 反而把 `isActive` 压回 `false`。
删掉这两个字段，SDK 退回「不校验」的行为。

**不会碰的**：`/v1/products`、`/v1/offerings` —— App 还要用它们显示套餐列表，
改了会让付费页变形。

---

## 2. 文件

```
unlock/qx/
  floaty_qx.js           改写脚本本体（QX 的 script-response-body）
  rewrite.conf           重写规则（[MITM] 段 + [rewrite] 段）
  test_floaty_qx.js      脚本单测（Node 模拟 $response 环境）
  test_rewrite_regex.js  正则匹配表测试（从 rewrite.conf 读规则来测）
```

本地跑测试：

```bash
node unlock/qx/test_floaty_qx.js        # 24 项
node unlock/qx/test_rewrite_regex.js    # 18 项
```

---

## 3. 配置步骤（一步一步照做）

### 3.1 装 Quantumult X

App Store 搜 **Quantumult X**（付费 App，¥7.99 左右）。
替代品：**Loon**、**Surge**、**Shadowrocket**（都支持 `script-response-body`，
规则写法略有差异，见本文末尾）。

### 3.2 安装并信任根证书

1. QX 底部 → **设置** → **HTTPS 解密** → **证书** → **生成证书**
2. 点 **安装证书** → 系统会跳到「设置」→ 允许下载描述文件
3. 系统 **设置 → 通用 → VPN 与设备管理** → 点刚下载的描述文件 → **安装**
4. **关键，很多人漏这步**：系统 **设置 → 通用 → 关于本机 → 证书信任设置**
   → 找到 `Quantumult X` → **把开关打开**（完全信任）
5. 回 QX → **设置 → HTTPS 解密** → 把 **总开关打开**

> iOS 17+ 必须在第 4 步手动打开信任开关。只装不信任 = 所有 HTTPS 都解不开，
> QX「活动」里能看到连接但看不到明文 body。

### 3.3 配置 MITM 域名

QX → **设置 → HTTPS 解密 → MITM 主机名**，加入：

```
api.revenuecat.com
api.revenuecat.biz
```

（`rewrite.conf` 的 `[MITM]` 段里已经写好了，如果用资源文件方式导入会自动带上。）

### 3.4 导入重写规则

**方式 A：手动粘贴（最快）**

QX → **订阅 → 重写 → 右上角「+」→ 新建重写**，把 `rewrite.conf` 里
`[rewrite]` 段的那一行粘进去。

**方式 B：资源文件引用（推荐，能自动更新）**

QX → **订阅 → 资源 → 右上角「+」**，填：

```
类型: rewrite
资源路径: https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/rewrite.conf
```

### 3.5 确认规则真的生效

规则长这样（关键参数都标出来了）：

```
^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$) url script-response-body https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.js, requires-body=true, max-size=131072, tag=floaty-unlock
```

两个**必须**有的参数：

| 参数 | 不加的后果 |
|---|---|
| `requires-body=true` | QX 不把响应体交给脚本，脚本拿到空 body → 什么都不改 |
| 正则里的 `(\/|\?|$)` | 只写 `/v1/subscribers$` 的话，带 query 的 URL 匹配不到 |

### 3.6 生效

1. QX 里确认 **重写** 和 **HTTPS 解密** 两个开关都开着
2. **完全退出 Floaty**（上滑杀掉，不是切后台）再重开
3. 打开 Floaty → 设置页看会员状态

---

## 4. 怎么确认成功了

### 看 QX 活动日志

QX → **活动** → 找 `api.revenuecat.com` 的记录 → 点进去看 **Response**：

- `is_active` 应该是 `true`
- `expires_date` 应该是 `2099-12-31T23:59:59Z`
- 没有 `verification` 字段

### 看 App 本身

Floaty 设置页应该从「升级到 Pro」变成 **「已是浮现会员 / You're on Floaty Pro」**，
并且「短信自动添加」「邮件自动添加」开关变成可打开状态。

---

## 5. 排错

| 症状 | 原因 | 处理 |
|---|---|---|
| QX 活动里**没有** `api.revenuecat.com` 记录 | MITM 域名没加，或 HTTPS 解密没开 | 回到 3.3 / 3.2-5 |
| 有记录但 Response 看不到 JSON | 证书没**信任**（只装了描述文件） | 回到 3.2-4，打开证书信任开关 |
| Response 是明文但 `is_active` 还是 `false` | 规则没匹配上 | 检查 `requires-body=true`；检查正则有没有 `(\/\|\?\|$)` |
| 规则匹配上了但 App 没变 | Floaty 把 CustomerInfo 缓存到磁盘了 | 完全杀 App 重开；不行就删 App 重装（重装后配置仍在 QX 里） |
| 付费页套餐列表空了 | 不该改的 `/v1/products` 被改了 | 确认规则里**没有**匹配 products/offerings |
| 改完 App 反而报订阅错误 | verification 没删干净 | 确认 `floaty_qx.js` 是最新版（含 `delete ent.verification`） |

---

## 6. 其他客户端（Loon / Surge / Shadowrocket）

脚本逻辑完全一样（`$response.body` / `$response.statusCode` 是三家通用的），
只是规则文件格式不同：

**Loon**（`[Rewrite]` 段）：

```
^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$) url script-response-body https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.js
```

**Surge**（`.sgmodule`）：

```
[Script]
floaty-unlock = type=http-response,pattern=^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$),requires-body=1,max-size=131072,script-path=https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.js
```

**Shadowrocket**（`[Script]` 段）：

```
[Script]
http-response ^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$) script-path=https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.js, requires-body=true, max-size=131072, tag=floaty-unlock
```

三家都需要在各自的 MITM 设置里加 `api.revenuecat.com` 并安装/信任证书。

---

## 7. 和另外两条路线的关系

| | QX 重写 | mitmproxy 插件 | dylib 注入 |
|---|---|---|---|
| 适合谁 | **普通 iPhone** | 有电脑可挂 | 越狱 / TrollStore |
| 要改 App | 否 | 否 | 是 |
| 要重签 | 否 | 否 | 是 |
| 要额外设备 | 否 | 要一台常开的电脑 | 否 |
| 离线可用 | 否（要联网拉订阅） | 否 | 是 |

三者改写的 JSON 内容**完全一致**（同一套字段、同一个 `2099` 日期、同样删 verification），
只是拦截位置不同：QX 在手机本地、mitmproxy 在电脑、dylib 在 App 进程内。

---

## 8. 说明

本工具用于在你自己的设备上、对自己拥有的 App 做安全研究与互操作性测试。
请勿用于分发破解版或侵犯他人权益。
