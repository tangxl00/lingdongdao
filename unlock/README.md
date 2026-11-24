# 浮现 (Floaty) 付费墙解锁

针对 **浮现 / Floaty（`com.enjoyio.floaty` v1.1.0）** 的订阅付费墙，提供两条解锁路线。

**原版 App 的功能与布局一个字节都不动**，只把"你是不是 Pro"这个判定改掉。

---

## 0. 结论先行：付费墙到底卡在哪

从二进制里挖出来的完整判定链（`E:\IPA_Analysis\REPORT\03-paywall.md`）：

```
Purchases.configure(apiKey)
      │
      ▼
CustomerInfo.entitlements[requiredEntitlementIdentifier].isActive
      │
      ▼
PaywallPresenter.presentPaywallIfNeeded()   ← 弹付费墙
```

| 能力 | 免费版 | Pro |
|---|---|---|
| 手动添加取件码 / 待办 / 火车票 / 机票 | ✅ | ✅ |
| 锁屏 Live Activity / 灵动岛 / 主屏小组件 | ✅ | ✅ |
| 提醒（到期提醒、每日提醒） | ✅ | ✅ |
| 识别模板管理（正则 + 命名捕获组） | ✅ | ✅ |
| 内置取件码识别 | ✅ | ✅ |
| **短信自动添加** | ❌ | ✅ |
| **邮件自动添加** | ❌ | ✅ |
| **通知自动添加**（需 iOS 27+） | ❌ | ✅ |
| **自建快捷指令自动添加** | ❌ | ✅ |

**没有条数/额度限制** —— 808 条本地化文案里找不到任何"免费 N 条"的说法。差异是纯功能开关。

所以解锁 = 让 `entitlements[...].isActive` 永远为 true。

---

## 1. 路线 A：MITM 改写（推荐，零改动，不用越狱）

**原理**：App 从 RevenueCat 服务器拉 `/v1/subscribers/{app_user_id}`，拿到的 JSON 里带每个权益的 `is_active` / `expires_date`。在链路层把这个 JSON 改成"永久有效"，App 读到的就是 Pro。

### 1.1 为什么这条路可行

- App **没有 TLS 证书钉死**：二进制明文里 `CertificatePinning` / `pinnedCert` / `TrustKit` / `serverTrust` / `publicKeyHash` 全部 0 命中。
- **不需要知道 entitlement / product ID**：直接改服务端返回的 `is_active` 即可。
- **必须一起摘掉 `verification` / `verification_data`**：RevenueCat 的服务端签名校验（enforced 模式）会把被改过的 JSON 判为失败，并把 `isActive` 压回 false。

### 1.2 用法

```bash
pip install mitmproxy

# 起代理（监听 8080）
mitmdump -s unlock/mitm/floaty_unlock.py --listen-port 8080
```

iPhone 侧：

1. Wi-Fi → 当前网络 → 代理 → 手动，填电脑 IP : 8080
2. Safari 打开 `http://mitm.it`，下载并**信任**证书（设置 → 通用 → VPN 与设备管理 → 信任；再设置 → 通用 → 关于本机 → 证书信任设置里打开）
3. 打开浮现，等它同步一次订阅状态
4. 回浮现设置页，应该显示**已是 Floaty Pro**（`You're on Floaty Pro`），自动添加开关也能打开

### 1.3 怎么确认真的生效了

插件会给每个被改写的响应加一个 `X-Floaty-Unlock` 请求头，并在终端打印命中统计。也可以在 mitmproxy 界面里直接看被改写后的 JSON（`is_active: true`、`expires_date: 2099-12-31T23:59:59Z`）。

### 1.4 插件行为细节

- 只改 `revenuecat.com` / `revenuecat.biz` 上 `/v1/subscribers`、`/v1/customer` 的响应。
- **不改** `/v1/products` / `/v1/offerings` —— 否则付费页的套餐列表会显示不出来。
- 同时处理三种响应外壳：顶层 flat、`subscriber`、`customer_info` / `subscriber_info`。
- 改写后重设 `Content-Length`、剥掉 `ETag` / `X-Signature`。

### 1.5 自测

```bash
python unlock/mitm/test_floaty_unlock.py   # 单元自测
python unlock/mitm/e2e_test.py             # 端到端（真起 mitmdump + 假 RevenueCat）
```

`fake_revenuecat.py` 是一个本地假 RevenueCat 服务，用来在没有真机的情况下验证改写逻辑。

---

## 2. 路线 B：注入 dylib（要越狱/TrollStore，可离线使用）

**原理**：不改网络，在 App 进程内 hook `NSURLSession`，把 RevenueCat 的响应体就地改写。

### 2.1 文件

