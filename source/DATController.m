/* DATXtract - an application for reading audio DAT tapes

   Copyright © 2002-2007 Peter DiCamillo

   This code is distributed under the license specified by the COPYING file
   at the top-level directory of this distribution.                         */

#import <sys/stat.h>
#import <fcntl.h>
#import "DATController.h"
#import "DATApplication.h"
#import "LP_tables.h"

@implementation DATController

// initialization before any other message
+(void)initialize {
	NSString *userDefaultsValuesPath;
	NSDictionary *userDefaultsValuesDict;
	
	// define defaults
	userDefaultsValuesPath = [[NSBundle mainBundle] pathForResource:@"UserDefaults"
                               ofType:@"plist"];
	userDefaultsValuesDict = [NSDictionary dictionaryWithContentsOfFile:userDefaultsValuesPath];
	
	// register defaults
	[[NSUserDefaults standardUserDefaults] registerDefaults:userDefaultsValuesDict];
}

// initialization after loading the nib file
-(void)awakeFromNib {
    SEL theSelector;
    NSMethodSignature *aSignature;
    NSInvocation *statusInvocation;

// initialize variables
    need_drive_info = true;
    drive_ready = false;
    need_ready_transition = false;
    stop_timer = false;
    need_initial_positioning = true;
    doing_unload = false;
    reading_position = false;
    first_frame = false;
    stop_requested = false;
    pause_requested = false;
    have_data_handle = false;
    have_info_handle = false;
	have_log_handle = false;
	log_file_open = false;

// read settings from NSUserDefault
	readAtProgramStart = [[NSUserDefaults standardUserDefaults] boolForKey:@READ_AT_PROGRAM_START_KEY];
	fileForEachProgram = [[NSUserDefaults standardUserDefaults] boolForKey:@FILE_FOR_EACH_PROGRAM_KEY];
	includeErrorFrames = [[NSUserDefaults standardUserDefaults] boolForKey:@INCLUDE_ERROR_FRAMES_KEY];
	errorLimit = [[NSUserDefaults standardUserDefaults] integerForKey:@ERROR_LIMIT_KEY];
	writeMetadata = [[NSUserDefaults standardUserDefaults] boolForKey:@WRITE_METADATA_KEY];
	writeLog = [[NSUserDefaults standardUserDefaults] boolForKey:@WRITE_LOG_KEY];

// validate the settings
	if (errorLimit < 0) errorLimit = DEFAULT_ERROR_LIMIT;

// write out the values
// this forces a plist file to be created with the current values if there wasn't one
	[self updateDefaultsPrefs];

// set the preference values in the main window
	[self updateActivePrefs];

// set the initial values for the preferences window
	[self updateWindowPrefs];

// initialize log with starting message
    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:@"Starting up: "];
    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:
        [[NSCalendarDate calendarDate]
        descriptionWithCalendarFormat:@"%b %d, %Y %H:%M:%S"]];
    
// create our tape drive object
    theDrive = [[DATDrive alloc] init];

// allow drive object to write to our log
    [theDrive setOwnerObject:self];
    
// tell app object about us for custom event
    [(DATApplication *)NSApp setMyController:self];

// set up invocation for drive status
    theSelector = @selector(updateDriveStatus);
    aSignature = [DATController instanceMethodSignatureForSelector:theSelector];
    statusInvocation = [NSInvocation invocationWithMethodSignature:aSignature];
    [statusInvocation setSelector:theSelector];
    [statusInvocation setTarget:self];
    
// invoke now to get started
    [statusInvocation invoke];

// start timer
    statusTimer = [NSTimer scheduledTimerWithTimeInterval:3
                    invocation:statusInvocation
                    repeats:YES];
}

// called by timer
- (void) updateDriveStatus {

    Boolean new_drive_ready;
    
    if (stop_timer) return;
    [self do_updateDriveStatus:&new_drive_ready];
    if (new_drive_ready != drive_ready) {
        drive_ready = new_drive_ready;
        stop_timer = true;
        [self driveReadyChanged];
        }
}

// unconditional update
- (void) do_updateDriveStatus:(Boolean *)is_ready {

    DriveInfo theInfo;
    int result;
    int drive_status;
    char infomsg[128];
    NSString *infostring;
    char statustext[256];
    UInt8 key;
    UInt16 code;
	time_t start_time;
	time_t elapsed_time;

    *is_ready = false;

    // get info and status for the drive
    result = [theDrive locateDrive];
    if (result == 0) {
        result = [theDrive setupInterface];
	}

    if (result != 0) {
        [driveInfo setStringValue:@""];
        [driveStatus setStringValue:@"Not found"];
        need_drive_info = true;
        return;
        }
    
	if ([insertingTapeCheckbox state] > 0) {
        [driveStatus setStringValue:@"Inserting tape set"];
		[theDrive releaseInterface];
		return;
		}

	start_time = time(NULL);
    result = [theDrive TestUnitReady:&drive_status withString:statustext
                            withKey:&key withCode:&code];
	elapsed_time = time(NULL) - start_time;

	// check if the drive is responding
	if (elapsed_time >= 4) {
        [driveStatus setStringValue:@"Drive found but not responding"];
		[self writeToLog:"Drive is not responding."];
		[self writeToLog:"Quit DATXtract, correct the problem, and re-launch."];
		[theDrive releaseInterface];
		stop_timer = true;
		return;
		}

    // if unit attention, check for ready and clear it
    if (result == 0) {
        if (drive_status == kSCSITaskStatus_CHECK_CONDITION) {
            if ((key == 6) && (code == 0x2800)) {
                need_ready_transition = false;
                }
            result = [theDrive TestUnitReady:&drive_status withString:statustext
                      withKey:&key withCode:&code];
           }
        }

    if (result == 0) {
        if (drive_status != kSCSITaskStatus_GOOD) {
            need_ready_transition = true;
            need_initial_positioning = true;
            [timeText setStringValue:@""];
            [attrText setStringValue:@""];
            [errorText setStringValue:@""];
            }
        if ((drive_status == kSCSITaskStatus_GOOD) && need_ready_transition) {
            drive_status = kSCSITaskStatus_No_Status;
            [driveStatus setStringValue:@"Loading tape"];
            }
        else {
            infostring = [[NSString alloc] initWithCString:statustext]; 
            [driveStatus setStringValue:infostring];
            [infostring release];
            }
        if (drive_status == kSCSITaskStatus_GOOD) *is_ready = true;
        }
    else {
        [driveStatus setStringValue:@"Error getting drive status"];
        need_drive_info = true;
        }

	if (need_drive_info) {
        memset(&theInfo, 0, sizeof(DriveInfo));
        result = [theDrive Inquiry:&theInfo];
        if (result == 0) {
            if ((strlen(theInfo.vendorID) == 0) &&
                (strlen(theInfo.productID) == 0) &&
                (strlen(theInfo.firmwareRevLevel) == 0)) {
                strcpy(infomsg, "Not available");
                if (drive_status == 0) {
                    [driveStatus setStringValue:@"Not responding"];
                    }
                }
            else {
                strcpy(infomsg, theInfo.vendorID);
                strcat(infomsg, " ");
                strcat(infomsg, theInfo.productID);
                strcat(infomsg, " ");
                strcat(infomsg, theInfo.firmwareRevLevel);
                need_drive_info = false;
                 }
            infostring = [[NSString alloc] initWithCString:infomsg]; 
            [driveInfo setStringValue:infostring];
            [infostring release];
            }
        else {
            [driveStatus setStringValue:@"Error getting drive info"];
            }
        }
        
    [theDrive releaseInterface];
}


- (void) handleCustomEvent:(NSEvent *)theEvent {
 
   // subtype 1 is finished tape load
   if ([theEvent subtype] == LOAD_EVENT_SUBTYPE) {
        [self endLoad];
        }

    // subtype 2 is finished read
    if ([theEvent subtype] == READ_EVENT_SUBTYPE) {
        [self endRead];
        }

    // subtype 3 is finished unload
    if ([theEvent subtype] == UNLOAD_EVENT_SUBTYPE) {
        // do nothing
        }

}

- (void) writeToLog:(char *)logtext {

    NSString *logstring = [[NSString alloc] initWithCString:logtext];
    
    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:@"\n"];

    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:logstring];

    [logText scrollRangeToVisible:NSMakeRange([[logText string] length]-1, 0)];

    [logstring release];

	if (log_file_open) {
		[logfile writeData:[NSData dataWithBytes:logtext length:strlen(logtext)]];		
		[logfile writeData:[NSData dataWithBytes:"\n" length:1]];		
		}
}

- (void) driveReadyChanged {

    int result;
    Boolean did_load;

    // changed to not ready- keep button disabled,
    // go back to showing status
    [readButton setEnabled:false];
    [rewindButton setEnabled:false];
    [ejectButton setEnabled:false];
    if (!drive_ready) {
        stop_timer = false;
        return;
        }

    // if drive is in data mode, set audio mode,
    // and reload tape

    // prepare to use drive
    result = [theDrive locateDrive];
    if (result == 0) {
        result = [theDrive setupInterface];
	}
    if (result != 0) {
        [self writeToLog:"Unable to setup drive interface"];
        drive_ready = false;
        stop_timer = false;
        return;
        }
    
    // set audio mode
    result = [self setAudioMode:&did_load];
    if (result != 0) {
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        return;
        }

    if (did_load) {
        [driveStatus setStringValue:@"Loading tape in audio mode"];
        }
    else {
        if (need_initial_positioning) {
            [self positionTape];
            }
        else {
            [self driveReadyOk];
            }
        }
}

