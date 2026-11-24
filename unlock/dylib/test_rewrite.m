/*
 *  test_rewrite.m — FloatyUnlock 的 JSON 改写逻辑单测
 *
 *  在 macOS 上编译运行：
 *      clang -fobjc-arc -framework Foundation test_rewrite.m FloatyUnlock.m -o test_rewrite
 *      ./test_rewrite
 *
 *  覆盖：
 *    1. 新版 subscriber 形状  { "subscriber": { "entitlements": {...} } }
 *    2. 旧版 customer_info 形状
 *    3. 顶层 flat 形状 { "entitlements": {...} }
 *    4. verification / verification_data 被摘掉
 *    5. active_entitlements 被填上
 *    6. products / offerings 路径不被改
 *    7. 非 JSON / 空 body 不改
 *    8. URL 判定表
 */

#import <Foundation/Foundation.h>

/* FloatyUnlock.m 里的函数是 static，这里重新声明以便测试 */
#ifdef __cplusplus
extern "C" {
#endif

/* 复制一份可测试的入口：直接 include 源文件里的实现不方便，
   这里用 weak 链接方式不行，改用把关键逻辑抽到头文件。
   —— 实际做法：把 FloatyUnlock.m 的纯逻辑部分通过下面这组声明暴露。 */

extern NSData *FUTestRewriteBody(NSData *data);
extern BOOL FUTestShouldRewriteURL(NSURL *url);
extern void FUTestInstall(void);
extern void *FUTestOrigIMPForInstance(id instance, const char *selectorName);

#ifdef __cplusplus
}
#endif

static int gFailed = 0;

static void check(NSString *name, BOOL cond) {
    if (cond) {
        printf("  PASS  %s\n", name.UTF8String);
    } else {
        printf("  FAIL  %s\n", name.UTF8String);
        gFailed++;
    }
}

static NSDictionary *parse(NSData *d) {
    return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
}

