
//
//  TimerWindowController.m
//  SelfControl
//
//  Created by Charlie Stigler on 2/15/09.
//  Copyright 2009 Eyebeam.

// This file is part of SelfControl.
//
// SelfControl is free software:  you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.


#import "TimerWindowController.h"
#import "SCUIUtilities.h"

@interface TimerWindowController ()

@property(nonatomic, readonly) AppController* appController;

@end

@implementation TimerWindowController

- (TimerWindowController*) init {
	if(self = [super init]) {
        settings_ = [SCSettings sharedSettings];
        
		// We need a block to prevent us from running multiple copies of the "Add to Block"
		// sheet.
		modifyBlockLock = [[NSLock alloc] init];
	
        numStrikes = 0;
	}

	return self;
}

- (void)awakeFromNib {
	[[self window] center];
	[[self window] makeKeyAndOrderFront: self];

	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

	NSWindow* window = [self window];

	[window center];

	if([defaults boolForKey:@"TimerWindowFloats"])
		[window setLevel: NSFloatingWindowLevel];
	else
		[window setLevel: NSNormalWindowLevel];

	[window setHidesOnDeactivate: NO];

	[window makeKeyAndOrderFront: self];

    // make the kill-block button red so it's extra noticeable
    NSMutableAttributedString* killBlockMutableAttributedTitle = [killBlockButton_.attributedTitle mutableCopy];
    [killBlockMutableAttributedTitle addAttribute: NSForegroundColorAttributeName value: [NSColor systemRedColor] range: NSMakeRange(0, killBlockButton_.title.length)];
    [killBlockMutableAttributedTitle applyFontTraits: NSBoldFontMask range: NSMakeRange(0, killBlockButton_.title.length)];
    killBlockButton_.attributedTitle = killBlockMutableAttributedTitle;

	killBlockButton_.hidden = YES;
	addToBlockButton_.hidden = NO;
    extendBlockButton_.hidden = NO;

    if ([SCBlockUtilities modernBlockIsRunning]) {
        blockEndingDate_ = [settings_ valueForKey: @"BlockEndDate"];
    } else {
        // legacy block!
        blockEndingDate_ = [SCMigrationUtilities legacyBlockEndDate];
        
        // if it's a legacy block, we will disable some features
        // since it's too difficult to get these working across versions.
        // the user will just have to wait until their next block to do these things!
        if ([SCBlockUtilities legacyBlockIsRunning]) {
            addToBlockButton_.enabled = YES;
            extendBlockButton_.enabled = YES;
        }
    }

    blocklistTeaserLabel_.stringValue = [SCUIUtilities blockTeaserStringWithMaxLength: 45];
	[self updateTimerDisplay: nil];

	timerUpdater_ = [NSTimer timerWithTimeInterval: 1.0
											target: self
										  selector: @selector(updateTimerDisplay:)
										  userInfo: nil
										   repeats: YES];

	//If the dialog isn't focused, instead of getting a NSTimer, we get null.
	//Scheduling the timer from the main thread seems to work.
	[self performSelectorOnMainThread: @selector(hackAroundMainThreadtimer:) withObject: timerUpdater_ waitUntilDone: YES];
    
    [NSTimer scheduledTimerWithTimeInterval: 1.0 repeats: NO block:^(NSTimer * _Nonnull timer) {
        [SCUIUtilities promptBrowserRestartIfNecessary];
    }];
    
    // the timer is a good time to prompt them to enable error reporting! nothing else is happening
    [NSTimer scheduledTimerWithTimeInterval: 3.0 repeats: NO block:^(NSTimer * _Nonnull timer) {
        [SCSentry showErrorReportingPromptIfNeeded];
    }];
}

- (void)blockEnded {
    [timerUpdater_ invalidate];
    timerUpdater_ = nil;

    [timerLabel_ setStringValue: NSLocalizedString(@"Block not active", @"block not active string")];
    [timerLabel_ setFont: [[NSFontManager sharedFontManager]
                           convertFont: [timerLabel_ font]
                           toSize: 37]
     ];

    [timerLabel_ sizeToFit];

    [self resetStrikes];
    
    [SCSentry addBreadcrumb: @"Block ended and timer window is closing" category: @"app"];
}


- (void)hackAroundMainThreadtimer:(NSTimer*)timer{
	[[NSRunLoop currentRunLoop] addTimer: timer forMode: NSDefaultRunLoopMode];
}

