//
//  ABMessageBox.mm
//  MessageBox
//
//  Created by Adam Bell on 2013-04-13.
//  Copyright (c) 2013 Adam Bell. All rights reserved.
//


#import "ABMessageBox.h"

#define XPCObjects "/System/Library/PrivateFrameworks/XPCObjects.framework/XPCObjects"
#define libGPUSupport "/System/Library/PrivateFrameworks/GPUSupport.framework/libGPUSupport.dylib"
#define libGPUSupportMercury "/System/Library/PrivateFrameworks/GPUSupport.framework/libGPUSupportMercury.dylib"
#define GPUSupport "/System/Library/PrivateFrameworks/GPUSupport.framework/GPUSupport"

CHDeclareClass(UIWindow);
CHDeclareClass(UITextEffectsWindow);
CHDeclareClass(SBUIController);
CHDeclareClass(UIViewController);

static BKSProcessAssertion *keepAlive;

@implementation ABMessageBox

-(id)init
{
	if ((self = [super init]))
	{
	}
    
    return self;
}

@end

static void forceFacebookApplicationRotation(UIInterfaceOrientation orientation)
{
    switch (orientation)
    {
        case 0:
        case UIInterfaceOrientationPortrait:
            notify_post(ROTATION_PORTRAIT_NOTIFICATION);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            notify_post(ROTATION_PORTRAIT_UPSIDEDOWN_NOTIFICATION);
            break;
        case UIInterfaceOrientationLandscapeLeft:
            notify_post(ROTATION_LANDSCAPE_LEFT_NOTIFICATION);
            break;
        case UIInterfaceOrientationLandscapeRight:
            notify_post(ROTATION_LANDSCAPE_RIGHT_NOTIFICATION);
            break;
        default:
            break;
    }
}

// Fix Facebook app rotation when application quits to SpringBoard

CHOptimizedMethod0(self, void, SBUIController, finishedUnscattering)
{
    CHSuper0(SBUIController, finishedUnscattering);
    
    UIInterfaceOrientation orientation = [UIDevice currentDevice].orientation;
    
    forceFacebookApplicationRotation(orientation);
}


CHOptimizedMethod3(self, void, SBUIController, window, UIWindow *, window, willRotateToInterfaceOrientation, UIInterfaceOrientation, orientation, duration, NSTimeInterval, duration)
{
    CHSuper3(SBUIController, window, window, willRotateToInterfaceOrientation, orientation, duration, duration);
    
    forceFacebookApplicationRotation(orientation);
}

CHDeclareMethod0(void, SBUIController, hookFacebook)
{
    // Thanks to http://stackoverflow.com/questions/6610705/how-to-get-process-id-in-iphone-or-ipad
    // Faster than ps,grep,etc
    
    int pid = 0;
    
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;
    
    size_t size;
    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    
    struct kinfo_proc * process = NULL;
    struct kinfo_proc * newprocess = NULL;
    
    do {
        
        size += size / 10;
        newprocess = (kinfo_proc *)realloc(process, size);
        
        if (!newprocess)
        {
            if (process){
                free(process);
            }
            return;
        }
        
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
        
    } while (st == -1 && errno == ENOMEM);
    
    if (st == 0)
    {
        
        if (size % sizeof(struct kinfo_proc) == 0)
        {
            int nprocess = size / sizeof(struct kinfo_proc);
            
            if (nprocess)
            {
                for (int i = nprocess - 1; i >= 0; i--)
                {
                    NSString * processID = [[NSString alloc] initWithFormat:@"%d", process[i].kp_proc.p_pid];
                    NSString * processName = [[NSString alloc] initWithFormat:@"%s", process[i].kp_proc.p_comm];
                    
                    if ([processName rangeOfString:@"Facebook"].location != NSNotFound)
                    {
                        pid = [processID intValue];
                    }
                }
                
                free(process);
            }
        }
    }
    if (pid == 0)
    {
        DebugLog(@"GET PROCESS FACEBOOK FAILED.");
    }
    
    
    // Need a BKSProcessAssertion to keep the app from being killed / allow the UI thread to work even when suspended
    
    keepAlive = [[BKSProcessAssertion alloc] initWithPID:pid
                                                   flags:1
                                                  reason:kProcessAssertionReasonBackgroundUI
                                                    name:@"epichax"
                                             withHandler:^void (void)
                 {
                     DebugLog(@"FACEBOOK PID: %d kept alive: %@", pid, [keepAlive valid] > 0 ? @"TRUE" : @"FALSE");
                 }];
    
    SBApplication *fb = [[NSClassFromString(@"SBApplicationController") sharedInstance] applicationWithDisplayIdentifier:@"com.facebook.Facebook"];
    
    UIView *fbView = [fb contextHostViewForRequester:@"hax" enableAndOrderFront:YES];
    fbView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    fbView.alpha = 0.0;
    [[ABMessageBoxWindow sharedInstance] addSubview:fbView];
    
    // Show the Chat Heads after the rest of the Facebook app has been hidden / finished animating
    
    [UIView animateWithDuration:0.0
                          delay:0.9
                        options:0
                     animations:^{
                         fbView.alpha = 1.0;
                     } completion:^(BOOL finished) {
                         //
                     }];    
}

