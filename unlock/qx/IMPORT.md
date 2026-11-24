# 一键导入 —— 复制下面这一行到 Quantumult X 就能用

> 本文是 `unlock/qx/` 的**最短操作路径**。想了解原理和排错看
> [`README.md`](README.md)。

---

## 一、你要复制的那一行

QX → **订阅 → 资源 → 右上角「+」**，类型选 **rewrite**，资源路径填下面
**任意一个**（三个都是实测可用的镜像，选延迟低的那个）：

```
https://gcore.jsdelivr.net/gh/tangxl00/lingdongdao@main/unlock/qx/floaty_qx.resource.conf
```

```
https://fastly.jsdelivr.net/gh/tangxl00/lingdongdao@main/unlock/qx/floaty_qx.resource.conf
```

```
https://ghproxy.net/https://raw.githubusercontent.com/tangxl00/lingdongdao/main/unlock/qx/floaty_qx.resource.conf
```

保存 → 点进这个资源 → **更新** → 拉到左边出现**绿色对勾**才算成功。

> **为什么不用 raw.githubusercontent.com**
> 2026-11-24 本机实测：`raw.githubusercontent.com` 和 `cdn.jsdelivr.net`
> 都返回 `000`（连不上），`ghfast.top` 25 秒超时。
> 上面列的三条是实测**返回 200 且内容逐字节一致**（SHA256 校验）的。
> 你手机的网络环境可能不同，如果这三条也不通，把域名换成
> `raw.githubusercontent.com` 试直连即可（文件路径不变）。

---

## 二、这个资源文件做了什么

它会自动帮你配好两件事，**不用手工粘规则**：

### 1. `[MITM]` 段 —— 声明要解密的域名

```ini
[MITM]
hostname = api.revenuecat.com, api.revenuecat.biz
```

### 2. `[rewrite]` 段 —— 一条正则覆盖三种接口

```ini
^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$) url script-response-body https://gcore.jsdelivr.net/gh/tangxl00/lingdongdao@main/unlock/qx/floaty_qx.js, requires-body=true, max-size=131072, tag=floaty-unlock
```

| 覆盖的接口 | 说明 |
|---|---|
| `/v1/subscribers/<id>` | 新版 SubscriberResponse（**Pro 判定入口**） |
| `/v1/customer/<id>` | 旧版 CustomerInfo |
| `/v1/subscribers[?query]` | 注册流程 POST |

| 参数 | 作用 | 漏了会怎样 |
|---|---|---|
| `requires-body=true` | 让 QX 把响应体交给脚本 | 脚本拿到空 body，什么都不改 |
| `max-size=131072` | 允许 128KB 响应体 | 大响应被截断 → `JSON.parse` 失败 |
| `(\/\|\?\|$)` | 兜住「有 query / 有尾斜杠 / 直接结束」 | 带 query 的 URL 匹配不到 |
| 正则**不含** `products`/`offerings` | 保住付费页套餐列表 | 套餐列表显示不出来 |

---

## 三、还差三步（资源文件管不到的部分）

资源文件只配规则，下面三件事必须你手动做：

### 1. 装证书并**信任**

QX → **设置 → HTTPS 解密 → 证书 → 生成证书 → 安装证书**

然后去系统 **设置 → 通用 → 关于本机 → 证书信任设置**，
把 `Quantumult X` 的开关**打开**。

> 只装描述文件不打开这个开关 = 所有 HTTPS 解不开。
> 现象：QX 活动里有连接记录，但看不到明文 body。
> 这是 iOS 17+ 最常踩的坑。

### 2. 打开两个总开关

QX → **设置 → HTTPS 解密** → 开关打开
QX 首页 → **重写** → 开关打开

### 3. 完全杀掉 Floaty 再重开

上滑杀掉（不是切后台），再打开。Floaty 启动时会拉一次订阅状态。

---

## 四、确认成功

**看 QX**：活动 → 点 `api.revenuecat.com` 记录 → Response

```json
"is_active": true,
"expires_date": "2099-12-31T23:59:59Z"
```
（并且没有 `verification` 字段）

**看 App**：Floaty 设置页从「升级到 Pro」变成
**「已是浮现会员 / You're on Floaty Pro」**，
「短信自动添加」「邮件自动添加」开关变成可打开。

---

## 五、镜像自检（可选）

在你的电脑或手机终端跑一下，能返回 `200` 且 1970 字节就说明镜像正常：

```bash
curl -sI https://gcore.jsdelivr.net/gh/tangxl00/lingdongdao@main/unlock/qx/floaty_qx.resource.conf | head -1
```

实测记录（2026-11-24）：

| 镜像 | 状态 | 耗时 | 大小 | SHA256 对比本地 |
|---|---|---|---|---|
| gcore.jsdelivr.net | 200 | 1.25s | 1970B | 一致 ✅ |
| fastly.jsdelivr.net | 200 | 2.11s | 1970B | 一致 ✅ |
| ghproxy.net | 200 | 2.69s | 1970B | 一致 ✅ |
| jsdelivr 上的 `floaty_qx.js` | 200 | 1.15s | 5133B | 一致 ✅ |

镜像上的脚本也实际跑过一遍（拿真实 RevenueCat 响应喂进去）：
`is_active=true`、`expires_date=2099`、`verification` 已删、
`active_entitlements=["pro","floaty_pro"]`、`request_date` 未被动。

---

## 六、更新规则

资源文件用 `@main` 引用（不是固定 commit），所以仓库更新后
在 QX 里**点一下该资源的「更新」**就能拿到新版，不用改配置。