- (void) driveReadyOk {

        [theDrive releaseInterface];
        [driveStatus setStringValue:@"Ready"];
        stop_timer = false;
        [readButton setEnabled:true];
        [rewindButton setEnabled:true];
        [ejectButton setEnabled:true];

}

- (void) endLoad
{
    if (doing_unload) {
        doing_unload = false;
        if (loadStatus != kSCSITaskStatus_GOOD) {
            [self writeToLog:"Unload failed"];
            }
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        }
    else {
        if (loadStatus != kSCSITaskStatus_GOOD) {
            [self writeToLog:"Load failed"];
            [theDrive releaseInterface];
            drive_ready = false;
            stop_timer = false;
            }
        else {
            if (need_initial_positioning) {
                [self positionTape];
                }
            else {
                [self driveReadyOk];
                }
            }
        }
}

- (int) setAudioMode:(Boolean *)did_load {

    int result;
    int mode;

    *did_load = false;
    
    // check for audio mode
    result = [theDrive getMyMode:&mode];
    if (result != 0) {
        [self writeToLog:"Unable to get drive mode"];
        return result;
        }

    if (mode == AUDIO_MODE) return 0;
    
    // set audio mode and load tape
    // set mode
    result = [theDrive setMyMode:AUDIO_MODE];    
    if (result != 0) {
        [self writeToLog:"Unable to set drive mode"];
        return result;
        }

    // make sure it worked
    result = [theDrive getMyMode:&mode];
    if (result != 0) {
        [self writeToLog:"Unable to get drive mode"];
        return result;
        }
    if (mode != AUDIO_MODE) {
	[self writeToLog:"Attempt to set audio mode failed -- "];
	[self writeToLog:"  audio mode may not be supported"];
        return 1;
        }

    // log
    [self writeToLog:"Changed drive mode to audio"];

    // load tape (in audio mode)
    result = [theDrive loadUnload:false withCallback:load_callback];
    if (result != 0) {
        [self writeToLog:"Unable to start load"];
        return result;
        }

    *did_load = true;
    return 0;
}


