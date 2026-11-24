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

        printf("\n");
        if (gFailed > 0) {
            printf("FAILED %d 项\n", gFailed);
            return 1;
        }
        printf("全部通过 ✅\n");
        return 0;
    }
}
