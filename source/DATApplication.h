/* DATXtract - an application for reading audio DAT tapes

   Copyright © 2002-2007 Peter DiCamillo

   This code is distributed under the license specified by the COPYING file
   at the top-level directory of this distribution.                         */

#import <Cocoa/Cocoa.h>
#import <DATController.h>

@interface DATApplication : NSApplication
{
    DATController *myController;
}

- (void) setMyController:(DATController *)theController;
- (void) sendEvent:(NSEvent *)theEvent;

@end