- (void)updateTimerDisplay:(NSTimer*)timer {
	// update UI for the whole app, in case the block is done with
    [self.appController performSelectorOnMainThread:@selector(refreshUserInterface)
                                         withObject:nil
                                      waitUntilDone:NO];

    NSString* finishingString = NSLocalizedString(@"Finishing", @"String shown when waiting for finished block to clear");
	int numSeconds = (int) [blockEndingDate_ timeIntervalSinceNow];
	int numHours;
	int numMinutes;

    // if we're already showing "Finishing", but the block timer isn't clearing,
    // keep track of that, so we can take drastic measures if necessary.
	if(numSeconds < 0 && [timerLabel_.stringValue isEqualToString: finishingString]) {
		[[NSApp dockTile] setBadgeLabel: nil];

		// This increments the strike counter.  After ten strikes of the timer being
		// at or less than 0 seconds, SelfControl will assume something's wrong and enable
		// manual block removal
		numStrikes++;

		if(numStrikes > 10) {
			// OK, this is taking longer than it should. Enable manual block removal.
            if (numStrikes == 10) {
                NSLog(@"WARNING: Block should have ended a minute ago! Probable failure to remove.");
                NSError* err = [SCErr errorWithCode: 105];
                [SCSentry captureError: err];
            }

			addToBlockButton_.hidden = YES;
            extendBlockButton_.hidden = YES;
			killBlockButton_.hidden = NO;
		}

		return;
	}

	numHours = (numSeconds / 3600);
	numSeconds %= 3600;
	numMinutes = (numSeconds / 60);
	numSeconds %= 60;

    NSString* timeString;
    if (numHours > 0 || numMinutes > 0 || numSeconds > 0) {
        timeString = [NSString stringWithFormat: @"%0.2d:%0.2d:%0.2d",
                      numHours,
                      numMinutes,
                      numSeconds];
    } else {
        // It usually takes 5-15 seconds after a block finishes for it to turn off
        // so show "Finishing" instead of "00:00:00" to avoid user worry and confusion!
        timeString = finishingString;
    }

	[timerLabel_ setStringValue: timeString];
	[timerLabel_ setFont: [[NSFontManager sharedFontManager]
						   convertFont: [timerLabel_ font]
						   toSize: 42]
	 ];

	[timerLabel_ sizeToFit];
	[timerLabel_ setFrame:NSRectFromCGRect(CGRectMake(0, timerLabel_.frame.origin.y, self.window.frame.size.width, timerLabel_.frame.size.height))];
	[self resetStrikes];
    
	if([[NSUserDefaults standardUserDefaults] boolForKey: @"BadgeApplicationIcon"] && [blockEndingDate_ timeIntervalSinceNow] > 0) {
		// We want to round up the minutes--standard when we aren't displaying seconds.
		if(numSeconds > 0 && numMinutes != 59) {
			numMinutes++;
		}

		NSString* badgeString = [NSString stringWithFormat: @"%0.2d:%0.2d",
								 numHours,
								 numMinutes];
		[[NSApp dockTile] setBadgeLabel: badgeString];
	} else {
		// If we aren't using badging, set the badge string to be
		// empty to remove any badge if there is one.
		[[NSApp dockTile] setBadgeLabel: nil];
	}
    
    // make sure add to list is disabled if it's an allowlist block
    // don't worry about it for a legacy block! the buttons are disabled anyway so it doesn't matter
    if ([SCBlockUtilities modernBlockIsRunning]) {
        addToBlockButton_.hidden = [settings_ boolForKey: @"ActiveBlockAsWhitelist"];
    }
}

- (void)windowShouldClose:(NSNotification *)notification {
	// Hack to make the application terminate after the last window is closed, but
	// INCLUDE the HUD-style timer window.
	if(![[self.appController initialWindow] isVisible]) {
		[NSApp terminate: self];
	}
}

- (IBAction) addToBlock:(id)sender {
	// Check if there's already a thread trying to modify the block.  If so, don't make
	// another.
	if(![modifyBlockLock tryLock]) {
		return;
	}

    [self.window beginSheet: addSheet_ completionHandler:^(NSModalResponse returnCode) {
        [self->addSheet_ orderOut: self];
    }];

	[modifyBlockLock unlock];
}

- (IBAction) extendBlockTime:(id)sender {
    // Check if there's already a thread trying to modify the block.  If so, don't make
    // another.
    if(![modifyBlockLock tryLock]) {
        return;
    }
    
    [self.window beginSheet: extendBlockTimeSheet_ completionHandler:^(NSModalResponse returnCode) {
        [self->extendBlockTimeSheet_ orderOut: self];
    }];
    
    [modifyBlockLock unlock];
}

- (IBAction) closeAddSheet:(id)sender {
	[NSApp endSheet: addSheet_];
}
- (IBAction) closeExtendSheet:(id)sender {
    [NSApp endSheet: extendBlockTimeSheet_];
}

- (IBAction) performAddSite:(id)sender {
	NSString* addToBlockTextFieldContents = [addToBlockTextField_ stringValue];
	[self.appController addToBlockList: addToBlockTextFieldContents lock: modifyBlockLock];
	[NSApp endSheet: addSheet_];
}

- (IBAction) performExtendBlock:(id)sender {
    NSInteger extendBlockMinutes = (extendBlockHoursField_.intValue * 60) + extendBlockMinutesField_.intValue;
        
    [self.appController extendBlockTime: extendBlockMinutes lock: modifyBlockLock];
    [NSApp endSheet: extendBlockTimeSheet_];
}