- (void) endRead
{
    Boolean read_failure = false;
    
    if (readStatus != kSCSITaskStatus_GOOD) {
        [self writeToLog:"Read failed"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        read_failure = true;
        }
    else if (readCount != DAT_FRAME_SIZE) {
        [self writeToLog:"Read too short"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        read_failure = true;
        }
    
    // never called processing routine
    if (first_frame && read_failure) {
        first_frame = false;
        return;
        }
    
    if (reading_position) {
        [self newPositionRead:read_failure];
        }
    else {
        [self newDataRead:read_failure];
        }
    
    first_frame = false;
}

- (void) positionTape
{
    int result;

    read_error_count_left = 0;
    read_error_count_right = 0;
    read_error_count_frames = 0;
    reading_position = true;
    first_frame = true;
    result = [theDrive readWithBuffer:readBuffer withCallback:read_callback];
    if (result != 0) {
        reading_position = false;
        first_frame = false;
        [self writeToLog:"Unable to start positioning read"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        }
    else {
        [driveStatus setStringValue:@"Positioning tape"];
        need_initial_positioning = false;
        }
}

- (void) newPositionRead:(Boolean)cleanup
{
    static unsigned long framecount;
    FrameInfo fi;
    int result;

    if (first_frame) {
        framecount = 0;
        }
    else {
        framecount++;
        }

    if (cleanup) {
        return;
        }

    [self getFrameInfo:&fi withFirst:first_frame];
    [self displayFrameInfo:&fi];

    if ((fi.interpolate_flags == 0) && 
        (strcmp(fi.pnum_text, "0BB") != 0)
        && ((fi.quantization == 0) ||
			(fi.quantization == 1))) {
        reading_position = false;
        [self driveReadyOk];
        return;
        }

    if (framecount > 500) {
        reading_position = false;
        [self driveReadyOk];
        [self writeToLog:"failed to find start of audio"];
        return;
        }

    result = [theDrive readWithBuffer:readBuffer 					withCallback:read_callback];
    if (result != 0) {
        reading_position = false;
        first_frame = false;
        [self writeToLog:"Unable to start read"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        }
}

- (void) newDataRead:(Boolean)cleanup
{
    FrameInfo fi;
    int result;
    static char last_pnum_text[4];
    static Boolean new_program_start;
    char msg[256];
    unsigned long secs_result;
    unsigned char frames;
    char timestring[16];
    Boolean file_result;

    // call to just clean up
    if (cleanup) {
        [self finishAudioFile];
        [pauseButton setEnabled:false];
        [resumeButton setEnabled:false];
        [stopButton setEnabled:false];
        pause_requested = false;
        stop_requested = false;
        [self driveReadyOk];
        return;
        }

    [self getFrameInfo:&fi withFirst:false];
    [self displayFrameInfo:&fi];

    if (first_frame) {
        result = [self initAudioFile:&fi];
        if (result != 0) {
            stop_requested = false;
            [self driveReadyOk];
            return;
            }
        [pauseButton setEnabled:true];
        [stopButton setEnabled:true];
        new_program_start = false;
        }

    if (frames_written == 360) {
        strcpy(last_pnum_text, fi.pnum_text);
        }

    if (frames_written > 360) {
        new_program_start = fi.start_id && (strcmp(last_pnum_text, fi.pnum_text) != 0);
        strcpy(last_pnum_text, fi.pnum_text);
        }

    if (new_program_start) {
        if (fileForEachProgram) {
            // close current file
            [self finishAudioFile];
            [pauseButton setEnabled:false];
            [resumeButton setEnabled:false];
            [stopButton setEnabled:false];
            pause_requested = false;
            stop_requested = false;

            // log new program
            sprintf(msg,
            "New program start\n\tAbs: %s  Prog: %s",
            fi.atime_text, fi.ptime_display_text);
            [self writeToLog:msg];

            // get filename
            file_result = [self getNewFileHandles];
            if (!file_result) {
                [self driveReadyOk];
                return;
                }

            // start new read
            first_frame = true;
            wait_for_prog = false;
            result = [self initAudioFile:&fi];
            if (result != 0) {
                [self driveReadyOk];
                return;
                }
            [pauseButton setEnabled:true];
            [stopButton setEnabled:true];
            new_program_start = false;
            }
        else {
            frames_to_time(frames_written, &secs_result, &frames,
						   fi.quantization);
            get_display_time(secs_result, frames, timestring);
            sprintf(msg,
            "New program start\n\tAbs: %s  Prog: %s\n\tFile: %s",
            fi.atime_text, fi.ptime_display_text, timestring);
            [self writeToLog:msg];
            }
        }

    // process data we just read
    result = [self writeAudioFile:&fi];
    if (result != 0) {
        [self finishAudioFile];
        [pauseButton setEnabled:false];
        [resumeButton setEnabled:false];
        [stopButton setEnabled:false];
        pause_requested = false;
        stop_requested = false;
        [self driveReadyOk];
        return;
        }

    if (stop_requested || errors_exceeded) {
        [pauseButton setEnabled:false];
        [resumeButton setEnabled:false];
        [stopButton setEnabled:false];
        pause_requested = false;
        stop_requested = false;
        [self finishAudioFile];
        [self driveReadyOk];
        return;
        }

    if (pause_requested) {
        [driveStatus setStringValue:@"Read paused"];
        [resumeButton setEnabled:true];
        return;
        }

    result = [theDrive readWithBuffer:readBuffer withCallback:read_callback];
    if (result != 0) {
        [pauseButton setEnabled:false];
        [resumeButton setEnabled:false];
        [stopButton setEnabled:false];
        pause_requested = false;
        stop_requested = false;
        first_frame = false;
        [self writeToLog:"Unable to start new read"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        [self finishAudioFile];
        }
}

- (void) getFrameInfo:(FrameInfo *)fi withFirst:(Boolean)first
{
    unsigned char d, msd, nsd, lsd;
    unsigned char subcode_count;
    unsigned char *sc;
    short i;
    Boolean numhrs, nummins, numsecs, numframes;
    unsigned char hrsval, minsval, secsval, framesval;
    static Boolean have_current_pnum;
    static Boolean have_current_index;
    static Boolean have_ptime_offset;
    static Boolean last_frame_start_id;
    static char current_pnum_text[5];
    static char current_index_text[3];
    static unsigned long ptime_offset;
    
    if (first) {
        have_current_pnum = false;
        have_current_index = false;
        have_ptime_offset = false;
        last_frame_start_id = false;
        }

    memset(fi, 0, sizeof(FrameInfo));

    d = readBuffer[5816];
    fi->priority_id = (d & 0x80) != 0;
    fi->start_id = (d & 0x40) != 0;
    fi->skip_id = (d & 0x20) != 0;
    fi->toc_id = (d & 0x10) != 0;
    fi->data_id = d & 0x0f;

    d = readBuffer[5817];
    msd = d >> 4;
    subcode_count = d & 0x0f;
    
    d = readBuffer[5818];
    nsd = d >> 4;
    lsd = d & 0x0f;
    convert_3_bsd(&(fi->have_numeric_pnum),
                  &(fi->program_number), fi->pnum_text,
                  msd, nsd, lsd);
    
    fi->interpolate_flags = readBuffer[5819];
    
    d = readBuffer[5820];
    fi->format_id = d >> 6;
    fi->emphasis = (d & 0x30) >> 4;
    fi->sample_rate = (d & 0x0c) >> 2;
    fi->channels = d & 0x03;
    
    d = readBuffer[5821];
    fi->quantization = d >> 6;
    fi->track_pitch = (d & 0x30) >> 4;
    fi->copy_bits = (d & 0x0c) >> 2;
    fi->pack_bits = d & 0x03;
    
    if (subcode_count == 0) return;
    
    sc = readBuffer + 5760 - 8;
    for (i = 0; i < subcode_count; i++) {
        sc += 8;
        d = sc[0];
        switch((d & 0xf0) >> 4) {
            case 1:	// program time
                    fi->have_program_time = true;
                    fi->have_index = true;

                    d = sc[2];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&(fi->have_numeric_index),
                                  &(fi->index_num), fi->index_text,
                                  msd, lsd);
                                   
                    d = sc[3];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numhrs, &hrsval,
                                  fi->ptime_text,
                                  msd, lsd);
                    (fi->ptime_text)[2] = ':';

                    d = sc[4];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&nummins, &minsval,
                                  (fi->ptime_text)+3,
                                  msd, lsd);
                   (fi->ptime_text)[5] = ':';

                     d = sc[5];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numsecs, &secsval,
                                  (fi->ptime_text)+6,
                                  msd, lsd);
                   (fi->ptime_text)[8] = '.';

                    d = sc[6];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numframes, &framesval,
                                  (fi->ptime_text)+9,
                                  msd, lsd);

                    if (numhrs && nummins && numsecs && numframes) {
                        fi->have_numeric_program_time = true;
                        fi->ptime_secs = (3600 * (unsigned long)hrsval) +
                                         (60 * (unsigned long)minsval) +
                                         (unsigned long)secsval;
                        fi->ptime_frames = framesval;
                        }
                    else {
                        fi->have_numeric_program_time = false;
                        fi->ptime_secs = 0;
                        fi->ptime_frames = 0;
                        }

                    break;

            case 2:	// absolute time
                    fi->have_absolute_time = true;
                    fi->have_index = true;

                    d = sc[2];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&(fi->have_numeric_index),
                                  &(fi->index_num), fi->index_text,
                                  msd, lsd);
                                   
                    d = sc[3];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numhrs, &hrsval,
                                  fi->atime_text,
                                  msd, lsd);
                    (fi->atime_text)[2] = ':';

                    d = sc[4];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&nummins, &minsval,
                                  (fi->atime_text)+3,
                                  msd, lsd);
                   (fi->atime_text)[5] = ':';

                     d = sc[5];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numsecs, &secsval,
                                  (fi->atime_text)+6,
                                  msd, lsd);
                   (fi->atime_text)[8] = '.';

                    d = sc[6];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numframes, &framesval,
                                  (fi->atime_text)+9,
                                  msd, lsd);

                    if (numhrs && nummins && numsecs && numframes) {
                        fi->have_numeric_absolute_time = true;
                        fi->atime_secs = (3600 * (unsigned long)hrsval) +
                                         (60 * (unsigned long)minsval) +
                                         (unsigned long)secsval;
                        fi->atime_frames = framesval;
                        }
                    else {
                        fi->have_numeric_absolute_time = false;
                        fi->atime_secs = 0;
                        fi->atime_frames = 0;
                        }

                    break;

            case 3:	// running time
                    fi->have_run_time = true;
                    fi->have_index = true;

                    d = sc[2];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&(fi->have_numeric_index),
                                  &(fi->index_num), fi->index_text,
                                  msd, lsd);
                                   
                    d = sc[3];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numhrs, &hrsval,
                                  fi->rtime_text,
                                  msd, lsd);
                    (fi->rtime_text)[2] = ':';

                    d = sc[4];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&nummins, &minsval,
                                  (fi->rtime_text)+3,
                                  msd, lsd);
                   (fi->rtime_text)[5] = ':';

					d = sc[5];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numsecs, &secsval,
                                  (fi->rtime_text)+6,
                                  msd, lsd);
                   (fi->rtime_text)[8] = '.';

                    d = sc[6];
                    msd = d >> 4;
                    lsd = d & 0x0f;
                    convert_2_bsd(&numframes, &framesval,
                                  (fi->rtime_text)+9,
                                  msd, lsd);

                    if (numhrs && nummins && numsecs && numframes) {
                        fi->have_numeric_run_time = true;
                        fi->rtime_secs = (3600 * (unsigned long)hrsval) +
                                         (60 * (unsigned long)minsval) +
                                         (unsigned long)secsval;
                        fi->rtime_frames = framesval;
                        }
                    else {
                        fi->have_numeric_run_time = false;
                        fi->rtime_secs = 0;
                        fi->rtime_frames = 0;
                        }

                    break;

			case 5: // date
					if ((sc[0] != 0) || (sc[1] != 0) || (sc[2] != 0) ||
						(sc[3] != 0) || (sc[4] != 0) || (sc[5] != 0) ||
						(sc[6] != 0)) {
						fi->have_date = true;
						}

					fi->date_weekday = sc[0] & 0x0f;

					d = sc[1];
                    msd = d >> 4;
                    lsd = d & 0x0f;
					fi->date_year = msd * 10 + lsd;
					
					d = sc[2];
                    msd = d >> 4;
                    lsd = d & 0x0f;
					fi->date_month = msd * 10 + lsd;

					d = sc[3];
                    msd = d >> 4;
                    lsd = d & 0x0f;
					fi->date_day = msd * 10 + lsd;

					d = sc[4];
                    msd = d >> 4;
                    lsd = d & 0x0f;
					fi->date_hours = msd * 10 + lsd;

					d = sc[5];
                    msd = d >> 4;
                    lsd = d & 0x0f;
					fi->date_mins = msd * 10 + lsd;

					d = sc[6];
                    msd = d >> 4;
                    lsd = d & 0x0f;
					fi->date_secs = msd * 10 + lsd;
					
					break;

            default:
                    break;
            }
        }


    // check for start of new program
    if ((!last_frame_start_id) && fi->start_id) {
        have_current_pnum = false;
        have_current_index = false;
        have_ptime_offset = false;
        }
    last_frame_start_id = fi->start_id;

    if (fi->have_index) {
        if (fi->have_numeric_index) {
            strcpy(fi->index_display_text, fi->index_text);
            have_current_index = true;
            strcpy(current_index_text, fi->index_display_text);
            }
        else {
            if (strcmp(fi->index_text, "AA") == 0) {
                if (have_current_index) {
                    strcpy(fi->index_display_text, current_index_text);
                    }
                else {
                    strcpy(fi->index_display_text, "--");
                    }
                }
            else {
                strcpy(fi->index_display_text, fi->index_text);
                have_current_index = false;
                }
            }
        }
    else {
        strcpy(fi->index_text, "--");
        strcpy(fi->index_display_text, "--");
        }
    
    if (fi->have_numeric_pnum) {
        strcpy(fi->pnum_display_text, fi->pnum_text);
        if (!fi->priority_id) strcat(fi->pnum_display_text, "?");
        have_current_pnum = true;
        strcpy(current_pnum_text, fi->pnum_display_text);
        }
    else {
        if (strcmp(fi->pnum_text, "0AA") == 0) {
            if (have_current_pnum) {
                strcpy(fi->pnum_display_text, current_pnum_text);
                }
            else {
                strcpy(fi->pnum_display_text, "---");
                }
            }
        else {
            strcpy(fi->pnum_display_text, fi->pnum_text);
            if (!fi->priority_id) strcat(fi->pnum_display_text, "?");
            have_current_pnum = false;
            }
        }

    if (fi->have_program_time) {
        if (fi->have_numeric_program_time) {
            strcpy(fi->ptime_display_text, fi->ptime_text);
            if (fi->have_absolute_time) {
                have_ptime_offset = true;
                ptime_offset = get_ptime_offset(fi);
                }
            }
        else {
            if (strcmp(fi->ptime_text, "AA:AA:AA.AA") == 0) {
                if (have_ptime_offset && fi->have_absolute_time) {
                    set_ptime_display(fi, ptime_offset);
                    }
                else {
                    strcpy(fi->ptime_display_text, "--:--:--.--");
                    }
                }
            else {
                strcpy(fi->ptime_display_text, fi->ptime_text);
                have_ptime_offset = false;
                }
            }
        }
    else {
        strcpy(fi->ptime_text, "--:--:--.--");
        strcpy(fi->ptime_display_text, "--:--:--.--");
        }
    
    if (!fi->have_absolute_time) {
        strcpy(fi->atime_text, "--:--:--.--");
        }

    if (!fi->have_run_time) {
        strcpy(fi->rtime_text, "--:--:--.--");
        }

    if ((fi->interpolate_flags) & 0x40) {
        read_error_count_left++;
        }
    if ((fi->interpolate_flags) & 0x20) {
        read_error_count_right++;
        }
    if ((fi->interpolate_flags) & 0x60) {
        read_error_count_frames++;
        }
}

