# 导入报「1 problem in sub-resource」怎么修

## 原因

QX 对**不同类型的资源**用**不同的解析器**，格式要求完全不同：

| 资源类型 | 文件内容 | 能不能有 `[rewrite]` 段头 | 能不能有 `[MITM]` 行 |
|---|---|---|---|
| `rewrite`（远程重写） | **纯规则行列表** | ❌ **不能** | ❌ **不能** |
| `filter`（分流规则） | 纯规则行列表 | ❌ | ❌ |
| 本地配置文件 `.conf` | 完整配置 | ✅ 必须 | ✅ 必须 |

之前那个文件里带了 `[MITM]` 和 `[rewrite]` 两个段头以及 `hostname =` 行 ——
那是**本地配置文件**的写法。当 QX 用 rewrite 解析器逐行读它时，
这三行都解析不了 → 正好报 **1 problem in sub-resource**。

已经修好了：现在 `floaty_qx.resource.conf` 只剩一条纯规则行。

---

## 修法（二选一）

### 方式 1：重拉资源（推荐）

QX → 订阅 → 资源 → 点进 `floaty_qx.resource.conf` 那条 → **更新**。

> CDN 有缓存。如果更新后还报同样的错，说明拿到的还是旧版（带段头的）。
> 强制刷新办法：把资源 URL 后面加个 `?v=2`，例如
> ```
> https://gcore.jsdelivr.net/gh/tangxl00/lingdongdao@main/unlock/qx/floaty_qx.resource.conf?v=2
> ```
> 这会让 CDN 当成新 URL 回源。

拉对之后：左边出现**绿色对勾**，右上角没有红字。

### 方式 2：手工粘规则（不依赖任何 CDN）

QX → **订阅 → 重写 → 右上角「+」→ 新建重写**，
把下面这一行粘进去，保存：

```
^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$) url script-response-body https://gcore.jsdelivr.net/gh/tangxl00/lingdongdao@main/unlock/qx/floaty_qx.js, requires-body=true, max-size=131072, tag=floaty-unlock
```

这条路径**完全不碰远程资源**，所以不会有 sub-resource 解析问题，最适合先跑通。

---

## 不管走哪条，MITM 域名都要手动配

这是因为远程 rewrite 资源里**不能**写 `[MITM]`。

QX → **设置 → HTTPS 解密 → MITM 主机名**，加：

```
api.revenuecat.com
```

（需要的话再加 `api.revenuecat.biz`）

---

## 完整的正确顺序

1. **装证书并信任**
   QX → 设置 → HTTPS 解密 → 证书 → 生成 → 安装
   → 系统 **设置 → 通用 → 关于本机 → 证书信任设置** → 打开 `Quantumult X` 开关

2. **配 MITM 域名**
   QX → 设置 → HTTPS 解密 → MITM 主机名 → `api.revenuecat.com`

3. **加规则**（方式 1 或方式 2 任选）

4. **开两个总开关**
   QX 设置 → HTTPS 解密 → 开
   QX 首页 → 重写 → 开

5. **完全杀掉 Floaty**（上滑，不是切后台）再打开

---

## 验证

QX → **活动** → 点 `api.revenuecat.com` 的记录 → **Response**：

```json
"is_active": true,
"expires_date": "2099-12-31T23:59:59Z"
```

并且**没有** `verification` 字段。

App 侧：Floaty 设置页从「升级到 Pro」变成
**「已是浮现会员 / You're on Floaty Pro」**。

---

## 如果还是报错

把 QX 报错截图里那行文字发我 —— `problem in sub-resource` 后面通常会跟
**具体是第几行 / 哪个字段**。我现在是按「段头不被接受」这个最可能的原因修的，
如果报的是别的（比如 `requires-body` 拼写、`max-size` 不被支持），
那就是另一处要改。
