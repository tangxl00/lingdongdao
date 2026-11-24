# ============================================================================
#  Floaty Unlock — 规则说明（给人看的）
#
#  真正给 QX 导入用的是 floaty_qx.resource.conf，那个文件里**只有一行规则**。
#  本文件只是把规则拆开解释清楚，不要拿去导入。
# ============================================================================

## 规则原文（复制这一行到 QX：订阅 → 重写 → + → 新建重写）
##
## ^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$) url script-response-body https://gcore.jsdelivr.net/gh/tangxl00/lingdongdao@44a5c29/unlock/qx/floaty_qx.js, requires-body=1, max-size=-1, tag=floaty-unlock

## ---------------------------------------------------------------------------
## 逐段拆解
## ---------------------------------------------------------------------------
##
## 1) 匹配部分
##
##    ^https?:\/\/api\.revenuecat\.(com|biz)\/v1\/(subscribers|customer)(\/|\?|$)
##
##    ^https?:             http 或 https
##    \/\/                 字面的 //
##    api\.revenuecat\.    字面的 api.revenuecat.
##    (com|biz)            .com 或 .biz
##    \/v1\/               字面的 /v1/
##    (subscribers|customer)
##                         /v1/subscribers/xxx（新版，Pro 判定入口）
##                         或 /v1/customer/xxx（旧版 CustomerInfo）
##    (\/|\?|$)            后面必须是 / 或 ? 或字符串结束
##                         ★ 这一段是关键：
##                           QX 匹配的是「带 query string 的整条 URL」。
##                           只写 /subscribers$ 的话，
##                           /subscribers?x=1 就匹配不到 →
##                           规则看着配了却不生效。
##
##    ★ 刻意不匹配 /v1/products 与 /v1/offerings：
##      那两个是付费页的套餐列表数据，改了会让套餐列表显示不出来。
##      上面的正则天然排除了它们（v1/ 后面接的不是 subscribers/customer）。
##
## 2) 动作部分
##
##    url script-response-body <脚本URL>, requires-body=1, max-size=-1, tag=floaty-unlock
##
##    url                  在 URL 层面匹配
##    script-response-body 用脚本改写「响应体」
##    requires-body=1      让 QX 把响应体读进来交给脚本
##                         ★ 写成 true 在部分 QX 版本上会解析失败，
##                           用数字 1 最稳
##    max-size=-1          不限制响应体大小
##                         ★ 原写 131072（128KB）在部分版本上不被接受；
##                           写 -1 = 不限制，最稳
##    tag=                  给规则起个名字，方便在 QX 里辨认
##
## 3) 脚本 URL 为什么是 @44a5c29 而不是 @main
##
##    实测（2026-11-24）：
##      gcore@main         → 返回旧版内容（CDN 缓存了旧的 @main 快照）
##      gcore@main?v=2     → 仍然旧版（?v=2 破不掉缓存）
##      gcore@<commit>     → 立即是新版 ✅
##      ghproxy 直连 raw   → 是新版（但也会滞后几分钟）
##
##    所以引用一律用固定 commit，不用 @main。

## ---------------------------------------------------------------------------
## MITM 域名（远程 rewrite 资源装不下这个，必须手动配）
## ---------------------------------------------------------------------------
##
## QX → 设置 → HTTPS 解密 → MITM 主机名 → 加：
##     api.revenuecat.com
##     api.revenuecat.biz

## ---------------------------------------------------------------------------
## 导入报 "problem in sub-resource" 的排查顺序
## ---------------------------------------------------------------------------
##
## 1. 资源文件里**不能有** [rewrite] / [MITM] 段头，不能有 hostname = 行
##    （那是本地 .conf 配置文件的写法，远程资源只接受纯规则行）
##
## 2. requires-body 必须写 =1，不能写 =true
##
## 3. max-size 写 -1（不限制）；某些版本不接受 131072
##
## 4. 文件必须纯 ASCII，不要带中文注释（QX 对非 ASCII 的处理不稳定）
##    → 这正是本说明单独放一个文件、而 resource.conf 只留一行纯 ASCII 的原因
##
## 5. 脚本 URL 必须是完整 https:// 绝对地址，不能是相对路径