- (void) displayFrameInfo:(FrameInfo *)fi
{
    char textmsg[256];
    char emph[4];
    char freq[8];
    char channels[2];
    char bits[8];
    char scms[4];

    sprintf(textmsg, " Abs: %s Index: %s\nProg: %s Pnum: %s",
            fi->atime_text, fi->index_display_text,
            fi->ptime_display_text, fi->pnum_display_text);

    /*printf("Abs: %s Index: %s Prog: %s Pnum: %s\n",
            fi->atime_text, fi->index_display_text,
            fi->ptime_display_text, fi->pnum_display_text);*/

    NSString *msgstring = [[NSString alloc] initWithCString:textmsg];
    [timeText setStringValue:msgstring];
    [msgstring release];

    if (fi->emphasis) {
        strcpy(emph, "Yes");
        }
    else {
        strcpy(emph, "No");
        }

    rate_to_text(fi->sample_rate, freq);

    switch (fi->channels) {
        case 0:
                strcpy(channels, "2");
                break;
        case 1:
                strcpy(channels, "4");
                break;
        default:
                strcpy(channels, "?");
                break;
        }

	quantization_to_text(fi->quantization, bits);

    switch (fi->copy_bits) {
        case 0:
                strcpy(scms, "Yes");
                break;
        case 2:
                strcpy(scms, "No");
                break;
        case 3:
                strcpy(scms, "One");
                break;
        default:
                strcpy(scms, "???");
                break;

        }

    sprintf(textmsg, "%s %s-Channel %s\nEmphasis: %s  Copies: %s",
        freq, channels, bits, emph, scms);

    msgstring = [[NSString alloc] initWithCString:textmsg];
    [attrText setStringValue:msgstring];
    [msgstring release];

    sprintf(textmsg, "Frames: %d  L: %d  R: %d",
            read_error_count_frames, read_error_count_left,
            read_error_count_right);

    msgstring = [[NSString alloc] initWithCString:textmsg];
    [errorText setStringValue:msgstring];
    [msgstring release];
}

- (void) updateActivePrefs;
{
    char textmsg[256];
	NSString *msgstring;
	
	if (readAtProgramStart) {
		sprintf(textmsg, "Read from program start");
		}
	else {
		sprintf(textmsg, "Read immediately");
		}
    msgstring = [[NSString alloc] initWithCString:textmsg];
    [currentProgStart setStringValue:msgstring];
    [msgstring release];

	if (fileForEachProgram) {
		sprintf(textmsg, "Separate program files");
		}
	else {
		sprintf(textmsg, "All programs in one file");
		}
    msgstring = [[NSString alloc] initWithCString:textmsg];
    [currentFileForProg setStringValue:msgstring];
    [msgstring release];

	if (includeErrorFrames) {
		sprintf(textmsg, "Including error frames");
		}
	else {
		sprintf(textmsg, "Skipping error frames");
		}
    msgstring = [[NSString alloc] initWithCString:textmsg];
    [currentIncludeError setStringValue:msgstring];
    [msgstring release];

	if (errorLimit > 0) {
		sprintf(textmsg, "Error limit: %d", errorLimit);
		}
	else {
		sprintf(textmsg, "Error limit: disabled");
		}
    msgstring = [[NSString alloc] initWithCString:textmsg];
    [currentErrorLimit setStringValue:msgstring];
    [msgstring release];

	if (writeMetadata) {
		sprintf(textmsg, "Writing metadata");
		}
	else {
		sprintf(textmsg, "Not writing metadata");
		}
    msgstring = [[NSString alloc] initWithCString:textmsg];
    [currentWriteMetadata setStringValue:msgstring];
    [msgstring release];

	if (writeLog) {
		sprintf(textmsg, "Writing logs");
		}
	else {
		sprintf(textmsg, "Not writing logs");
		}
    msgstring = [[NSString alloc] initWithCString:textmsg];
    [currentWriteLog setStringValue:msgstring];
    [msgstring release];
}

- (void) updateWindowPrefs
{
    char textmsg[256];
	NSString *msgstring;

	[prefsProgStart setState:readAtProgramStart ? NSOnState : NSOffState];
	[prefsFileForProg setState:fileForEachProgram ? NSOnState : NSOffState];
	[prefsIncludeError setState:includeErrorFrames ? NSOnState : NSOffState];
	sprintf(textmsg, "%d", errorLimit);
    msgstring = [[NSString alloc] initWithCString:textmsg];
    [prefsErrorLimit setStringValue:msgstring];
    [msgstring release];
	[prefsWriteMetadata setState:writeMetadata ? NSOnState : NSOffState];
	[prefsWriteLog setState:writeLog ? NSOnState : NSOffState];
}

- (void) updateDefaultsPrefs
{
	[[NSUserDefaults standardUserDefaults] setBool:readAtProgramStart forKey:@READ_AT_PROGRAM_START_KEY];
	[[NSUserDefaults standardUserDefaults] setBool:fileForEachProgram forKey:@FILE_FOR_EACH_PROGRAM_KEY];
	[[NSUserDefaults standardUserDefaults] setBool:includeErrorFrames forKey:@INCLUDE_ERROR_FRAMES_KEY];
	[[NSUserDefaults standardUserDefaults] setInteger:errorLimit forKey:@ERROR_LIMIT_KEY];
	[[NSUserDefaults standardUserDefaults] setBool:writeMetadata forKey:@WRITE_METADATA_KEY];
	[[NSUserDefaults standardUserDefaults] setBool:writeLog forKey:@WRITE_LOG_KEY];
}

- (void) updateErrorLimit
{
	errorLimit = [[prefsErrorLimit stringValue] intValue];
	if (errorLimit < 0) errorLimit = DEFAULT_ERROR_LIMIT;
}

- (Boolean) getNewFile
{
    NSSavePanel *sp;
    int runResult;
    NSString *tstring;
    
    // create or get the shared instance of NSSavePanel
    sp = [NSSavePanel savePanel];
    
    // customize
    [sp setTitle:@"Save/Replace Numbered Files"];
    
    // display
    runResult = [sp runModal];
    
    // check for ok
    if (runResult != NSOKButton) {
        return false;
        }
    
    // save path and name
    file_extension[0] = 0;
    safe_strcat(file_extension, [[[sp filename] pathExtension] cString], 128);
    if (file_extension[0] == 0) {
        strcpy(file_extension, "aiff");
        }

    tstring = [NSString stringWithString:[[sp filename] stringByDeletingPathExtension]];
    file_name[0] = 0;
    safe_strcat(file_name, [[tstring lastPathComponent] cString], 64);
    file_path[0] = 0;
    safe_strcat(file_path, [[tstring stringByDeletingLastPathComponent] cString], 64);

    // initialize file counter
    file_counter = 0;

    return true;
}    


- (Boolean) getNewFileHandles
{
    NSFileManager *manager;
    NSDictionary *dictionary;
	// datapath is global for logging
    NSString *dataPathString;
    char infopath[268];
    NSString *infoPathString;
    char logpath[268];
    NSString *logPathString;
	mode_t open_mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
	mode_t open_flags;
	int fd;
	char msg[512];
	char write_replace = 1;		// future setting
	
    // release any previous filehandles
    if (have_data_handle) {
        [datafile release];
        have_data_handle = false;
        }
    if (have_info_handle) {
        [infofile release];
        have_info_handle = false;
        }
	if (have_log_handle) {
		[logfile release];
		have_log_handle = false;
		}

    // get filenames
    file_counter++;
    sprintf(datapath, "%s/%s-%03d.%s", file_path, file_name, file_counter, file_extension);
	if (writeMetadata) {
		sprintf(infopath, "%s/%s-%03d.%s", file_path, file_name, file_counter, "txt");
		}
	if (writeLog) {
		sprintf(logpath, "%s/%s-%03d.%s", file_path, file_name, file_counter, "log");
		}

	// delete any previous files and create new files
	if (write_replace != 0) {
		unlink(datapath);
		if (writeMetadata) {
			unlink(infopath);
			}
		if (writeLog) {
			unlink(logpath);
			}
		}

	open_flags = O_WRONLY | O_CREAT;
	if (write_replace == 0) {
		open_flags |= O_EXCL;
		}
	else {
		open_flags |= O_TRUNC;
		}
		
	fd = open(datapath, open_flags, open_mode);
	if (fd == -1) {
		sprintf(msg, "Unable to create file \"%s\": %s", datapath, strerror(errno));
		[self writeToLog:msg];
		return false;
		}
	
	if (writeMetadata) {
		fd = open(infopath, open_flags, open_mode);
		if (fd == -1) {
			sprintf(msg, "Unable to create file \"%s\": %s", infopath, strerror(errno));
			[self writeToLog:msg];
			return false;
			}
		}

	if (writeLog) {
		fd = open(logpath, open_flags, open_mode);
		if (fd == -1) {
			sprintf(msg, "Unable to create file \"%s\": %s", logpath, strerror(errno));
			[self writeToLog:msg];
			return false;
			}
		}

    // set creators and types
    manager = [NSFileManager defaultManager];
    NSNumber *fileType = [NSNumber numberWithUnsignedLong:'AIFF'];
    NSNumber *fileCreator = [NSNumber numberWithUnsignedLong:'TVOD'];
    dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                    fileType, NSFileHFSTypeCode,
                    fileCreator, NSFileHFSCreatorCode,
                    nil];
    dataPathString = [NSString stringWithCString:datapath];
    [manager changeFileAttributes:dictionary atPath:dataPathString];
 
	if (writeMetadata) {
		fileType = [NSNumber numberWithUnsignedLong:'TEXT'];
		fileCreator = [NSNumber numberWithUnsignedLong:'ttxt'];
		dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
						fileType, NSFileHFSTypeCode,
						fileCreator, NSFileHFSCreatorCode,
						nil];
		infoPathString = [NSString stringWithCString:infopath];
		[manager changeFileAttributes:dictionary atPath:infoPathString];
		}

	if (writeLog) {
		fileType = [NSNumber numberWithUnsignedLong:'TEXT'];
		fileCreator = [NSNumber numberWithUnsignedLong:'ttxt'];
		dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
						fileType, NSFileHFSTypeCode,
						fileCreator, NSFileHFSCreatorCode,
						nil];
		logPathString = [NSString stringWithCString:logpath];
		[manager changeFileAttributes:dictionary atPath:logPathString];
		}

    // get file handles
    datafile = [NSFileHandle fileHandleForWritingAtPath:dataPathString];
	if (datafile == nil) {
		[self writeToLog:"Unable to get data file handle"];
		return false;
		}
	if (writeMetadata) {
		infofile = [NSFileHandle fileHandleForWritingAtPath:infoPathString];
		if (infofile == nil) {
			[self writeToLog:"Unable to get metadata file handle"];
			return false;
			}
		}

	if (writeLog) {
		logfile = [NSFileHandle fileHandleForWritingAtPath:logPathString];
		if (logfile == nil) {
			[self writeToLog:"Unable to get log file handle"];
			return false;
			}
		}

	[datafile retain];
	have_data_handle = true;
	dataFileString = [NSString stringWithString:dataPathString];
	[dataFileString retain];

	if (writeMetadata) {
		[infofile retain];
		have_info_handle = true;
		infoFileString = [NSString stringWithString:infoPathString];
		[infoFileString retain];
		}

	if (writeLog) {
		[logfile retain];
		have_log_handle = true;
		log_file_open = true;
		logFileString = [NSString stringWithString:logPathString];
		[logFileString retain];
		}

	return true;
}

