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

#pragma mark - 测试入口（test_rewrite.m 用）

NSData *FUTestRewriteBody(NSData *data) {
    return FURewriteBody(data);
}

BOOL FUTestShouldRewriteURL(NSURL *url) {
    return FUShouldRewriteURL(url);
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

/// 把 sel 在 cls 上的实现替换成 replacement。
/// 若该方法其实继承自父类，则在 cls 上新增一个 override，而不是改父类。
static void FUSwizzle(Class cls, SEL sel, IMP replacement) {
    if (cls == Nil) {
        return;
    }
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL) {
        return;
    }
    if (class_getMethodImplementation(cls, sel) == replacement) {
        return; // 已经装过了
    }
    IMP orig = method_getImplementation(m);
    if (orig == replacement) {
        return;
    }
    FUOrigIMPs()[FUKey(cls, sel)] = [NSValue valueWithPointer:orig];

    // 自己实现 → 直接换实现；继承来的 → 在子类上 override
    const char *types = method_getTypeEncoding(m);
    if (!class_addMethod(cls, sel, replacement, types)) {
        method_setImplementation(m, replacement);
    }
}

#pragma mark - L1 / L2：completion handler 型

static NSURLSessionDataTask *FUDataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request,
                                                   void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    if (handler == nil) {
        Class cls = object_getClass(self);
        IMP orig = FUOrigIMP(cls, @selector(dataTaskWithRequest:completionHandler:));
        if (orig == NULL) {
            return nil;
        }
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

    Class cls = object_getClass(self);
    IMP orig = FUOrigIMP(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (orig == NULL) {
        return nil;
    }
    typedef NSURLSessionDataTask * (*Orig)(id, SEL, NSURLRequest *,
                                           void (^)(NSData *, NSURLResponse *, NSError *));
    return ((Orig)orig)(self, _cmd, request, wrapped);
}

static NSURLSessionDataTask *FUDataTaskWithURL(id self, SEL _cmd, NSURL *url,
                                               void (^handler)(NSData *, NSURLResponse *, NSError *)) {
    if (handler == nil) {
        Class cls = object_getClass(self);
        IMP orig = FUOrigIMP(cls, @selector(dataTaskWithURL:completionHandler:));
        if (orig == NULL) {
            return nil;
        }
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

    Class cls = object_getClass(self);
    IMP orig = FUOrigIMP(cls, @selector(dataTaskWithURL:completionHandler:));
    if (orig == NULL) {
        return nil;
    }
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
        Class cls = object_getClass(self);
        IMP orig = FUOrigIMP(cls, @selector(URLSession:dataTask:didReceiveData:));
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
    Class cls = object_getClass(self);
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
        if (newData != nil) {
            FUMarkHit(@"delegate");
            IMP origData = FUOrigIMP(cls, @selector(URLSession:dataTask:didReceiveData:));
            if (origData != NULL) {
                ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))origData)(
                    self, @selector(URLSession:dataTask:didReceiveData:),
                    session, task, newData);
            }
        } else {
            IMP origData = FUOrigIMP(cls, @selector(URLSession:dataTask:didReceiveData:));
            if (origData != NULL) {
                ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))origData)(
                    self, @selector(URLSession:dataTask:didReceiveData:),
                    session, task, acc);
            }
        }
    }

    IMP origComplete = FUOrigIMP(cls, @selector(URLSession:dataTask:didCompleteWithError:));
    if (origComplete != NULL) {
        ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSError *))origComplete)(
            self, @selector(URLSession:dataTask:didCompleteWithError:),
            session, task, error);
    }
}

#pragma mark - 安装

static void FUInstall(void) {
    // L1 / L2 —— NSURLSession 的 completion handler 型
    Class sessionCls = [NSURLSession class];
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
