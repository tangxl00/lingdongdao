# Quantumult X 重写脚本 —— Floaty Unlock

用 Quantumult X（或 Loon / Surge）**在网络层改写 RevenueCat 的响应**，把 Floaty 的
Pro 权益改成「永久有效」。**不用改 App 二进制、不用重签、不用越狱** —— 原版
Floaty 从 App Store 正常安装即可。

---

## 1. 原理

Floaty 的付费判定链是 RevenueCat SDK：

```
CustomerInfo.entitlements[requiredEntitlementIdentifier].is_active
```

`entitlements` 整个由服务端 JSON 下发，客户端只读不算 → **在响应里把它改掉即可**。

脚本改写内容：

| 字段 | 原值 | 改后 |
|---|---|---|
| `entitlements.<id>.is_active` | `false` | `true` |
| `entitlements.<id>.expires_date` | 具体日期 | `2099-12-31T23:59:59Z` |
| `entitlements.<id>.will_renew` | `true`/`false` | `false` |
| `entitlements.<id>.verification` / `verification_data` | 存在 | 删除 |
| `active_entitlements` | `[]` | 填入全部权益 ID |
| HTTP 404（未注册用户） | 404 | 200 + 合成一份「已注册 + 永久有效」 |

**不会改的**：`/v1/products`、`/v1/offerings` —— App 还要用它们显示套餐列表，
改了会让付费页变形。

---

## 2. 文件

```
unlock/qx/
  floaty_qx.js        改写脚本本体（QX 的 script-response-body）
  rewrite.conf        重写规则（订阅 → 重写）
  test_floaty_qx.js   Node 单测（模拟 $response 环境跑脚本）
```

---

## 3. 配置步骤（Quantumult X）

### 3.1 安装 MITM 证书

设置 → **HTTPS 解密** → 证书 → 安装 → 打开「完全信任」。

### 3.2 开启 MITM 域名

在重写规则里声明要解密的域名（QX 需要这个才能看到明文）：

```
[MITM]
hostname = api.revenuecat.com
```

### 3.3 导入重写规则

**订阅 → 重写 → 右上角「+」→ 新建重写**，把 `rewrite.conf` 的内容粘进去。

如果用「资源文件」方式管理（推荐，方便自动更新）：

```
[rewrite]
^https?:\/\/api\.revenuecat\.com\/v1\/subscribers\/.*$ url script-response-body https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.js, requires-body=true, tag=floaty-unlock
^https?:\/\/api\.revenuecat\.com\/v1\/customer\/.*$ url script-response-body https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.js, requires-body=true, tag=floaty-unlock
^https?:\/\/api\.revenuecat\.com\/v1\/subscribers$ url script-response-body https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.js, requires-body=true, tag=floaty-unlock
```

> `requires-body=true` 是关键：没有它 QX 不会把响应体交给脚本。

### 3.4 生效

1. QX → 开关打开「重写」和「HTTPS 解密」。
2. **完全退出 Floaty 再重开**（App 启动时会拉一次订阅状态）。
3. 打开 App 的 Pro 功能看是否已解锁。

---

## 4. 验证

QX → 订阅 → **活动**（Activity）里能看到 `api.revenuecat.com` 的记录，
点进去看 Response，`is_active` 应为 `true`。

---

## 5. 与 dylib 注入方案的区别

仓库里有两套方案，可任选其一，也可叠加：

| | QX 重写脚本 | dylib 注入 |
|---|---|---|
| 需要越狱 | 否 | 是（TrollStore / ldid） |
| 需要重签 | 否 | 是 |
| 需要改 App | 否 | 是（59 字节 LC_LOAD_DYLIB） |
| 需要电脑常开代理 | 是 | 否 |
| 覆盖范围 | 只改网络响应 | 改 App 内部（含离线缓存判定） |

**推荐**：有 TrollStore 就用 dylib（一次装好，不用挂代理）；没有就用 QX 脚本。

> 另有一份 **mitmproxy 插件版**（`unlock/mitm/floaty_unlock.py`），功能等价，
> 适合在电脑上做中间人代理调试。

---

## 6. 常见问题

**Q：App 还是显示要付费。**
- 检查 QX「活动」里有没有 `api.revenuecat.com` 的记录。没有 → MITM 域名没配或证书没信任。
- 有记录但 body 没变 → 规则没匹配到（检查是不是 `http://` 而不是 `https://`），或 `requires-body=true` 漏了。

**Q：重开后 Pro 图标还在付费页。**
- 完全 kill App 再开（不是切后台）。
- Floaty 会缓存 CustomerInfo 到磁盘，必要时删 App 重装一次。

**Q：会不会影响别的 App。**
- 规则只匹配 `api.revenuecat.com`，别的 App 走 RevenueCat 也会被改（对 Floaty 无影响）。

---

## 7. 免责

本工具用于在你自己的设备上、对自己拥有的 App 做安全研究与互操作性测试。
请勿用于分发破解版或侵犯他人权益。
