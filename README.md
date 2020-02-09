## DATXtract Notes — Version 1.3, November, 2007

### What is DATXtract?

DATXtract is a program for transferring the contents of audio DAT tapes into
AIFF files.

### What's New in Version 1.3

* 32 KHz tapes, recorded in either standard or LP (Long-Play) mode, are now
supported.

* A new preference setting allows frames with errors to be included in the
AIFF file.  While DATXtract has no built-in error correction, this option
allows errors to be corrected by other means.  The default action is to omit
error frames from the file.

* Metadata and log files may now be created for each audio file.  The metadata
files describes the characteristics of the recording.  The log file includes
any errors or other messages that were logged for the audio file.  Preference
settings control the creation of these files.

* Preference handling has been improved.  A standard Preferences dialog is now
used, and preferences and window positions are now persistent.

### What are the requirements for using DATXtract?

* OS X 10.2 and later, including OS X 10.5 (Leopard).  Older versions of OS X
are untested but may work.

* Either an Intel or PPC Mac.  DATXtract is not native on Intel Macs, but
works under emulation with no known problems.  A universal binary version of
DATXtract is planned for the next release.

* An audio-capable computer DAT drive.  "Audio-capable" means that the drive
must have firmware which supports the set of SCSI commands for working with
audio tapes.  Although computer DAT drives are typically connected via a SCSI
connection, they may also be connected via Firewire by using a
SCSI-to-Firewire adapter.  At this time of this writing, information about
using audio DATs in DDS drives, including firmware information, is available
on Ade Rixon's web pages at:
http://homepage.ntlworld.com/adrian.rixon/personal/ade/dat-dds/index.html

### How has DATXtract been tested?

I've tested DATXtract in my own environment, which consists of Tascam DA-20
and DA-30 decks for recording tapes, and a Sony SDT-9000 drive for use with
DATXtract.  DATXtract should work with other recorders and computer drives as
well.  If there are problems using other hardware I will attempt to fix them,
as time permits.

I can't guarantee the performance or reliability of DATXtract in your
environment.  Perform your own tests before using it for any critical
applications.

### How do I use DATXtract?

If you are using a tape drive with a SCSI connection, the tape drive must be
connected and turned on at the time you boot your machine.  Reboot if
necessary in order to achieve this.  If you are using a Firewire connection,
all you have to do is turn on the drive then connect the Firewire cable to the
Mac.  Next, launch DATXtract.  You should see in it's window that it has
located the tape drive.  Select the checkbox for Inserting a tape and wait
until the status shows Inserting tape set. Then insert the tape into the
drive.  When the drive has completely finished loading the tape, uncheck
Inserting a tape.  DATXtract will load the tape in audio mode if necessary,
then position the tape at the start.  Click on the Read button to read the
contents of the tape into a file.  There are two preferences for controlling
what Read does.  You can select not reading from the tape until the first
start of a program is detected.  You can also select starting a new output
file each time a new program is detected.  When new files are started, a
sequential number will be appended to the file name you chose.  There are also
error handling preferences for controlling whether frames with errors are
included in the AIFF file, and how many error should be allowed for a file
before reading stops.

When using a Firewire adapter, the Inserting a tape checkbox should always be
used, as described above.  However, with a direct SCSI connection normally it
will not be necessary to use the checkbox.  Also, it is not necessary to use
the checkbox when the drive is  connected and the tape is completely loaded
before DATXtract is launched.  The tape drive will stop responding if the
checkbox is not used when it should have been.  In that case,  DATXtract will
display an error message indicating a drive problem needs to be corrected.  To
do that,  quit from DATXtract, eject the tape from the drive, and unplug the
Firewire connection.  Then start over again following the above directions.

DATXtract uses somewhat arbitrary rules for handling errors.  It ignores
errors during the first 200 frames, since errors are common at the very start
of a recording.  Also, it will stop if the number of errors exceeds the error
limit setting.  The default limit is 15 errors, but you can enter a different
value in the preferences.  Check the Log section of the window to see if any
errors have been encountered during reading, and how DATXtract handled them.

### Is DATXtract supported?

I'll provide informal support for DATXtract as time permits.  Write to me
using peter@pdicamillo.org for help with questions and problems.  Also, the
download site contains the DATXtract source code which may be used for support
purposes.

### How do I get DATXtract?

The download site for DATXtract is: http://pdicamillo.org/~peter/datxtract/

Peter DiCamillo
peter@pdicamillo.org
November, 2007