- (int) initAudioFile:(FrameInfo *)fi {

    unsigned char freq32k[4] = {0x40, 0x0d, 0xfa, 0x00};
    unsigned char freq441k[4] = {0x40, 0x0e, 0xac, 0x44};
    unsigned char freq48k[4] = {0x40, 0x0e, 0xbb, 0x80};
    char msg[512];
    char freq[8];
    Boolean writeOK;
	char temp[16];
	time_t current_time;
	
    // check we can handle data format
    if ((fi->quantization != 0) && (fi->quantization != 1)) {
		sprintf(msg, "unknown quantization (%d) not supported", fi->quantization);
		[self writeToLog:msg];
        return 1;
        }

	// 12-bit must be for 32K
	if (fi->quantization == 1) {
		if (fi->sample_rate != 2) {
			sprintf(msg, "12-bit quantization is only supported with 32KHz sampling rate", fi->quantization);
			[self writeToLog:msg];
			return 1;
			}
		}

    // allocate AIFF header to ensure alignment
    ah = malloc(AIFF_HEADER_SIZE);
    if (ah == 0) {
        [self writeToLog:"unable to allocate AIFF header"];
        return 1;
        }

    // initialize AIFF header
    strcpy((char *)ah, "FORM");			// formname
    *(unsigned long *)(ah+4) = 46;	// formsize - sample size + 46
    strcpy((char *)(ah+8), "AIFF");		// aiffname
    strcpy((char *)(ah+12), "COMM");		// commname
    *(unsigned long *)(ah+16) = 18;	// commsize (18)
    *(unsigned short *)(ah+20) = 2;	// channels
    *(unsigned long *)(ah+22) = 0;	// samplecount - sample size / 4
    *(unsigned short *)(ah+26) = 16;	// samplebits    
    switch(fi->sample_rate) {		// samplefreq, IEEE extended
        case 0:
                memcpy(ah+28, freq48k, 4);
                break;
        case 1:
                memcpy(ah+28, freq441k, 4);
                break;
        case 2:
                memcpy(ah+28, freq32k, 4);
                break;
        default:
                [self writeToLog:"Unknown sample rate"];
                return 2;
                break;
        }
    memset(ah+32, 0, 6);		// reset of extended value
    strcpy((char *)(ah+38), "SSND");		// ssndname
    *(unsigned long *)(ah+42) = 8;	// ssndsize - sample size + 8
    *(unsigned long *)(ah+46) = 0;	// offset
    *(unsigned long *)(ah+50) = 0;	// blocksize

    // write header
    writeOK = true;
    NS_DURING
    [datafile writeData:[NSData dataWithBytes:ah length:AIFF_HEADER_SIZE]];
    NS_HANDLER
    strcpy(msg, "Error initializing file: ");
    strcat(msg, [[localException reason] cString]);
    [self writeToLog:msg];
    writeOK = false;
    NS_ENDHANDLER
    if (!writeOK) {
        return 1;
        }
        
    // initialize variables
    expected_frame = 0;
    samples_written = 0;
	frames_read = 0;
    frames_written = 0;
    file_sample_rate = fi->sample_rate;
	file_quantization = fi->quantization;
    file_error_count = 0;
    adjusted_file_error_count = 0;
    errors_exceeded = false;

    // display filename
    [filenameText setStringValue:dataFileString];
    
    // log start
    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:@"\nOpening file: "];
    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:dataFileString];
    [logText scrollRangeToVisible:NSMakeRange([[logText string] length]-1, 0)];

	if (log_file_open) {
		[logfile writeData:[NSData dataWithBytes:"Opening file: " length:14]];		
		[logfile writeData:[NSData dataWithBytes:datapath length:strlen(datapath)]];		
		[logfile writeData:[NSData dataWithBytes:"\n" length:1]];		
		}

    rate_to_text(fi->sample_rate, freq);
    sprintf(msg, "File sample rate: %s", freq);
    [self writeToLog:msg];
	
    if (fi->quantization == 1) {
	    sprintf(msg, "Writing 16-bit file from 12-bit LP mode tape", freq);
		[self writeToLog:msg];
		}

	if (errorLimit == 0) {
		sprintf(msg, "Error limit disabled");
		}
	else {
		sprintf(msg, "Stopping after %d errors", errorLimit);
		}
    [self writeToLog:msg];
	

	// done if not doing info
	if (!have_info_handle) return 0;

	// write initial info file data-
	current_time = time(0);
	sprintf(msg, "Extraction started %s", asctime(localtime(&current_time)));
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

	// write values which must be constant for the entire file
    switch (fi->sample_rate) {
        case 0:
                strcpy(temp, "48000");
                break;
        case 1:
                strcpy(temp, "44100");
                break;
        case 2:
                strcpy(temp, "32000");
                break;
        default:
                sprintf(temp, "x%02x", fi->sample_rate);
                break;
        }
    sprintf(msg, "Sampling frequency: %s\n", temp);
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];
	
    switch (fi->channels) {
        case 0:
                strcpy(temp, "2");
                break;
        case 1:
                strcpy(temp, "4");
                break;
        default:
                strcpy(temp, "?");
                break;
        }
    sprintf(msg, "Channels: %s\n", temp);
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

    switch (fi->quantization) {
        case 0:
                strcpy(temp, "16-bit linear");
                break;
        case 1:
                strcpy(temp, "12-bit non-linear");
                break;
        default:
                sprintf(temp, "x%02x", fi->quantization);
                break;
        }
    sprintf(msg, "Quantization: %s\n", temp);
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];
	
    sprintf(msg, "Emphasis: %s\n", fi->emphasis ? "Yes" : "No");
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

    switch (fi->copy_bits) {
        case 0:
                strcpy(temp, "Yes");
                break;
        case 2:
                strcpy(temp, "No");
                break;
        case 3:
                strcpy(temp, "One");
                break;
        default:
                strcpy(temp, "???");
                break;
		}
    sprintf(msg, "Copies: %s\n", temp);
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

	// write start frame info
    sprintf(msg, "Start frame:\n");
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];
	[self writeFrameInfo:fi];

	return 0;
}

