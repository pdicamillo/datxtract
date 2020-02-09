/* DATXtract - an application for reading audio DAT tapes

   Copyright © 2002-2007 Peter DiCamillo

   This code is distributed under the license specified by the COPYING file
   at the top-level directory of this distribution.                         */

#import <Cocoa/Cocoa.h>
#import "DATDrive.h"

typedef struct FrameInfo {
    Boolean priority_id;
    Boolean start_id;
    Boolean skip_id;
    Boolean toc_id;
    unsigned char data_id;
    Boolean have_numeric_pnum;
    short program_number;
    char pnum_text[4];
    char pnum_display_text[5];
    unsigned char interpolate_flags;
    unsigned char format_id;
    unsigned char emphasis;
    unsigned char sample_rate;
    unsigned char channels;
    unsigned char quantization;
    unsigned char track_pitch;
    unsigned char copy_bits;
    unsigned char pack_bits;
    Boolean have_index;
    Boolean have_numeric_index;
    unsigned char index_num;
    char index_text[3];
    char index_display_text[3];
    Boolean have_program_time;
    Boolean have_numeric_program_time;
    unsigned long ptime_secs;
    unsigned char ptime_frames;
    char ptime_text[12];
    char ptime_display_text[12];
    Boolean have_absolute_time;
    Boolean have_numeric_absolute_time;
    unsigned long atime_secs;
    unsigned char atime_frames;
    char atime_text[12];
    Boolean have_run_time;
    Boolean have_numeric_run_time;
    unsigned long rtime_secs;
    unsigned char rtime_frames;
    char rtime_text[12];
    Boolean have_date;
    unsigned char date_weekday;
    unsigned char date_year;
    unsigned char date_month;
    unsigned char date_day;
    unsigned char date_hours;
    unsigned char date_mins;
    unsigned char date_secs;
} FrameInfo;

#define AIFF_HEADER_SIZE  54

void load_callback(SCSIServiceResponse serviceResponse,
                   SCSITaskStatus taskStatus,
                   UInt64 bytesTransferred,
                   void *refcon);
                
extern SCSIServiceResponse loadResponse;
extern SCSITaskStatus loadStatus;
extern UInt64 loadCount;

void read_callback(SCSIServiceResponse serviceResponse,
                   SCSITaskStatus taskStatus,
                   UInt64 bytesTransferred,
                   void *refcon);

extern SCSIServiceResponse readResponse;
extern SCSITaskStatus readStatus;
extern UInt64 readCount;

#define LOAD_EVENT_SUBTYPE	1
#define READ_EVENT_SUBTYPE	2
#define UNLOAD_EVENT_SUBTYPE	3
#define DEFAULT_ERROR_LIMIT	15

void convert_2_bsd(Boolean *is_numeric,
                   unsigned char *result_val,
                   char *result_text,
                   unsigned char msd,
                   unsigned char lsd);

void convert_3_bsd(Boolean *is_numeric,
                   short *result_val,
                   char *result_text,
                   unsigned char msd,
                   unsigned char nsd,
                   unsigned char lsd);
                   
unsigned long get_ptime_offset(FrameInfo *fi);
void set_ptime_display(FrameInfo *fi, unsigned long offset);
void get_display_time(unsigned long secs_result, unsigned char frames,
                      char *result);
unsigned long secs_to_frames(unsigned long secs);
void frames_to_time(unsigned long in_frames, unsigned long *secs,
                    unsigned char *frames, unsigned char quantization);
void rate_to_text(unsigned char rate, char *text);
void quantization_to_text(unsigned char quantization, char *text);
char * safe_strcat(char *dest, const char *src, int len);

@interface DATController : NSObject
{
    IBOutlet NSTextField *driveInfo;
    IBOutlet NSTextField *driveStatus;
    IBOutlet NSTextField *timeText;
    IBOutlet NSTextField *attrText;
    IBOutlet NSTextField *errorText;
    IBOutlet NSTextField *filenameText;
    IBOutlet NSTextField *fileDurationText;
    IBOutlet NSButton *readButton;
    IBOutlet NSButton *stopButton;
    IBOutlet NSButton *rewindButton;
    IBOutlet NSButton *ejectButton;
    IBOutlet NSButton *pauseButton;
    IBOutlet NSButton *resumeButton;
    IBOutlet NSButton *insertingTapeCheckbox;
    IBOutlet NSTextView *logText;
    IBOutlet NSTextField *currentProgStart;
    IBOutlet NSTextField *currentFileForProg;
    IBOutlet NSTextField *currentIncludeError;
    IBOutlet NSTextField *currentErrorLimit;
    IBOutlet NSTextField *currentWriteMetadata;
    IBOutlet NSTextField *currentWriteLog;
	IBOutlet NSWindow *prefsWindow;
    IBOutlet NSButton *prefsProgStart;
    IBOutlet NSButton *prefsFileForProg;
    IBOutlet NSButton *prefsIncludeError;
    IBOutlet NSTextField *prefsErrorLimit;
    IBOutlet NSButton *prefsWriteMetadata;
    IBOutlet NSButton *prefsWriteLog;