int main(void) {
    @autoreleasepool {
        printf("== 1. 新版 subscriber 形状 ==\n");
        NSString *sub = @"{\"subscriber\":{\"entitlements\":{\"pro\":{\"id\":\"pro\",\"is_active\":false,"
                        "\"will_renew\":false,\"expires_date\":\"2025-01-01T00:00:00Z\","
                        "\"verification\":\"sig\",\"verification_data\":\"vdata\"}},"
                        "\"active_entitlements\":[]}}";
        NSData *out = FUTestRewriteBody([sub dataUsingEncoding:NSUTF8StringEncoding]);
        check(@"返回了新 body", out != nil);
        NSDictionary *root = parse(out);
        NSDictionary *sub2 = root[@"subscriber"];
        NSDictionary *ent = sub2[@"entitlements"][@"pro"];
        check(@"is_active = YES", [ent[@"is_active"] boolValue] == YES);
        check(@"will_renew = NO", [ent[@"will_renew"] boolValue] == NO);
        check(@"expires_date 被改成 2099",
              [ent[@"expires_date"] isEqualToString:@"2099-12-31T23:59:59Z"]);
        check(@"verification 被摘掉", ent[@"verification"] == nil);
        check(@"verification_data 被摘掉", ent[@"verification_data"] == nil);
        check(@"active_entitlements 被填上",
              [sub2[@"active_entitlements"] isEqualToArray:@[@"pro"]]);

        printf("== 2. 旧版 customer_info 形状 ==\n");
        NSString *cust = @"{\"customer_info\":{\"entitlements\":{\"lifetime\":{\"is_active\":false,"
                         "\"expires_date\":\"2025-01-01T00:00:00Z\"}}}}";
        NSData *out2 = FUTestRewriteBody([cust dataUsingEncoding:NSUTF8StringEncoding]);
        NSDictionary *ent2 = parse(out2)[@"customer_info"][@"entitlements"][@"lifetime"];
        check(@"customer_info 内的权益被改", [ent2[@"is_active"] boolValue] == YES);
        check(@"expires_date 被改", [ent2[@"expires_date"] isEqualToString:@"2099-12-31T23:59:59Z"]);

        printf("== 3. 顶层 flat 形状 ==\n");
        NSString *flat = @"{\"entitlements\":{\"pro\":{\"is_active\":false}},"
                         "\"active_entitlements\":[]}";
        NSData *out3 = FUTestRewriteBody([flat dataUsingEncoding:NSUTF8StringEncoding]);
        NSDictionary *r3 = parse(out3);
        check(@"顶层权益被改", [r3[@"entitlements"][@"pro"][@"is_active"] boolValue] == YES);
        check(@"顶层 active_entitlements 被填",
              [r3[@"active_entitlements"] isEqualToArray:@[@"pro"]]);

        printf("== 4. 空 / 非 JSON 不改 ==\n");
        check(@"空 body 返回 nil", FUTestRewriteBody([NSData data]) == nil);
        check(@"非 JSON 返回 nil",
              FUTestRewriteBody([@"not json at all" dataUsingEncoding:NSUTF8StringEncoding]) == nil);
        check(@"无 entitlements 的 JSON 返回 nil",
              FUTestRewriteBody([@"{\"foo\":1}" dataUsingEncoding:NSUTF8StringEncoding]) == nil);

        printf("== 5. URL 判定表 ==\n");
        check(@"revenuecat.com subscriber 命中",
              FUTestShouldRewriteURL([NSURL URLWithString:@"https://api.revenuecat.com/v1/subscribers/abc"]));
        check(@"revenuecat.biz subscriber 命中",
              FUTestShouldRewriteURL([NSURL URLWithString:@"https://api.revenuecat.biz/v1/subscribers/abc"]));
        check(@"旧版 /v1/customer 命中",
              FUTestShouldRewriteURL([NSURL URLWithString:@"https://api.revenuecat.com/v1/customer/abc"]));
        check(@"products 不命中",
              !FUTestShouldRewriteURL([NSURL URLWithString:@"https://api.revenuecat.com/v1/products"]));
        check(@"offerings 不命中",
              !FUTestShouldRewriteURL([NSURL URLWithString:@"https://api.revenuecat.com/v1/offerings"]));
        check(@"非 revenuecat 域名不命中",
              !FUTestShouldRewriteURL([NSURL URLWithString:@"https://example.com/v1/subscribers/abc"]));
        check(@"非 revenuecat 域名(前缀伪装)不命中",
              !FUTestShouldRewriteURL([NSURL URLWithString:@"https://revenuecat.com.evil.net/v1/subscribers/a"]));

        printf("== 6. swizzle 装得上，且 class cluster 能找回原始 IMP ==\n");
        FUTestInstall();
        NSURLSession *sess = [NSURLSession sharedSession];
        check(@"session 非空", sess != nil);

        // 关键回归：NSURLSession 是 class cluster，实例的真实类是私有子类
        // （macOS 上是 __NSCFURLSession / iOS 上是 __NSCFURLSession）。
        // 如果只按 object_getClass(self) 查表就会查不到 → 原始 IMP 为 NULL →
        // 所有网络请求被吞掉、App 联网全断。这里必须能沿类链回溯到。
        void *origReq = FUTestOrigIMPForInstance(sess, "dataTaskWithRequest:completionHandler:");
        void *origURL = FUTestOrigIMPForInstance(sess, "dataTaskWithURL:completionHandler:");
        check(@"dataTaskWithRequest:completionHandler: 能找回原始 IMP", origReq != NULL);
        check(@"dataTaskWithURL:completionHandler: 能找回原始 IMP", origURL != NULL);
        check(@"两个 IMP 不相同（确实是两个方法）", origReq != origURL);

        // 走一次真实的 completion-handler 型调用，验证请求没有被吞掉。
        // 命中本地不可达地址 → 期望走 error 回调，而不是永远挂起。
        __block BOOL called = NO;
        __block NSError *capturedErr = nil;
        NSURL *dead = [NSURL URLWithString:@"http://127.0.0.1:1/never"];
        NSURLSessionDataTask *t = [sess dataTaskWithURL:dead
                                    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            called = YES;
            capturedErr = e;
        }];
        check(@"dataTaskWithURL: 返回了 task 对象（没被吞）", t != nil);
        [t resume];
        // 等回调（最多 5 秒）
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (!called && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        check(@"completion handler 确实被回调了（链路没断）", called);
        check(@"回调带回了 error（说明请求真的发出去了）", capturedErr != nil);

        printf("== 7. L0：NSURLProtocol 已注册，且 async 路径能被接管 ==\n");
        // NSURLProtocol 是唯一覆盖 Swift async/await 的钩子
        // （URLSession.data(for:) 是泛型扩展，不是 ObjC 方法，swizzle 够不着）
        Class proto = NSClassFromString(@"FUURLProtocol");
        check(@"FUURLProtocol 类存在", proto != Nil);
        check(@"FUURLProtocol 是 NSURLProtocol 子类",
              proto != Nil && [proto isSubclassOfClass:[NSURLProtocol class]]);
        check(@"+canInitWithRequest: 对 RevenueCat 权益接口返回 YES",
              proto != Nil && [proto canInitWithRequest:
                  [NSURLRequest requestWithURL:
                      [NSURL URLWithString:@"https://api.revenuecat.com/v1/subscribers/u1"]]] == YES);
        check(@"+canInitWithRequest: 对 products 返回 NO（付费页套餐要能显示）",
              proto != Nil && [proto canInitWithRequest:
                  [NSURLRequest requestWithURL:
                      [NSURL URLWithString:@"https://api.revenuecat.com/v1/products"]]] == NO);
        check(@"+canInitWithRequest: 对无关域名返回 NO",
              proto != Nil && [proto canInitWithRequest:
                  [NSURLRequest requestWithURL:
                      [NSURL URLWithString:@"https://example.com/v1/subscribers/u1"]]] == NO);

        // configuration 的 protocolClasses 必须带上我们（这是 async 路径能生效的关键）
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        BOOL hasOurs = NO;
        for (Class c in cfg.protocolClasses) {
            if (c == proto) {
                hasOurs = YES;
                break;
            }
        }
        check(@"NSURLSessionConfiguration.protocolClasses 已包含 FUURLProtocol", hasOurs);

        printf("\n");
        if (gFailed > 0) {
            printf("FAILED %d 项\n", gFailed);
            return 1;
        }
        printf("全部通过 ✅\n");
        return 0;
    }
}