- (int) writeAudioFile:(FrameInfo *)fi {
    char msg[512];
    char timestring[16];
    char channels[4];
    unsigned long current_frame;
    unsigned int i, sample_count;
	unsigned int end_count;
    unsigned char *sample;
    unsigned long byte_count;
    unsigned long secs_result;
    unsigned char frames;
    Boolean writeOK;
    Boolean have_error, have_frame_error;
    int result;
    char freq1[8], freq2[8];
	char bits1[8], bits2[8];
    unsigned char sample_rate_to_use;
	unsigned char quantization_to_use;
	unsigned char *writePtr;
	short *unpackPtr;
	int x0, x1, x2;
    
    result = 0;
    have_error = have_frame_error = false;
	frames_read++;

    // check if we're waiting
    // assume flag may not be valid if bad frame
    if (wait_for_prog) {
        if (fi->interpolate_flags) {
            return 0;
            }
        else {
            if (fi->start_id) {
                wait_for_prog = false;
                }
            else {
                return 0;
                }
            }
        }

    // handle bad or questionable frame
	if (fi->interpolate_flags) {
		if (fi->interpolate_flags & 0x60) {
			switch (fi->interpolate_flags & 0x60) {
				case 0x20:
							strcpy(channels, "R");
							break;
				case 0x40:
							strcpy(channels, "L");
							break;
				case 0x60:
							strcpy(channels, "L+R");
							break;
				default:
							strcpy(channels, "???");
							break;
				}

			frames_to_time(frames_written, &secs_result, &frames,
						   file_quantization);
			get_display_time(secs_result, frames, timestring);
			sprintf(msg,
				"\tChannels: %s\n\tAbs: %s  Prog: %s\n\tFile start: %s",
				channels, fi->atime_text, fi->ptime_display_text, timestring);
			}
		else {
			frames_to_time(frames_written, &secs_result, &frames,
						   file_quantization);
			get_display_time(secs_result, frames, timestring);
			sprintf(msg,
				"\tInterpolate flags: %x\n\tAbs: %s  Prog: %s\n\tFile start: %s",
				fi->interpolate_flags, fi->atime_text, fi->ptime_display_text,
				timestring);
			}
		expected_frame = 0;
		have_error = have_frame_error = true;
		if (includeErrorFrames) {
			[self writeToLog:"Including error frame: "];
			[self writeToLog:msg];
			}
		else {
			[self writeToLog:"Skipping error frame: "];
			[self writeToLog:msg];
			goto display;
			}
		}

	// check if expected frame
    if (fi->have_absolute_time) {
        current_frame = secs_to_frames(fi->atime_secs);
        current_frame += fi->atime_frames;
        if (current_frame > 300) {
//            if (expected_frame != 0) {
//                if (current_frame != expected_frame) {
//                    frames_to_time(frames_written, &secs_result, &frames,
//									 file_quantization);
//                    get_display_time(secs_result, frames, timestring);
//                    sprintf(msg,
//                    "Warning: expected frame %ld, got %ld\n\tAbs: %s  Prog: %s\n\tFile: %s",
//                    expected_frame, current_frame,
//                    fi->atime_text, fi->ptime_display_text, timestring);
//                    [self writeToLog:msg];
//                    }
//                }
            expected_frame = current_frame + 1;
            }
        else {
            expected_frame = 0;
            }
        }
    else {
        expected_frame = 0;
        }


    // determine sample rate and quantization to use for this frame
    sample_rate_to_use = fi->sample_rate;
	quantization_to_use = fi->quantization;

    // handle sample rate or quantization mismatch
    if ((fi->sample_rate != file_sample_rate) ||
		(fi->quantization != file_quantization)) {
 
		// report mismatch
		frames_to_time(frames_written, &secs_result, &frames,
					   file_quantization);
        get_display_time(secs_result, frames, timestring);
        rate_to_text(file_sample_rate, freq1);
        rate_to_text(fi->sample_rate, freq2);
		quantization_to_text(file_quantization, bits1);
		quantization_to_text(fi->quantization, bits2);
        sprintf(msg, "Frame mismatch at:\n    Abs: %s  Prog: %s\n    File: %s",
                fi->atime_text, fi->ptime_display_text, timestring);
        [self writeToLog:msg];
		if (fi->sample_rate != file_sample_rate) {
			sprintf(msg, "    expected %s, frame = %s", freq1, freq2);
			[self writeToLog:msg];
			}
		if (fi->quantization != file_quantization) {
			sprintf(msg, "    expected %s, frame = %s", bits1, bits2);
			[self writeToLog:msg];
			}
		
		// see if the contents of the frame appears to be
		// consistent with what we're expecting
		
		// count the number of final samples
		end_count = 0;
		for (i = (4*1439); i >= (4*960); i--) {
			if (readBuffer[i] == 0) {
				end_count++;
				}
			else {
				break;
				}
			}

		// set what the frame appears to be
		if (end_count >= 480) {			// 32KHz, 16-bit
			sample_rate_to_use = 2;
			quantization_to_use = 0;
			}
		else if (end_count >= 117) {	// 44.1KHz, 16-bit
			sample_rate_to_use = 1;
			quantization_to_use = 0;
			}
		else {							// 48KHz, 16-bit or 32KHz 12-bit
			if (file_quantization == 0) {
				sample_rate_to_use = 0;
				quantization_to_use = 0;
				}
			else {
				sample_rate_to_use = 2;
				quantization_to_use = 1;
				}
			}
 
		// check for error
		have_error = (sample_rate_to_use != file_sample_rate) ||
					 (quantization_to_use != file_quantization);

		// report results
		rate_to_text(sample_rate_to_use, freq1);
		quantization_to_text(quantization_to_use, bits1);
		sprintf(msg, "    using apparent %s, %s (%s)\n", freq1, bits1,
			have_error ? "error" : "no error");
        [self writeToLog:msg];
        }


	// fill-in writeBuffer
	
	if (quantization_to_use == 0) {
		// get sample count
		switch (sample_rate_to_use) {
			case 1:			// 44.1
				sample_count = 1323;
				break;
			
			case 2:			// 32
				sample_count = 960;
				break;
				
			case 0:			// 48
			default:
				sample_count = 1440;
				break;
			}
			
		// copy to write buffer;
		sample = readBuffer;
		writePtr = writeBuffer;
		for (i = 0; i < sample_count; i++) {
			*(writePtr++) = sample[1];
			*(writePtr++) = sample[0];
			*(writePtr++) = sample[3];
			*(writePtr++) = sample[2]; 
			sample += 4;
			}
		}

    else {					// 32K LP mode 
		unpackPtr = (short *)writeBuffer;
		for (i = 0; i < 5760; i += 3) {
			x0 = readBuffer[translate_lp_frame_index[i]];
			x1 = readBuffer[translate_lp_frame_index[i+1]];
			x2 = readBuffer[translate_lp_frame_index[i+2]];
			*(unpackPtr++) = decode_lp_sample[(x0 << 4) | ((x1 >> 4) & 0x0f)];
			*(unpackPtr++) = decode_lp_sample[(x2 << 4) | (x1 & 0x0f)];
			}
		sample_count = 1920;
		}
	
	byte_count = sample_count * 4;
	
    // write the data
    writeOK = true;
    NS_DURING
    [datafile writeData:[NSData dataWithBytes:writeBuffer length:byte_count]];
    NS_HANDLER
    strcpy(msg, "Error writing to file: ");
    strcat(msg, [[localException reason] cString]);
    [self writeToLog:msg];
    writeOK = false;
    NS_ENDHANDLER
    if (!writeOK) {
        result = 1;
        goto display;
        }

    samples_written += sample_count;
	frames_written++;

	// save frame info for last frame written
	file_end_info = *fi;

	// report sample count for frame error
	if (have_frame_error) {
		frames_to_time(frames_written, &secs_result, &frames,
					   file_quantization);
		get_display_time(secs_result, frames, timestring);
		sprintf(msg, "\t File end: %s (%d samples)", timestring, sample_count);
		[self writeToLog:msg];
		}

    // log start of data
    if (frames_written == 1) {
        [self writeToLog:"Writing audio data started"];
        }
        
    // display frames written as time
display:
    // check if errors exceeded
    if (have_error) {
        file_error_count++;
        adjusted_file_error_count++;
        }

    if (frames_written < 200) {
        errors_exceeded = file_error_count >= 100;
        if (errors_exceeded) {
            [self writeToLog:"Stopping due to 100 errors within first 200 frames"];
            }
        }
    else {
        if (frames_written == 200) {
            adjusted_file_error_count = 0;
            }
		if (errorLimit > 0) {
			errors_exceeded = adjusted_file_error_count >= errorLimit;
			if (errors_exceeded) {
				sprintf(msg, "Stopping due to %d errors", errorLimit);
				[self writeToLog:msg];
				}
			}
        }

    frames_to_time(frames_written, &secs_result, &frames, file_quantization);
    get_display_time(secs_result, frames, timestring);
    rate_to_text(file_sample_rate, freq1);
    sprintf(msg, "%s %s Err: %d", freq1, timestring, adjusted_file_error_count);
    NSString *msgstring = [[NSString alloc] initWithCString:msg];
    [fileDurationText setStringValue:msgstring];
    [msgstring release];

    return result;
}