CHOptimizedMethod0(self, void, UIWindow, makeKeyAndVisible)
{
    CHSuper0(UIWindow, makeKeyAndVisible);
    
    // Create the Chat Head window once, and only when in SpringBoard
    
    if (![self isKindOfClass:[ABMessageBoxWindow class]] && [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
    {
        ABMessageBoxWindow *messageBoxWindow = [ABMessageBoxWindow sharedInstance];
        messageBoxWindow.windowLevel = 10; //1 below UIKeyboard //UIWindowLevelStatusBar;
        messageBoxWindow.hidden = NO;
        messageBoxWindow.backgroundColor = [UIColor clearColor];
    }
}

// Force the keyboard to not completely overtake the Chat Heads window

CHOptimizedMethod0(self, int, UITextEffectsWindow, windowLevel)
{
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive)
        return 9;
    return CHSuper0(UITextEffectsWindow, windowLevel);
}


CHOptimizedMethod1(self, void, UITextEffectsWindow, setWindowLevel, int, windowLevel)
{
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive)
        CHSuper1(UITextEffectsWindow, setWindowLevel, 9);
    else
        CHSuper1(UITextEffectsWindow, setWindowLevel, windowLevel);
}

CHOptimizedMethod4(self, void, UIViewController, _willRotateToInterfaceOrientation, UIInterfaceOrientation, orientation, duration, NSTimeInterval, duration, forwardToChildControllers, BOOL, forward, skipSelf, BOOL, skipSelf)
{
    CHSuper4(UIViewController, _willRotateToInterfaceOrientation, orientation, duration, duration, forwardToChildControllers, forward, skipSelf, skipSelf);
    
    DebugLog(@"ROTATING");
    
    forceFacebookApplicationRotation(orientation);
}

static void fbLaunching(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    if (keepAlive != nil)
    {
        // Kill the BKSProcessAssertion because it isn't needed anymore
        // Not sure if creating / removing it is necessary but I'd like to keep it as stock as possible when in app)
        
        [keepAlive invalidate];
        keepAlive = nil;
        
        SBApplication *fb = [[NSClassFromString(@"SBApplicationController") sharedInstance] applicationWithDisplayIdentifier:@"com.facebook.Facebook"];
        [[fb contextHostManager] disableHostingForRequester:@"hax"];
        
        for (UIView *subview in [[[ABMessageBoxWindow sharedInstance] subviews] copy])
        {
            [subview removeFromSuperview];
        }
    }
}

static void fbQuitting(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    [[NSClassFromString(@"SBUIController") sharedInstance] hookFacebook];
}

static void fb_gpusKillClient()
{
    DebugLog(@"OpenGL... no u");
    
    return;
}

static void fb_gpus_ReturnNotPermittedKillClient()
{
    DebugLog(@"OpenGL... no u");
    
    return;
}

static void (*orig_gpus_ReturnNotPermittedKillClient)();
static void (*orig_gpus_ReturnNotPermittedKillClient2)();
static void (*orig_gpusKillClient)();

static int fb_XPConnectionHasEntitlement(NSString *string)
{
    DebugLog(@"XPCConnectionHasEntitlement... no u");
    return 1;
}

static int (*orig_XPConnectionHasEntitlement)(NSString *string);

CHConstructor
{
    @autoreleasepool
    {
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.facebook.Facebook"])
            return;
        
        CHLoadLateClass(UIWindow);
        CHLoadLateClass(UITextEffectsWindow);
        CHLoadLateClass(UIViewController);
        
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"])
        {
            // UIKeyboard in Messages likes to try to stay overtop the Chat Heads window so... no u
            
            CHHook0(UITextEffectsWindow, windowLevel);
            CHHook1(UITextEffectsWindow, setWindowLevel);
        }
        
        CHHook4(UIViewController, _willRotateToInterfaceOrientation, duration, forwardToChildControllers, skipSelf);        
        
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
        {
            // Easiest way to communicate inter-app
            
            CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
            CFNotificationCenterAddObserver(darwin, NULL, fbLaunching, CFSTR("ca.adambell.MessageBox.fbLaunching"), NULL, CFNotificationSuspensionBehaviorCoalesce);
            CFNotificationCenterAddObserver(darwin, NULL, fbQuitting, CFSTR("ca.adambell.MessageBox.fbQuitting"), NULL, CFNotificationSuspensionBehaviorCoalesce);
            
            CHLoadLateClass(SBUIController);
            
            CHHook0(UIWindow, makeKeyAndVisible);
            CHHook0(SBUIController, finishedUnscattering);
            CHHook3(SBUIController, window, willRotateToInterfaceOrientation, duration);
        }
        
        // Need to go lower to hook backboardd stuff
        // Load appropriate libraries to be hooked
        
        dlopen(XPCObjects, RTLD_LAZY);
        dlopen(libGPUSupport, RTLD_LAZY);
        dlopen(libGPUSupportMercury, RTLD_LAZY);
        
        // Gotta hook the XPC entitlement function since the facebook app isn't signed with the proper assertion entitlements
        
        MSHookFunction(((int *)MSFindSymbol(NULL, "_XPCConnectionHasEntitlement")), (int *)fb_XPConnectionHasEntitlement, (int **)orig_XPConnectionHasEntitlement);
        
        // Gotta hook some OpenGL exeption handlers so they don't crash the app
        
        MSHookFunction(((int *)MSFindSymbol(NULL, "_gpus_ReturnNotPermittedKillClient")), (int *)fb_gpus_ReturnNotPermittedKillClient, (int **)orig_gpus_ReturnNotPermittedKillClient);
        MSHookFunction(((int *)MSFindSymbol(NULL, "_gpus_ReturnNotPermittedKillClient")), (int *)fb_gpus_ReturnNotPermittedKillClient, (int **)orig_gpus_ReturnNotPermittedKillClient2);
        MSHookFunction(((int *)MSFindSymbol(NULL, "_gpusKillClient")), (int *)fb_gpusKillClient, (int **)orig_gpusKillClient);
    }
}