/* DATXtract - an application for reading audio DAT tapes

   Copyright © 2002-2007 Peter DiCamillo

   This code is distributed under the license specified by the COPYING file
   at the top-level directory of this distribution.                         */

#import "DATApplication.h"

@implementation DATApplication

- (void) setMyController:(DATController *)theController
{
    myController = theController;
}

- (void)sendEvent:(NSEvent *)theEvent
{
    if ([theEvent type] == NSApplicationDefined) {
        [myController handleCustomEvent:theEvent];
        }
    else {
        [super sendEvent:theEvent];
        }
}
@end