- (void) finishAudioFile {
    unsigned long sample_byte_count;
    unsigned long secs_result;
    unsigned char frames;
    char timestring[16];
    char msg[512];
	time_t current_time;

    sample_byte_count = samples_written * 4;

    // update header and finish file
    *(unsigned long *)(ah+4) = sample_byte_count + 46;	// sample size + 46
    *(unsigned long *)(ah+22) = samples_written;	// sample count
    *(unsigned long *)(ah+42) = sample_byte_count + 8;	// sample size + 8

    NS_DURING
    [datafile seekToFileOffset:0];
    NS_HANDLER
    strcpy(msg, "Error closing data file: ");
    strcat(msg, [[localException reason] cString]);
    [self writeToLog:msg];
    NS_ENDHANDLER

    NS_DURING
    [datafile writeData:[NSData dataWithBytes:ah length:AIFF_HEADER_SIZE]];
    NS_HANDLER
    strcpy(msg, "Error closing data file: ");
    strcat(msg, [[localException reason] cString]);
    [self writeToLog:msg];
    NS_ENDHANDLER

    NS_DURING
    [datafile closeFile];
    NS_HANDLER
    strcpy(msg, "Error closing data file: ");
    strcat(msg, [[localException reason] cString]);
    [self writeToLog:msg];
    NS_ENDHANDLER

	// write end frame info
	if (have_info_handle) {
		sprintf(msg, "End frame:\n");
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];
		[self writeFrameInfo:&file_end_info];

		sprintf(msg, "Frames read: %u\n", frames_read);
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

		sprintf(msg, "Frames written: %u\n", frames_written);
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

		sprintf(msg, "Error frames: %u\n", file_error_count);
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

		sprintf(msg, "Adjusted error frames: %u\n", adjusted_file_error_count);
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

		sprintf(msg, "Samples: %u\n", samples_written);
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

		frames_to_time(frames_written, &secs_result, &frames, file_quantization);
		get_display_time(secs_result, frames, timestring);
		sprintf(msg, "Duration: %s\n", timestring);
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

		current_time = time(0);
		sprintf(msg, "Extraction finished %s", asctime(localtime(&current_time)));
		[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

		NS_DURING
		[infofile closeFile];
		NS_HANDLER
		strcpy(msg, "Error closing info file: ");
		strcat(msg, [[localException reason] cString]);
		[self writeToLog:msg];
		NS_ENDHANDLER
		}

    free(ah);

    // log completion
    // log start
    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:@"\nFinished file: "];
    [logText replaceCharactersInRange:NSMakeRange(
        [[logText string] length], 0) withString:dataFileString];
    [logText scrollRangeToVisible:NSMakeRange([[logText string] length]-1, 0)];

	if (log_file_open) {
		[logfile writeData:[NSData dataWithBytes:"Finished file: " length:15]];		
		[logfile writeData:[NSData dataWithBytes:datapath length:strlen(datapath)]];		
		[logfile writeData:[NSData dataWithBytes:"\n" length:1]];		
		}

    frames_to_time(frames_written, &secs_result, &frames, file_quantization);
    get_display_time(secs_result, frames, timestring);
    sprintf(msg, "\tTotal Errors: %d  Adjusted Errors: %d\n\tDuration: %s",
            file_error_count, adjusted_file_error_count, timestring);
    [self writeToLog:msg];

	if (have_log_handle) {
		log_file_open = false;
		NS_DURING
		[logfile closeFile];
		NS_HANDLER
		strcpy(msg, "Error closing log file: ");
		strcat(msg, [[localException reason] cString]);
		[self writeToLog:msg];
		NS_ENDHANDLER
		}

    // reset filename display
    [filenameText setStringValue:@""];
    [fileDurationText setStringValue:@""];
    [dataFileString release];
	if (have_info_handle) {
		[infoFileString release];
		}
}

- (void) writeFrameInfo:(FrameInfo *)fi
{
	char msg[256];
	int weekday, year;
	char *decode_weekday[] = {"Sun", "Mon","Tue","Wed","Thu","Fri","Sat", "???"};
	
	if (strcmp(fi->pnum_display_text, "---") != 0) {
		sprintf(msg, "  Program number: %s\n", fi->pnum_display_text);
		}
	else {
		sprintf(msg, "  Program number: none\n");
		}
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];
		
	if (strcmp(fi->index_display_text, "--") != 0) {
		sprintf(msg, "  Index: %s\n", fi->index_display_text);
		}
	else {
		sprintf(msg, "  Index: none\n");
		}
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

	if (strcmp(fi->atime_text, "--:--:--.--") != 0) {
		sprintf(msg, "  Absolute time: %s\n", fi->atime_text);
		}
	else {
		sprintf(msg, "  Absolute time: none\n");
		}
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

	if (strcmp(fi->ptime_display_text, "--:--:--.--") != 0) {
		sprintf(msg, "  Program time: %s\n", fi->ptime_display_text);
		}
	else {
		sprintf(msg, "  Program time: none\n");
		}
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

	if (strcmp(fi->rtime_text, "--:--:--.--") != 0) {
		sprintf(msg, "  Running time: %s\n", fi->rtime_text);
		}
	else {
		sprintf(msg, "  Running time: none\n");
		}
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];

	if (fi->have_date) {
		weekday = fi->date_weekday - 1;
		if ((weekday < 0) || (weekday > 6)) {
			weekday = 7;
			}
		year = fi->date_year;
		if (year < 50) year += 100;
		year += 1900;
		sprintf(msg, "  Date: %s, %04d-%02d-%02d %02d:%02d:%02d\n",
			decode_weekday[weekday], year, fi->date_month, fi->date_day,
			fi->date_hours, fi->date_mins, fi->date_secs);
		}
	else {
		sprintf(msg, "  Date: none\n");
		}
	[infofile writeData:[NSData dataWithBytes:msg length:strlen(msg)]];
}

- (IBAction)read:(id)sender
{
    int result;
    Boolean file_result;

    stop_timer = true;
    [readButton setEnabled:false];
    [rewindButton setEnabled:false];
    [ejectButton setEnabled:false];

    // get filename
    file_result = [self getNewFile];
    if (file_result) file_result = [self getNewFileHandles];
    if (!file_result) {
        stop_timer = false;
        [readButton setEnabled:true];
        [rewindButton setEnabled:true];
        [ejectButton setEnabled:true];
        return;
        }

    // prepare to use drive
    result = [theDrive locateDrive];
    if (result == 0) {
        result = [theDrive setupInterface];
	}
    if (result != 0) {
        [self writeToLog:"Unable to setup drive interface"];
        drive_ready = false;
        stop_timer = false;
        return;
        }

    first_frame = true;
    read_error_count_left = 0;
    read_error_count_right = 0;
    read_error_count_frames = 0;
    wait_for_prog = readAtProgramStart;
    result = [theDrive readWithBuffer:readBuffer 				     	      withCallback:read_callback];
    if (result != 0) {
        first_frame = false;
        [self writeToLog:"Unable to start read"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        }
    else {
        [driveStatus setStringValue:@"Reading tape"];
        }
}

- (IBAction)stop:(id)sender
{
    stop_requested = true;
    [stopButton setEnabled:false];
    if (pause_requested) {
        [self resume:nil];
        }
}

- (IBAction)rewind:(id)sender
{
    int result;

    stop_timer = true;
    [readButton setEnabled:false];
    [rewindButton setEnabled:false];
    [ejectButton setEnabled:false];

    [timeText setStringValue:@""];
    [attrText setStringValue:@""];
    [errorText setStringValue:@""];

    // prepare to use drive
    result = [theDrive locateDrive];
    if (result == 0) {
        result = [theDrive setupInterface];
	}
    if (result != 0) {
        [self writeToLog:"Unable to setup drive interface"];
        drive_ready = false;
        stop_timer = false;
        return;
        }

    // do async load
    need_initial_positioning = true;
    result = [theDrive loadUnload:false withCallback:load_callback];
    if (result != 0) {
        [self writeToLog:"Unable to start rewind"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        return;
        }
    else {
        [driveStatus setStringValue:@"Rewinding tape"];
        }
}

- (IBAction)eject:(id)sender
{
    int result;

    stop_timer = true;
    [readButton setEnabled:false];
    [rewindButton setEnabled:false];
    [ejectButton setEnabled:false];

    [timeText setStringValue:@""];
    [attrText setStringValue:@""];
    [errorText setStringValue:@""];

    // prepare to use drive
    result = [theDrive locateDrive];
    if (result == 0) {
        result = [theDrive setupInterface];
	}
    if (result != 0) {
        [self writeToLog:"Unable to setup drive interface"];
        drive_ready = false;
        stop_timer = false;
        return;
        }

    // do async unload
    doing_unload = true;
    result = [theDrive loadUnload:true withCallback:load_callback];
    if (result != 0) {
        doing_unload = false;
        [self writeToLog:"Unable to start unload"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        return;
        }
    else {
        [driveStatus setStringValue:@"Ejecting tape"];
        }
}

- (IBAction)pause:(id)sender
{
    pause_requested = true;
    [pauseButton setEnabled:false];
}

- (IBAction)resume:(id)sender
{
    int result;

    pause_requested = false;
    [resumeButton setEnabled:false];
    result = [theDrive readWithBuffer:readBuffer withCallback:read_callback];
    if (result != 0) {
        [stopButton setEnabled:false];
        stop_requested = false;
        first_frame = false;
        [self writeToLog:"Unable to start new read"];
        [theDrive releaseInterface];
        drive_ready = false;
        stop_timer = false;
        [self finishAudioFile];
        }
    [driveStatus setStringValue:@"Reading tape"];
    [pauseButton setEnabled:true];
}

- (IBAction)inserting_checkbox:(id)sender
{
}

- (IBAction)preferences:(id)sender
{
	[prefsWindow makeKeyAndOrderFront:nil];
}

- (IBAction)prefDefaults:(id)sender
{
	NSString *userDefaultsValuesPath;
	NSDictionary *userDefaultsValuesDict;
	NSNumber *resultNumber;
	
	// define defaults
	userDefaultsValuesPath = [[NSBundle mainBundle] pathForResource:@"UserDefaults"
                               ofType:@"plist"];
	userDefaultsValuesDict = [NSDictionary dictionaryWithContentsOfFile:userDefaultsValuesPath];

	resultNumber = [userDefaultsValuesDict objectForKey:@READ_AT_PROGRAM_START_KEY];
	readAtProgramStart = [resultNumber boolValue];
	
	resultNumber = [userDefaultsValuesDict objectForKey:@FILE_FOR_EACH_PROGRAM_KEY];
	fileForEachProgram = [resultNumber boolValue];

	resultNumber = [userDefaultsValuesDict objectForKey:@INCLUDE_ERROR_FRAMES_KEY];
	includeErrorFrames = [resultNumber boolValue];

	resultNumber = [userDefaultsValuesDict objectForKey:@ERROR_LIMIT_KEY];
	errorLimit = [resultNumber intValue];

	resultNumber = [userDefaultsValuesDict objectForKey:@WRITE_METADATA_KEY];
	writeMetadata = [resultNumber boolValue];

	resultNumber = [userDefaultsValuesDict objectForKey:@WRITE_LOG_KEY];
	writeLog = [resultNumber boolValue];

	[self updateWindowPrefs];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];
}

- (IBAction)prefClose:(id)sender
{
	[self updateErrorLimit];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];

	[prefsWindow close];
}

- (IBAction)prefProgStart:(id)sender
{
	readAtProgramStart = [prefsProgStart state] == NSOnState;
	[self updateErrorLimit];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];
}