| 文件 | 作用 |
|---|---|
| `unlock/dylib/FloatyUnlock.m` | 注入式 dylib 源码（Objective-C, ARC, arm64, iOS 17.0+） |
| `unlock/dylib/test_rewrite.m` | 逻辑单测 |
| `unlock/patcher/floaty_patcher.py` | Mach-O 补丁器：在头部空白插入 `LC_LOAD_DYLIB` |
| `unlock/patcher/test_floaty_patcher.py` | 补丁器单测 |

### 2.2 dylib 的四层拦截

RevenueCat 的 `CustomerInfo` / `EntitlementInfo` 都是 Swift struct，没有 ObjC 运行时元数据，没法直接 swizzle。所以拦在更下面一层 —— **URLSession 的响应体**：

| 层 | 拦截点 | 说明 |
|---|---|---|
| L1 | `-[NSURLSession dataTaskWithRequest:completionHandler:]` | 包一层 handler |
| L2 | `-[NSURLSession dataTaskWithURL:completionHandler:]` | 同上 |
| L3 | 运行时枚举所有类 → `URLSession:dataTask:didReceiveData:` | **只对 RevenueCat 的任务**先缓存，其余原样透传 |
| L4 | 运行时枚举所有类 → `URLSession:dataTask:didCompleteWithError:` | 改写后回放，再交回原实现 |

改写内容与路线 A 完全一致：`is_active=true`、`will_renew=false`、`expires_date=grace_period_expires_date=2099-12-31`、摘掉 `verification` / `verification_data`、填 `active_entitlements`。

### 2.3 为什么补丁能打在加密二进制上

原版主二进制和扩展都是 FairPlay 加密（`cryptid=1`），`__TEXT` 是密文，**代码一个字节都改不了**。但 Mach-O 的 **load commands 区在 `__TEXT` 之前**，而且那段是明文 padding：

```
主二进制 floaty:
  load commands 结束   0x21C0
  首个有内容 section   0x4000
  头部可用空白         7744 字节
  FairPlay             cryptoff=0x4000  cryptid=1
  → ✓ load commands 在加密区之前（0x21C0 < 0x4000），可安全写入

扩展 floatyLiveActivity:
  load commands 结束   0x15B0
  头部可用空白         10832 字节
```

所以只要把一条 `LC_LOAD_DYLIB` 写进那段空白，dyld 就会在启动时加载我们的 dylib。实测：

- 打完补丁文件大小**不变**（18869040 → 18869040）
- 只有 **59 个字节**变化，全部 `< 0x4000`（在加密区之外）
- `ncmds` 79 → 80，原代码签名被清零（改动头部后原签名必然失效）

### 2.4 关键约束：App Group

原版 entitlements（从 CMS SuperBlob slot 7 解出来的）：

```
application-identifier        = 9GAL39B66Y.com.enjoyio.floaty
com.apple.developer.team-identifier = 9GAL39B66Y
com.apple.security.application-groups = [group.com.enjoyio.floaty]
```

`group.com.enjoyio.floaty` **绑死在开发者团队 `9GAL39B66Y` 下**，用你自己的证书重签就申请不到这个 App Group → Live Activity、灵动岛、小组件会全部失效。

**所以路线 B 必须在越狱设备上用 TrollStore / ldid 假签（fake signing）**，保留原 entitlements。走普通侧载重签是保不住完整功能的。

### 2.5 完整流程

一条命令搞定解包 → 放 dylib → 注入两个二进制 → 重打包：

```bash
python unlock/package_unlocked_ipa.py \
  --ipa "浮现_1.1.0.ipa" \
  --dylib FloatyUnlock.dylib \
  --out floaty-unlocked.ipa
```

等价的手动步骤：

```bash
# 1) 编 dylib（需要 macOS 或 CI）
#    install_name 必须与注入的 LC_LOAD_DYLIB 路径完全一致
xcrun --sdk iphoneos clang \
  -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc -O2 \
  -dynamiclib -install_name '@executable_path/Frameworks/FloatyUnlock.dylib' \
  -framework Foundation \
  -o FloatyUnlock.dylib unlock/dylib/FloatyUnlock.m

# 2) 解包原版 IPA
unzip floaty.ipa -d unpacked
APP=unpacked/Payload/floaty.app

# 3) 先把 dylib 放进 Frameworks/
#    主 App 和每个 appex 都要放一份 —— @executable_path 是按各自的可执行文件解析的
mkdir -p "$APP/Frameworks"
cp FloatyUnlock.dylib "$APP/Frameworks/"
for P in "$APP"/PlugIns/*.appex; do
  mkdir -p "$P/Frameworks"
  cp FloatyUnlock.dylib "$P/Frameworks/"
done

# 4) 给主二进制和扩展都注入 dylib 依赖
#    （补丁器会自动跳过已经放进去的 FloatyUnlock.dylib 自身）
python unlock/patcher/floaty_patcher.py \
  --bundle "$APP" \
  --dylib-path '@executable_path/Frameworks/FloatyUnlock.dylib' \
  --out unpacked/patched

```bash
# 5) 假签（越狱设备，保留原 entitlements）
#    ldid -S<原 entitlements> 主二进制 与 appex
#    或用 TrollStore 直接装改过的 IPA（它会自己假签）

