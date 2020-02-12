/* DATXtract - an application for reading audio DAT tapes

   Copyright © 2002-2007 Peter DiCamillo

   This code is distributed under the license specified by the COPYING file
   at the top-level directory of this distribution.                         */

#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/scsi-commands/SCSITaskLib.h>

#define DATA_MODE 0
#define AUDIO_MODE 1
#define DAT_FRAME_SIZE 5822
#define DAT_FRAME_SIZE_MSB 0x16
#define DAT_FRAME_SIZE_LSB 0xbe

typedef struct DriveInfo {
    char	vendorID[9];
    char	productID[17];
    char	firmwareRevLevel[5];
} DriveInfo;

void blank_trim(char *);
void get_sense_string(char *str, UInt8 key, UInt8 ASC, UInt8 ASCQ,
                      UInt16 code, Boolean addRawValues);

@interface DATDrive : NSObject {
    id owner;
    io_service_t drive_service;
    SCSITaskDeviceInterface **interface;
    IOCFPlugInInterface **plugInInterface;
    IOVirtualRange global_range;
}

- (id) init;
- (void) setOwnerObject:(id)the_owner;
- (void) writeToLog:(char *)logtext;
- (int) locateDrive;
- (int) setupInterface;
- (void) releaseInterface;
- (int) TestUnitReady:(int *)status withString:(char *)status_string
            withKey:(UInt8 *)result_key withCode:(UInt16 *)result_code;
- (int) Inquiry:(DriveInfo *)info;
- (int) getMyMode:(int *)current_mode;
- (int) setMyMode:(int)mode_wanted;
- (int) loadUnload:(Boolean)do_unload
            withCallback:(SCSITaskCallbackFunction)the_callback;
- (int) readWithBuffer:(unsigned char *)buff
            withCallback:(SCSITaskCallbackFunction)the_callback;

@end