    DATDrive *theDrive;
    Boolean need_drive_info;
    Boolean drive_ready;
    Boolean need_ready_transition;
    Boolean stop_timer;
    Boolean need_initial_positioning;
    Boolean doing_unload;
    Boolean reading_position;
    Boolean first_frame;
    Boolean stop_requested;
    Boolean pause_requested;
    Boolean have_data_handle;
    Boolean have_info_handle;
	Boolean have_log_handle;
	Boolean log_file_open;
    int read_error_count_left;
    int read_error_count_right;
    int read_error_count_frames;
    NSTimer *statusTimer;
    unsigned char readBuffer[DAT_FRAME_SIZE];
	unsigned char writeBuffer[1920 * 4];
    char file_path[128];
    char file_name[64];
    char file_extension[64];
    int file_counter;
    char datapath[268];
    NSFileHandle *datafile;
    NSFileHandle *infofile;
	NSFileHandle *logfile;
    NSString * dataFileString;
    NSString * infoFileString;
	NSString * logFileString;
    unsigned char *ah;		// AIFF header
    unsigned long expected_frame;
    unsigned long samples_written;
    unsigned long frames_read;
    unsigned long frames_written;
    unsigned char file_sample_rate;
	unsigned char file_quantization;
    int file_error_count;
    int adjusted_file_error_count;
    Boolean errors_exceeded;
    Boolean wait_for_prog;
	FrameInfo file_end_info;

	// settings variables
	Boolean readAtProgramStart;
	Boolean fileForEachProgram;
	Boolean includeErrorFrames;
	int errorLimit;
	Boolean writeMetadata;
	Boolean writeLog;
}

#define READ_AT_PROGRAM_START_KEY "ReadAtProgramStart"
#define FILE_FOR_EACH_PROGRAM_KEY "FileForEachProgram"
#define INCLUDE_ERROR_FRAMES_KEY "IncludeErrorFrames"
#define ERROR_LIMIT_KEY "ErrorLimit"
#define WRITE_METADATA_KEY "WriteMetadata"
#define WRITE_LOG_KEY "WriteLog"

- (void) handleCustomEvent:(NSEvent *)theEvent;
- (void) writeToLog:(char *)logtext;
- (void) updateDriveStatus;
- (void) do_updateDriveStatus:(Boolean *)is_ready;
- (void) driveReadyChanged;
- (void) driveReadyOk;
- (int) setAudioMode:(Boolean *)did_load;
- (void) endLoad;
- (void) endRead;
- (void) positionTape;
- (void) newPositionRead:(Boolean)cleanup;
- (void) newDataRead:(Boolean)cleanup;
- (void) getFrameInfo:(FrameInfo *)fi withFirst:(Boolean)first;
- (void) displayFrameInfo:(FrameInfo *)fi;
- (void) updateActivePrefs;
- (void) updateWindowPrefs;
- (void) updateDefaultsPrefs;
- (void) updateErrorLimit;
- (Boolean) getNewFile;
- (Boolean) getNewFileHandles;
- (int) initAudioFile:(FrameInfo *)fi;
- (int) writeAudioFile:(FrameInfo *)fi;
- (void) finishAudioFile;
- (void) writeFrameInfo:(FrameInfo *)fi;
- (IBAction)read:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)rewind:(id)sender;
- (IBAction)eject:(id)sender;
- (IBAction)pause:(id)sender;
- (IBAction)resume:(id)sender;
- (IBAction)inserting_checkbox:(id)sender;
- (IBAction)preferences:(id)sender;
- (IBAction)prefDefaults:(id)sender;
- (IBAction)prefClose:(id)sender;
- (IBAction)prefProgStart:(id)sender;
- (IBAction)prefProgFiles:(id)sender;
- (IBAction)prefIncludeError:(id)sender;
- (IBAction)prefErrorLimit:(id)sender;
- (IBAction)prefWriteMetadata:(id)sender;
- (IBAction)prefWriteLog:(id)sender;
@end