- (void)configurationChanged {
    if ([SCBlockUtilities modernBlockIsRunning]) {
        blockEndingDate_ = [settings_ valueForKey: @"BlockEndDate"];
    } else {
        // legacy block!
        blockEndingDate_ = [SCMigrationUtilities legacyBlockEndDate];
    }
    
    // update the blocklist teaser in case that changed
    blocklistTeaserLabel_.stringValue = [SCUIUtilities blockTeaserStringWithMaxLength: 45];
    [self updateTimerDisplay: nil];
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
}

// see updateTimerDisplay: for an explanation
- (void)resetStrikes {
	numStrikes = 0;
}

- (IBAction)killBlock:(id)sender {
	AuthorizationRef authorizationRef;
	char* helperToolPath = [self selfControlKillerHelperToolPathUTF8String];
	NSUInteger helperToolPathSize = strlen(helperToolPath);
	AuthorizationItem right = {
		kAuthorizationRightExecute,
		helperToolPathSize,
		helperToolPath,
		0
	};
	AuthorizationRights authRights = {
		1,
		&right
	};
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults |
	kAuthorizationFlagExtendRights |
	kAuthorizationFlagInteractionAllowed;
	OSStatus status;

	status = AuthorizationCreate (&authRights,
								  kAuthorizationEmptyEnvironment,
								  myFlags,
								  &authorizationRef);

	if(status) {
        if (status != AUTH_CANCELLED_STATUS) {
            NSError* err = [SCErr errorWithCode: 501];
            [SCSentry captureError: err];
        }
        return;
	}
    
    // we're about to launch a helper tool which will read settings, so make sure the ones on disk are valid
    [settings_ synchronizeSettings];

	char uidString[10];
	snprintf(uidString, sizeof(uidString), "%d", getuid());

	char* args[] = { uidString, NULL };
    
    
    FILE* pipe = NULL;
	status = AuthorizationExecuteWithPrivileges(authorizationRef,
												helperToolPath,
												kAuthorizationFlagDefaults,
												args,
												&pipe);
    
	if(status) {
		NSLog(@"WARNING: Authorized execution of helper tool returned failure status code %d", status);

        NSError* err = [SCErr errorWithCode: 400];
        [SCSentry captureError: err];
        [SCUIUtilities presentError: err];

		return;
	}
    
    // read until the pipe finishes so we wait for execution to end before we
    // show the modal (this also helps make the focus ordering better)
    for (;;) {
        ssize_t bytesRead = read(fileno(pipe), NULL, 256);
        if (bytesRead < 1) break;
    }
        
    // reload settings so the timer window knows the block is done
    [[SCSettings sharedSettings] reloadSettings];
        
    // update the UI _before_ we run the alert,
    // so the main window doesn't steal the focus from the alert
    // (and after we've synced settings so we know things have changed)
    [self.appController performSelectorOnMainThread:@selector(refreshUserInterface)
                                         withObject:nil
                                      waitUntilDone:YES];
    
    // send some debug info to Sentry to help us track this issue
    [SCSentry captureMessage: @"User manually cleared SelfControl block from the timer window"];
//    [SCSentry captureMessage: @"User manually cleared SelfControl block from the timer window" withScopeBlock:^(SentryScope * _Nonnull scope) {
//        SentryAttachment* fileAttachment = [[SentryAttachment alloc] initWithPath: [@"~/Documents/SelfControl-Killer.log" stringByExpandingTildeInPath]];
//        [scope addAttachment: fileAttachment];
//    }];
    
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText: @"Success!"];
    [alert setInformativeText:@"The block was cleared successfully.  You can find the log file, named SelfControl-Killer.log, in your Documents folder. If you're still having issues, please check out the SelfControl FAQ on GitHub."];
    [alert addButtonWithTitle: @"OK"];
    [alert runModal];
}

- (NSString*)selfControlKillerHelperToolPath {
	static NSString* path;

	// Cache the path so it doesn't have to be searched for again.
	if(!path) {
		NSBundle* thisBundle = [NSBundle mainBundle];
		path = [thisBundle pathForAuxiliaryExecutable: @"SCKillerHelper"];
	}

	return path;
}
- (char*)selfControlKillerHelperToolPathUTF8String {
	static char* path;

	// Cache the converted path so it doesn't have to be converted again
	if(!path) {
		path = malloc(512);
		[[self selfControlKillerHelperToolPath] getCString: path
												 maxLength: 512
												  encoding: NSUTF8StringEncoding];
	}

	return path;
}

- (void)dealloc {
	[timerUpdater_ invalidate];
}

#pragma mark - Properties

- (AppController *)appController
{
    AppController* controller = (AppController *)[NSApp delegate];
    return controller;
}

@end