- (IBAction)prefProgFiles:(id)sender
{
	fileForEachProgram = [prefsFileForProg state] == NSOnState;
	[self updateErrorLimit];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];
}

- (IBAction)prefIncludeError:(id)sender
{
	includeErrorFrames = [prefsIncludeError state] == NSOnState;
	[self updateErrorLimit];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];
}

- (IBAction)prefErrorLimit:(id)sender
{
	[self updateErrorLimit];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];
}

- (IBAction)prefWriteMetadata:(id)sender
{
	writeMetadata = [prefsWriteMetadata state] == NSOnState;
	[self updateErrorLimit];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];
}

- (IBAction)prefWriteLog:(id)sender
{
	writeLog = [prefsWriteLog state] == NSOnState;
	[self updateErrorLimit];
	[self updateActivePrefs];
	[self updateDefaultsPrefs];
}

@end

SCSIServiceResponse loadResponse;
SCSITaskStatus loadStatus;
UInt64 loadCount;

void load_callback(SCSIServiceResponse serviceResponse,
                   SCSITaskStatus taskStatus,
                   UInt64 bytesTransferred,
                   void *refcon)
{
    NSEvent *loadEvent;
    NSPoint point;
    SCSITaskInterface **task;

    // free task
    task = (SCSITaskInterface **)refcon;
    (*task)->Release(task);

    // save returned info
    loadResponse = serviceResponse;
    loadStatus = taskStatus;
    loadCount = bytesTransferred;

    // post event
    point.x = point.y = 0;
    loadEvent = [NSEvent otherEventWithType:NSApplicationDefined
                            location:point
                            modifierFlags:0
                            timestamp:0.0
                            windowNumber:0
                            context:NULL
                            subtype:LOAD_EVENT_SUBTYPE
                            data1:0
                            data2:0];
    [NSApp postEvent:loadEvent atStart:false];
}

SCSIServiceResponse readResponse;
SCSITaskStatus readStatus;
UInt64 readCount;

void read_callback(SCSIServiceResponse serviceResponse,
                   SCSITaskStatus taskStatus,
                   UInt64 bytesTransferred,
                   void *refcon)
{
    NSEvent *loadEvent;
    NSPoint point;
    SCSITaskInterface **task;

    // free task
    task = (SCSITaskInterface **)refcon;
    (*task)->Release(task);

    // save returned info
    readResponse = serviceResponse;
    readStatus = taskStatus;
    readCount = bytesTransferred;

    // post event
    point.x = point.y = 0;
    loadEvent = [NSEvent otherEventWithType:NSApplicationDefined
                            location:point
                            modifierFlags:0
                            timestamp:0.0
                            windowNumber:0
                            context:NULL
                            subtype:READ_EVENT_SUBTYPE
                            data1:0
                            data2:0];
    [NSApp postEvent:loadEvent atStart:false];
}

void convert_2_bsd(Boolean *is_numeric,
                   unsigned char *result_val,
                   char *result_text,
                   unsigned char msd,
                   unsigned char lsd) {

    *is_numeric = ((msd <= 9) && (lsd <= 9));
    *result_val = 0;
    
    if (msd <= 9) {
        *result_val = msd * 10;
        result_text[0] = msd + 48; 
        }
    else {
        result_text[0] = msd + 55;
        }


    if (lsd <= 9) {
        *result_val += lsd;
        result_text[1] = lsd + 48; 
        }
    else {
        result_text[1] = lsd + 55;
        }

    result_text[2] = 0;

}

void convert_3_bsd(Boolean *is_numeric,
                   short *result_val,
                   char *result_text,
                   unsigned char msd,
                   unsigned char nsd,
                   unsigned char lsd) {

    *is_numeric = ((msd <= 9) && (nsd <= 9) && (lsd <= 9));
    *result_val = 0;
    
    if (msd <= 9) {
        *result_val = msd * 100;
        result_text[0] = msd + 48; 
        }
    else {
        result_text[0] = msd + 55;
        }

    if (nsd <= 9) {
        *result_val += nsd * 10;
        result_text[1] = nsd + 48; 
        }
    else {
        result_text[1] = nsd + 55;
        }

    if (lsd <= 9) {
        *result_val += lsd;
        result_text[2] = lsd + 48; 
        }
    else {
        result_text[2] = lsd + 55;
        }

    result_text[3] = 0;
}

unsigned long get_ptime_offset(FrameInfo *fi) {
    unsigned long aframes;
    unsigned long pframes;

    aframes = secs_to_frames(fi->atime_secs);
    aframes += fi->atime_frames;

    pframes = secs_to_frames(fi->ptime_secs);
    pframes += fi->ptime_frames;

    return(aframes - pframes);
}
    
void set_ptime_display(FrameInfo *fi, unsigned long offset) {

    unsigned long aframes;
    unsigned long pframes;
    unsigned long secs_result;
    unsigned char frames;

    aframes = secs_to_frames(fi->atime_secs);
    aframes += fi->atime_frames;
    pframes = aframes - offset;
    
    frames_to_time(pframes, &secs_result, &frames, fi->quantization);
    get_display_time(secs_result, frames, fi->ptime_display_text);
}

void get_display_time(unsigned long secs_result, unsigned char frames,
                      char *result)
{
    unsigned char hrs, mins, secs;

    hrs = secs_result / 3600;
    secs_result -= (hrs * 3600);
    mins = secs_result / 60;
    secs = secs_result - (mins * 60);
    if (hrs > 99) hrs = 99;
    if (mins > 99) mins = 99;
    if (secs > 99) secs = 99;
    if (frames > 99) frames = 99;
    sprintf(result, "%02d:%02d:%02d.%02d",
            hrs, mins, secs, frames);
}

unsigned long secs_to_frames(unsigned long secs) {

    unsigned long result;
    
    result = (secs / 3) * 100;
    
    switch (secs % 3) {
        case 0:
                break;
                
        case 1:
                result += 33;
                break;
                
        case 2:
                result += 66;
                break;
                
        default:
                break;
        }

    return result;
}


void frames_to_time(unsigned long in_frames, unsigned long *secs,
                    unsigned char *frames, unsigned char quantization)
{
    unsigned long x, rframes;
	unsigned long adj_frames;
	
	if (quantization == 0) {
		adj_frames = in_frames;
		}
	else {
		adj_frames = in_frames * 2;
		}

	x = adj_frames / 100;
	*secs = x * 3;
	rframes = adj_frames - (x * 100);
    
	if (rframes < 33) {
		*frames = rframes;
		}
	else if (rframes < 66) {
		(*secs) ++;
		*frames = rframes - 33;
		}
	else {
		(*secs) += 2;
		*frames = rframes - 66;
		}
}

void rate_to_text(unsigned char rate, char *text)
{
    switch (rate) {
        case 0:
                strcpy(text, "48KHz");
                break;
        case 1:
                strcpy(text, "44.1KHz");
                break;
        case 2:
                strcpy(text, "32KHz");
                break;
        default:
                sprintf(text, "x%02x", rate);
                break;
        }
}

void quantization_to_text(unsigned char quantization, char *text)
{
    switch (quantization) {
        case 0:
                strcpy(text, "16-Bit");
                break;
        case 1:
                strcpy(text, "12-Bit");
                break;
        default:
                sprintf(text, "x%02x", quantization);
                break;
        }
}

char * safe_strcat(char *dest, const char *src, int len)
{
    // len = declared length of dest
    // strcat which appends only as much as fits
    int src_len, dest_len, copylen;
    
    if (src == 0) return dest;	// no src string
    src_len = strlen(src);
    if (src_len == 0) return dest; // nothing to copy
    
    dest_len = strlen(dest);
    copylen = len - 1 - dest_len;
    if (copylen <= 0) return dest; // already no room
    
    if (copylen > src_len) copylen = src_len;  // no longer than source
    
    memcpy(dest + dest_len, src, copylen);
    dest[dest_len + copylen] = 0;

    return dest;
}