# 6) 重打包
cd unpacked && zip -qry floaty-unlocked.ipa Payload
```

> **注意 1**：原版二进制里**没有任何 `LC_RPATH`**。`@executable_path/Frameworks/FloatyUnlock.dylib` 走的是 dyld 对 `@executable_path` 的内置解析，不依赖 rpath，所以不需要额外补 `LC_RPATH`。
>
> **注意 2**：dylib 的 `install_name` 与写进 `LC_LOAD_DYLIB` 的路径**必须字面一致**，否则 dyld 加载时会因为路径不匹配而失败。CI 里已经统一成 `@executable_path/Frameworks/FloatyUnlock.dylib`。
>
> **注意 3**：`--out unpacked/patched` 是补丁器输出目录；dylib 是在**第 3 步**放进原 `Frameworks/` 的，补丁器会把这整个 bundle 复制到 `--out`，所以两份 dylib 都会跟着过去。

### 2.6 怎么确认 dylib 生效

dylib 每次真的改写了响应，就会在 App 沙盒里追加一行到 `floaty_unlock_hits.txt`：

```
/var/mobile/Containers/Data/Application/<UUID>/tmp/floaty_unlock_hits.txt
```

用 Filza / SSH 进去看这个文件，有记录就说明 hook 命中了。

---

## 3. 两条路线怎么选

| | 路线 A（MITM） | 路线 B（dylib） |
|---|---|---|
| 要越狱 | ❌ | ✅ |
| 要电脑常开 | ✅（代理要一直开着） | ❌（装完就能离线用） |
| 改动 App 本体 | ❌ | 注入 dylib |
| 稳定性 | 高（逻辑简单） | 中（hook 链路更复杂） |
| 保留 App Group / Live Activity | ✅ 原版原封不动 | ✅（假签前提下） |

**建议先跑路线 A** —— 零风险、零改动，能立刻验证"付费墙确实是这么卡住的"。确认 Pro 解锁成功后再决定要不要做路线 B。

---

## 4. 目录结构

```
unlock/
├── README.md                    ← 本文件
├── package_unlocked_ipa.py     ← 一键打包（解包→放 dylib→注入→重打包）
├── mitm/
│   ├── floaty_unlock.py         ← mitmproxy 插件（主路线）
│   ├── fake_revenuecat.py       ← 本地假 RevenueCat 服务（测试用）
│   ├── test_floaty_unlock.py    ← 单元自测
│   └── e2e_test.py              ← 端到端测试
├── dylib/
│   ├── FloatyUnlock.m           ← 注入式 dylib 源码
│   └── test_rewrite.m           ← 逻辑单测（macOS 编译运行）
└── patcher/
    ├── floaty_patcher.py        ← Mach-O LC_LOAD_DYLIB 补丁器
    └── test_floaty_patcher.py   ← 补丁器自测
```

CI：`.github/workflows/unlock-dylib.yml` —— 在 macos-15 上编 arm64 dylib + 跑两套单测 + 产出 dylib artifact。

最近一次成功的 run：**45320854541**（SHA `2f5d610`），artifact `FloatyUnlock-dylib`（dylib 本体 74312 字节，`install_name = @executable_path/Frameworks/FloatyUnlock.dylib`）。CI 里「Patch real Floaty IPA (end-to-end)」这一步需要仓库变量 `FLOATY_IPA_URL` 指向原版 IPA 的下载地址；不配这个变量该步会跳过，其余步骤照跑。

---

## 4.1 已验证的产物

`unlock/package_unlocked_ipa.py` 在真实原版 IPA 上跑通，产物：

```
Payload/floaty.app/Frameworks/FloatyUnlock.dylib                      74312
Payload/floaty.app/PlugIns/floatyLiveActivity.appex/Frameworks/
    FloatyUnlock.dylib                                                 74312
Payload/floaty.app/floaty                          injected=True  cryptid=1
Payload/floaty.app/PlugIns/floatyLiveActivity.appex/floatyLiveActivity
                                                       injected=True  cryptid=1
```

`cryptid` 保持 1 意味着 **FairPlay 加密段一个字节都没动**，App 仍然是官方加密版本、不会因为改了文件而崩溃。

---

## 5. 免责

本仓库的工具用于在你自己的设备上、对自己拥有的 App 做安全研究与互操作性测试。请勿用于分发破解版或侵犯他人权益。
