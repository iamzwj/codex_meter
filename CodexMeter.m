#import <AppKit/AppKit.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSString *cached = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastCodexUsageDisplay"];
    self.statusItem.button.title = cached ?: @"—";
    self.statusItem.button.toolTip = @"正在读取 Codex 用量…";
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"正在读取用量…" action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"立即刷新" action:@selector(refreshUsage:) keyEquivalent:@"r"];
    [menu addItemWithTitle:@"打开 Codex 用量页" action:@selector(openUsagePage:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出 Codex Meter" action:@selector(quit:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
    [self refreshUsage:nil];
    [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refreshUsage:) userInfo:nil repeats:YES];
}

- (void)refreshUsage:(id)sender {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *response = [self readUsage];
        dispatch_async(dispatch_get_main_queue(), ^{ [self renderResponse:response]; });
    });
}

- (NSDictionary *)readUsage {
    // Use the Desktop app's current CLI. The legacy Resources/codex binary can
    // return a stale 0/0 usage snapshot after Codex Desktop updates.
    NSString *binary = @"/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:binary]) return nil;
    NSString *init = @"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"CodexMeter\",\"version\":\"1.0\"}}}";
    NSString *ready = @"{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}";
    NSString *read = @"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}";
    NSString *command = [NSString stringWithFormat:@"{ printf '%%s\\n' '%@'; sleep 1; printf '%%s\\n' '%@' '%@'; sleep 4; } | '%@' app-server --stdio", init, ready, read, binary];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[@"-lc", command];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    @try { [task launchAndReturnError:nil]; } @catch (NSException *exception) { return nil; }
    [task waitUntilExit];
    NSString *output = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        if ([line rangeOfString:@"\"id\":2"].location == NSNotFound) continue;
        NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"\\\"usedPercent\\\":([0-9]+)" options:0 error:nil];
        NSArray<NSTextCheckingResult *> *matches = [pattern matchesInString:line options:0 range:NSMakeRange(0, line.length)];
        if (matches.count >= 2) {
            NSInteger fiveHourUsed = [[line substringWithRange:[matches[0] rangeAtIndex:1]] integerValue];
            NSInteger weeklyUsed = [[line substringWithRange:[matches[1] rangeAtIndex:1]] integerValue];
            return @{@"rateLimits": @{@"primary": @{@"usedPercent": @(fiveHourUsed)}, @"secondary": @{@"usedPercent": @(weeklyUsed)}}};
        }
    }
    return nil;
}

- (void)renderResponse:(NSDictionary *)response {
    NSDictionary *limits = response[@"rateLimits"];
    NSNumber *fiveHourUsed = limits[@"primary"][@"usedPercent"];
    NSNumber *weeklyUsed = limits[@"secondary"][@"usedPercent"];
    if (!fiveHourUsed || !weeklyUsed) {
        NSString *cached = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastCodexUsageDisplay"];
        self.statusItem.button.title = cached ?: @"!";
        self.statusItem.button.toolTip = cached ? @"暂时未能刷新，仍显示上次成功读取的用量。" : @"无法读取 Codex 用量；请确认已登录 Codex。";
        self.statusItem.menu.itemArray.firstObject.title = cached ? [NSString stringWithFormat:@"暂时未更新（保留上次：%@）", cached] : @"读取失败：请确认 Codex 已登录";
        return;
    }
    NSInteger fiveHourRemaining = MAX(0, MIN(100, 100 - fiveHourUsed.integerValue));
    NSInteger weeklyRemaining = MAX(0, MIN(100, 100 - weeklyUsed.integerValue));
    NSString *display = [NSString stringWithFormat:@"%ld%%(%ld%%)", (long)fiveHourRemaining, (long)weeklyRemaining];
    [[NSUserDefaults standardUserDefaults] setObject:display forKey:@"lastCodexUsageDisplay"];
    self.statusItem.button.title = display;
    NSString *detail = [NSString stringWithFormat:@"5小时剩余 %ld%%（已用 %ld%%）  ·  周剩余 %ld%%（已用 %ld%%）", (long)fiveHourRemaining, (long)fiveHourUsed.integerValue, (long)weeklyRemaining, (long)weeklyUsed.integerValue];
    self.statusItem.button.toolTip = [detail stringByAppendingString:@"\n每分钟自动刷新"];
    self.statusItem.menu.itemArray.firstObject.title = detail;
}

- (void)openUsagePage:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://chatgpt.com/codex/settings/usage"]]; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
