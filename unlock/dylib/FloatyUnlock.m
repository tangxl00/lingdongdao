/*
 *  FloatyUnlock.m
 *
 *  浮现 (Floaty / com.enjoyio.floaty) 付费墙解锁 —— 注入式 dylib
 *
 *  原理
 *  ----
 *  浮现的订阅判定完全走 RevenueCat SDK：
 *
 *      Purchases.configure(apiKey)
 *        -> CustomerInfo.entitlements[requiredEntitlementIdentifier].isActive
 *        -> PaywallPresenter.presentPaywallIfNeeded()
 *
 *  RevenueCat 的 CustomerInfo / EntitlementInfo 都是 Swift struct，
 *  没有 ObjC 运行时元数据，没法直接 swizzle。所以本 dylib 拦在更下面一层：
 *  **URLSession 的响应体**。
 *
 *  只要把 RevenueCat 下发的 /v1/subscribers/{app_user_id} 响应里的权益改成
 *  "永久有效"，App 侧读到的就是 Pro —— App 本体一个字节都不用改，
 *  功能与布局 100% 保留。
 *
 *  四层拦截（互相兜底，任一命中即可）
 *  ----------------------------------
 *  L1  swizzle -[NSURLSession dataTaskWithRequest:completionHandler:]
 *  L2  swizzle -[NSURLSession dataTaskWithURL:completionHandler:]
 *      -> 包一层 completion handler，拿到完整 data 时就地改写
 *  L3  运行时枚举所有类，swizzle 实现了
 *      URLSession:dataTask:didReceiveData:
 *      的类：**只对 RevenueCat 的任务**先缓存、其余原样透传
 *  L4  运行时枚举所有类，swizzle 实现了
 *      URLSession:dataTask:didCompleteWithError:
 *      的类：把 L3 缓存的 RevenueCat 响应改写后回放，再交回原实现
 *
 *  另外摘掉 entitlement verification —— RevenueCat 的服务端签名校验
 *  在 enforced 模式下会把被改过的 JSON 判定为失败并把 isActive 压回 false。
 *
 *  命中记录
 *  --------
 *  每次真的改写了响应，就在 App 沙盒 tmp 里追加一行到
 *  floaty_unlock_hits.txt，方便确认 dylib 生效。
 *
 *  兼容性
 *  ------
 *  * arm64 + iOS 17.0+（与原 App 的 MinimumOSVersion 一致）
 *  * ARC
 *  * 注入方式：jailbreak（Substrate/ElleKit）或 TrollStore 假签
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 常量

static NSString *const kFUHosts[] = {
    @"revenuecat.com",
    @"revenuecat.biz",
};
static const NSUInteger kFUHostCount = 2;

static NSString *const kFUFarFuture = @"2099-12-31T23:59:59Z";

#pragma mark - 小工具

static BOOL FUIsRevenueCatHost(NSString *host) {
    if (host.length == 0) {
        return NO;
    }
    host = host.lowercaseString;
    for (NSUInteger i = 0; i < kFUHostCount; i++) {
        NSString *h = kFUHosts[i];
        if ([host isEqualToString:h] || [host hasSuffix:[@"." stringByAppendingString:h]]) {
            return YES;
        }
    }
    return NO;
}

static BOOL FUIsSubscriberPath(NSString *path) {
    if (path.length == 0) {
        return NO;
    }
    NSString *p = path.lowercaseString;
    if ([p containsString:@"/v1/products"] || [p containsString:@"/v1/offerings"]
        || [p containsString:@"/products"] || [p containsString:@"/offerings"]) {
        // 套餐/产品列表必须保持原样，否则付费页会显示不出来
        return NO;
    }
    return [p containsString:@"/subscribers"] || [p containsString:@"/customer"];
}

/// 这条请求要不要改写（只看 URL）
static BOOL FUShouldRewriteURL(NSURL *url) {
    if (url == nil) {
        return NO;
    }
    return FUIsRevenueCatHost(url.host) && FUIsSubscriberPath(url.path);
}

#pragma mark - JSON 改写

/// 把一个 entitlement 字典改成"永久有效"
static void FUUnlockEntitlement(NSMutableDictionary *ent) {
    if (![ent isKindOfClass:[NSDictionary class]]) {
        return;
    }
    ent[@"is_active"] = @YES;
    ent[@"will_renew"] = @NO;
    ent[@"expires_date"] = kFUFarFuture;
    ent[@"grace_period_expires_date"] = kFUFarFuture;
    // 摘掉服务端签名校验字段（snake_case，与 SDK 的 convertFromSnakeCase 对应）
    [ent removeObjectForKey:@"verification"];
    [ent removeObjectForKey:@"verification_data"];
}

/// 就地把一个字典里的 entitlements 改掉。返回是否发生了改写。
static BOOL FUUnlockEntitlementsInPlace(NSMutableDictionary *dict) {
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    BOOL changed = NO;

    id ents = dict[@"entitlements"];
    if ([ents isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *newEnts = [ents mutableCopy];
        for (NSString *eid in newEnts) {
            id ent = newEnts[eid];
            if ([ent isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *m = [ent mutableCopy];
                FUUnlockEntitlement(m);
                newEnts[eid] = m;
                changed = YES;
            }
        }
        dict[@"entitlements"] = newEnts;

        // active_entitlements 是 SDK 另一处判断依据
        id active = dict[@"active_entitlements"];
        if ([active isKindOfClass:[NSArray class]]) {
            dict[@"active_entitlements"] = [newEnts.allKeys copy];
        }
    }
    return changed;
}

/// 主入口：改写一个 JSON 响应体。返回 nil 表示不用改。
static NSData *FURewriteBody(NSData *data) {
    if (data.length == 0) {
        return nil;
    }
    NSError *err = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err != nil || root == nil || ![root isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSMutableDictionary *out = [root mutableCopy];
    BOOL changed = FUUnlockEntitlementsInPlace(out);

    // subscriber / customer_info 两层壳
    for (NSString *key in @[ @"subscriber", @"customer_info", @"subscriber_info" ]) {
        id child = out[key];
        if (![child isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSMutableDictionary *m = [child mutableCopy];
        if (FUUnlockEntitlementsInPlace(m)) {
            out[key] = m;
            changed = YES;
        }
    }

    if (!changed) {
        return nil;
    }

    NSData *newData = [NSJSONSerialization dataWithJSONObject:out options:0 error:&err];
    if (newData == nil) {
        return nil;
    }
    return newData;
}

/// 判断（URL + body）是否该改写
static NSData *FURewriteIfNeeded(NSURL *url, NSData *data) {
    if (url == nil || data.length == 0) {
        return nil;
    }
    if (!FUShouldRewriteURL(url)) {
        return nil;
    }
    return FURewriteBody(data);
}

#pragma mark - 前向声明（测试入口在 swizzle 基础设施之前定义）

static void FUInstall(void);
static IMP FUOrigIMPForInstance(id self, SEL sel);

#pragma mark - 测试入口（test_rewrite.m 用）

NSData *FUTestRewriteBody(NSData *data) {
    return FURewriteBody(data);
}

BOOL FUTestShouldRewriteURL(NSURL *url) {
    return FUShouldRewriteURL(url);
}

/// 装一次 swizzle（供单测在 macOS 宿主上验证 hook 链路）
void FUTestInstall(void) {
    FUInstall();
}

/// 取某个类的原始 IMP（供单测验证 class cluster 回溯是否正确）
void *FUTestOrigIMPForInstance(id instance, const char *selectorName) {
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selectorName]);
    IMP imp = FUOrigIMPForInstance(instance, sel);
    return (void *)imp;
}

/// 命中时写一个标记文件，方便用户确认 dylib 真的生效了
static void FUMarkHit(NSString *tag) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"floaty_unlock_hits.txt"];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date].description, tag];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh == nil) {
            [[NSFileManager defaultManager] createFileAtPath:path
                                                 contents:[NSData data]
                                               attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    });
}

#pragma mark - swizzle 基础设施

static void FUInstall(void);

/// 原 IMP 登记表：key = "<class ptr>|<selector>"，value = IMP
static NSMutableDictionary *FUOrigIMPs(void) {
    static NSMutableDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSMutableDictionary dictionary];
    });
    return table;
}

static NSString *FUKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%p|%@", (void *)cls, NSStringFromSelector(sel)];
}

static IMP FUOrigIMP(Class cls, SEL sel) {
    NSValue *v = FUOrigIMPs()[FUKey(cls, sel)];
    return v ? (IMP)v.pointerValue : NULL;
}

/// 沿实例的真实类链向上找原始 IMP。
///
/// NSURLSession 是 class cluster：真实实例的类是私有子类 __NSCFURLSession，
/// 而我们 swizzle 的是公开类 NSURLSession。若只查 object_getClass(self)
/// 就会查不到记录 → 拿到 NULL → 请求被吞掉、异步调用永久挂起。
/// 因此必须沿 superclass 链回溯。
static IMP FUOrigIMPForInstance(id self, SEL sel) {
    for (Class c = object_getClass(self); c != Nil; c = class_getSuperclass(c)) {
        IMP imp = FUOrigIMP(c, sel);
        if (imp != NULL) {
            return imp;
        }
    }
    return NULL;
}

/// L1 / L2 单独存一份原始 IMP —— 安装时抓一次，之后不再查表，
/// 彻底避开 class cluster 与「二次安装抓到自己的 replacement」两个坑。
static IMP gOrigDataTaskWithRequest = NULL;
static IMP gOrigDataTaskWithURL = NULL;

/// 沿类链向上找**真正的原始实现**（跳过已经被我们换成 replacement 的那份）。
///
/// 必须逐级用 class_copyMethodList 只看「本级自己声明的方法」：
/// class_getInstanceMethod 返回的可能是父类继承来的方法，而父类可能
/// 已经被 swizzle 过（IMP == replacement），此时若直接取它的 IMP 就会
/// 把 replacement 当成原实现，调用后无限递归。
static IMP FUFindRealIMP(Class cls, SEL sel, IMP replacement) {
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *ms = class_copyMethodList(c, &count);
        IMP found = NULL;
        if (ms != NULL) {
            for (unsigned int i = 0; i < count; i++) {
                if (method_getName(ms[i]) == sel) {
                    found = method_getImplementation(ms[i]);
                    break;
                }
            }
            free(ms);
        }
        if (found != NULL && found != replacement) {
            return found;
        }
    }
    return NULL;
}

/// 取某个方法签名的 type encoding（沿类链找第一个声明者）
static const char *FUTypeEncoding(Class cls, SEL sel) {
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *ms = class_copyMethodList(c, &count);
        const char *enc = NULL;
        if (ms != NULL) {
            for (unsigned int i = 0; i < count; i++) {
                if (method_getName(ms[i]) == sel) {
                    enc = method_getTypeEncoding(ms[i]);
                    break;
                }
            }
            free(ms);
        }
        if (enc != NULL) {
            return enc;
        }
    }
    return NULL;
}

/// 把 sel 在 cls 上的实现替换成 replacement。
///
/// 用 class_replaceMethod：
///   * cls 自己声明过 → 直接换实现
///   * cls 继承来的    → 在 cls 上新增一个 override（父类那份不受影响）
/// 这样无论类链怎么排，每个类都有自己独立的 entry，不会出现
/// 「子类拿到父类的 replacement」导致调用递归或回调丢失。
static void FUSwizzle(Class cls, SEL sel, IMP replacement) {
    if (cls == Nil) {
        return;
    }
    if (FUOrigIMPs()[FUKey(cls, sel)] != nil) {
        return; // 已经装过了
    }
    IMP orig = FUFindRealIMP(cls, sel, replacement);
    if (orig == NULL) {
        return;
    }
    const char *types = FUTypeEncoding(cls, sel);
    if (types == NULL) {
        return;
    }
    FUOrigIMPs()[FUKey(cls, sel)] = [NSValue valueWithPointer:orig];
    class_replaceMethod(cls, sel, replacement, types);
}

#pragma mark - L1 / L2：completion handler 型

static NSURLSessionDataTask *FUDataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request,
                                                   void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    IMP orig = FUOrigIMPForInstance(self, @selector(dataTaskWithRequest:completionHandler:));
    if (orig == NULL || orig == (IMP)FUDataTaskWithRequest) {
        orig = gOrigDataTaskWithRequest;
    }
    if (orig == NULL) {
        return nil;
    }

    if (handler == nil) {
        typedef NSURLSessionDataTask * (*Orig)(id, SEL, NSURLRequest *,
                                               void (^)(NSData *, NSURLResponse *, NSError *));
        return ((Orig)orig)(self, _cmd, request, handler);
    }

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *newData = nil;
            NSURL *url = response.URL ?: request.URL;
            if (data.length > 0) {
                newData = FURewriteIfNeeded(url, data);
                if (newData != nil) {
                    FUMarkHit(@"completion-handler");
                }
            }
            handler(newData ?: data, response, error);
        };

    typedef NSURLSessionDataTask * (*Orig)(id, SEL, NSURLRequest *,
                                           void (^)(NSData *, NSURLResponse *, NSError *));
    return ((Orig)orig)(self, _cmd, request, wrapped);
}

static NSURLSessionDataTask *FUDataTaskWithURL(id self, SEL _cmd, NSURL *url,
                                               void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    IMP orig = FUOrigIMPForInstance(self, @selector(dataTaskWithURL:completionHandler:));
    if (orig == NULL || orig == (IMP)FUDataTaskWithURL) {
        orig = gOrigDataTaskWithURL;
    }
    if (orig == NULL) {
        return nil;
    }

    if (handler == nil) {
        typedef NSURLSessionDataTask * (*Orig)(id, SEL, NSURL *,
                                               void (^)(NSData *, NSURLResponse *, NSError *));
        return ((Orig)orig)(self, _cmd, url, handler);
    }

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *newData = nil;
            NSURL *u = response.URL ?: url;
            if (data.length > 0) {
                newData = FURewriteIfNeeded(u, data);
                if (newData != nil) {
                    FUMarkHit(@"completion-handler-url");
                }
            }
            handler(newData ?: data, response, error);
        };

    typedef NSURLSessionDataTask * (*Orig)(id, SEL, NSURL *,
                                           void (^)(NSData *, NSURLResponse *, NSError *));
    return ((Orig)orig)(self, _cmd, url, wrapped);
}

#pragma mark - L3 / L4：delegate 型

/// 每个 task 的缓存 body
static NSMutableDictionary *FUBuffers(void) {
    static NSMutableDictionary *buf = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        buf = [NSMutableDictionary dictionary];
    });
    return buf;
}

static NSLock *FULock(void) {
    static NSLock *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSLock alloc] init];
    });
    return lock;
}

static void FUReceiveData(id self, SEL _cmd, NSURLSession *session, NSURLSessionDataTask *task,
                           NSData *data) {
    NSURL *url = task.originalRequest.URL ?: task.currentRequest.URL;
    if (!FUShouldRewriteURL(url)) {
        // 非 RevenueCat 流量：原样透传，不缓存、不拦截
        IMP orig = FUOrigIMPForInstance(self, @selector(URLSession:dataTask:didReceiveData:));
        if (orig != NULL) {
            ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))orig)(
                self, _cmd, session, task, data);
        }
        return;
    }

    // RevenueCat 流量：先缓存，等 complete 时统一改写再回放
    if (data.length > 0) {
        NSValue *key = [NSValue valueWithNonretainedObject:task];
        NSLock *lock = FULock();
        [lock lock];
        NSMutableData *acc = FUBuffers()[key];
        if (acc == nil) {
            acc = [NSMutableData data];
            FUBuffers()[key] = acc;
        }
        [acc appendData:data];
        [lock unlock];
    }
}

static void FUCompleteWithError(id self, SEL _cmd, NSURLSession *session,
                                NSURLSessionDataTask *task, NSError *error) {
    NSValue *key = [NSValue valueWithNonretainedObject:task];

    NSLock *lock = FULock();
    [lock lock];
    NSMutableData *acc = FUBuffers()[key];
    if (acc) {
        [FUBuffers() removeObjectForKey:key];
    }
    [lock unlock];

    if (acc.length > 0) {
        NSURL *url = task.originalRequest.URL ?: task.currentRequest.URL;
        NSData *newData = FURewriteIfNeeded(url, acc);
        IMP origData = FUOrigIMPForInstance(self, @selector(URLSession:dataTask:didReceiveData:));
        if (origData != NULL) {
            if (newData != nil) {
                FUMarkHit(@"delegate");
            }
            ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))origData)(
                self, @selector(URLSession:dataTask:didReceiveData:),
                session, task, newData ?: acc);
        }
    }

    IMP origComplete = FUOrigIMPForInstance(self, @selector(URLSession:dataTask:didCompleteWithError:));
    if (origComplete != NULL) {
        ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSError *))origComplete)(
            self, @selector(URLSession:dataTask:didCompleteWithError:),
            session, task, error);
    }
}

#pragma mark - 安装

static void FUInstall(void) {
    // L1 / L2 —— NSURLSession 的 completion handler 型
    //
    // 先把「真正的原始 IMP」抓一次存到全局，后面 swizzle 后的调用直接用它，
    // 不再回头查表 —— 避免二次安装时把 replacement 当成原实现造成无限递归。
    Class sessionCls = [NSURLSession class];
    if (gOrigDataTaskWithRequest == NULL) {
        gOrigDataTaskWithRequest = FUFindRealIMP(
            sessionCls, @selector(dataTaskWithRequest:completionHandler:), (IMP)FUDataTaskWithRequest);
    }
    if (gOrigDataTaskWithURL == NULL) {
        gOrigDataTaskWithURL = FUFindRealIMP(
            sessionCls, @selector(dataTaskWithURL:completionHandler:), (IMP)FUDataTaskWithURL);
    }

    FUSwizzle(sessionCls, @selector(dataTaskWithRequest:completionHandler:),
              (IMP)FUDataTaskWithRequest);
    FUSwizzle(sessionCls, @selector(dataTaskWithURL:completionHandler:),
              (IMP)FUDataTaskWithURL);

    // L3 / L4 —— 枚举所有类，把实现 delegate 回调的类都 swizzle
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    SEL dataSel = @selector(URLSession:dataTask:didReceiveData:);
    SEL completeSel = @selector(URLSession:dataTask:didCompleteWithError:);

    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (class_getInstanceMethod(cls, dataSel)) {
            FUSwizzle(cls, dataSel, (IMP)FUReceiveData);
        }
        if (class_getInstanceMethod(cls, completeSel)) {
            FUSwizzle(cls, completeSel, (IMP)FUCompleteWithError);
        }
    }
    free(classes);

    NSLog(@"[FloatyUnlock] 已加载：RevenueCat 权益将被改写为永久 Pro");
}

__attribute__((constructor)) static void FUInit(void) {
    @autoreleasepool {
        FUInstall();
        // 等主线程跑起来再装一次（此时可能又加载了新的类）
        dispatch_async(dispatch_get_main_queue(), ^{
            FUInstall();
        });
    }
}
