# Safety rules for code

The rules that a change must not break, why each one exists, and the test that guards it.

## Overview

This tool changes photo files, and a photo can be the only copy. So the
rules below are strict, and a change that makes a file less safe does not
merge. The list in `CLAUDE.md` of the repo is the source. This page gives
each rule its reason and its guard.

Before you change a rule, change the design first. The design is the
contract. Then write the test, see it fail, and change the code.

The test names below are functions in `Tests/DesqueezeCoreTests/`, unless a
row says another folder.

## The original is never at risk

| Rule | Why | Guard |
|---|---|---|
| The tool never changes, moves or deletes an ARW. | The ARW is the original. | The tests on the real programs compare the bytes of the ARW before and after: `testARealRunConvertsTagsChecksAndClearsTheBackups`, `testARealPlanAndRunWithDnglabFirstConvertMatchTagAndClearTheBackups`. |
| A DNG keeps its `_original` backup until the tag reads back correctly. Then the backup goes to the Trash. Nothing is deleted. | In a folder with no ARW files, the DNG is the only copy of the photo. | `testAFailedCheckRestoresTheBackup`, `testAReadBackWithNoTagAfterAGoodWriteCountsAsFailedAndRestores`, `testARefusedTrashCountsAsSetAndKeepsTheBackup` |
| A failed write restores only when a backup exists. | A write that fails makes no backup, and the file is unchanged. | `testAFailedWriteWithNoBackupDoesNotRestore` |
| The tool sets tags. It never resamples or exports an image. | The tag is reversible, and the pixels are the photographer's. | No test can prove an absence. The tests pin the exact arguments of every exiftool call, for example `testWritePassesTheFactorAsOneArgument`. |

## The tool does not touch a backup that it did not make

| Rule | Why | Guard |
|---|---|---|
| A DNG with an existing `_original` is blocked, not skipped and not written. | exiftool never replaces an existing `_original`. A write would leave a backup of the wrong state, and the tool would then send that backup to the Trash. | `testAnOlderBackupBlocksAFileThatIsNotAtTheFactor`, `testAFileWithAnExistingBackupIsBlockedWithANote` |
| "Skipped" means only "already at this value". | A count of skipped files must never hide a file that the run did not look at. | `testABlockedFileIsNotInTheSkippedCount`, `testALeftoverBackupFileIsSkippedNotBlocked` |
| An orphan backup is reported and left. | It can be the only copy of a photo. | `testTheJobDoesNotTouchAnOrphanBackup`, `testARunReportsEachOrphanBackupFirstAndTouchesNone` |
| An orphan backup claims its ARW. | A conversion would make a second DNG of a photo whose DNG is waiting to be renamed back. | `testAnOrphanBackupClaimsItsARWByBaseName`, `testARealRunDoesNotConvertAnARWWhoseDNGIsWaitingAsAnOrphanBackup` |

## A conversion never writes over a file

| Rule | Why | Guard |
|---|---|---|
| Only a pending ARW goes to a converter. A DNG claims an ARW by base name, or by `OriginalRawFileName`. | An ARW that is wrongly pending gives a failed file, or a second DNG of a photo whose DNG has another name. An ARW that is wrongly claimed only waits. | `testAnARWIsPendingOnlyWhenNoDNGHasItsBaseName`, `testARenamedDNGClaimsItsARWThroughOriginalRawFileName` |
| When anything has the name `<base>.dng`, no converter starts. | The scan can be a moment old. This check is at the last moment. | `testRefusesToStartWhenTheDNGExistsAlready`, `testAnythingAtTheNameStopsTheConverterBeforeItStarts` |
| A converter writes a hidden work file, never `<base>.dng`. | `<base>.dng` appears only when it is complete and matched. A run that ends hard leaves a hidden file and a pending ARW, never a DNG that looks complete. | `testTheWorkFileIsAHiddenFileBesideTheARWWithTheBaseNameInIt`, `testTheScanDoesNotSeeAWorkFile` |
| The rename of the work file fails when the name is taken. | A DNG that another program made while the converter worked is never replaced. | `ExclusiveRenameTests`, `ExclusiveRenameVolumeTests`, `testADNGThatAnotherProgramMakesJustBeforeTheRenameIsLeftAsItIs` |
| An ARW whose work-file name would be longer than 255 bytes gets no converter. | No file can have that name. A converter fails on it with words that do not say what to do. | `testAnARWWhoseWorkFileNameIsTooLongStartsNoConverterAndTouchesNothing`, `testARealRunStartsNoConverterForAnARWWithANameThatIsTooLong` |
| Never pass `-f` to dnglab. | `-f` writes over an existing file. | `testNoCallEverPassesTheOverrideFlag` |
| Never pass `-h` to Adobe DNG Converter. | It opens a window, and the process never returns. | `testTheOutputNameIsTheNameOfTheWorkFileAndNeverAPath` |

## A conversion passes only on proof

| Rule | Why | Guard |
|---|---|---|
| A conversion passes only when the exit code is 0, the work file has bytes, and the rename passed. | Adobe DNG Converter returns 0 for a file that it cannot read. A converter that is ended in work can leave a file with no bytes. | `testThrowsWhenExitIsZeroButNoDNGExists`, `testExitZeroWithAnEmptyWorkFileFailsAndReportsTheWorkFile` |
| For dnglab, every tag of the match must also read back. | A DNG that looks complete and is not matched would render differently, with no note. | `testAReadBackThatDiffersInOneTagReportsTheWorkFileAndNamesTheTag` |
| A program that a signal ended has no exit code. | The signal number must not read as an exit code, and half a file must not pass as a whole one. | `testAProgramThatASignalEndedIsAnErrorThatNamesTheSignal` |

## Only the tool's own files go to the Trash

| Rule | Why | Guard |
|---|---|---|
| A failed conversion sends only its own work file to the Trash. A `<base>.dng` never moves. | The name of the work file is the tool's own, so no file of the user is at risk. The job checks the path itself, and does not take the word of the converter. | `testOnlyTheExactWorkFileOfTheARWIsMovedForEitherConverter`, `testTheDNGOfTheARWIsNeverMovedForEitherConverter` |
| A leftover is discarded only when it is a regular file. | A folder can hold the person's files, and a link is not the tool's to judge. | `testAFolderOrALinkAtALeftoverNameStopsTheARWAndNothingGoesToTheTrash` |
| The Trash is a parameter with no default. | No caller reaches the Trash by leaving an argument out, and no test fills a person's Trash. | The signature of ``FileBackups/init(trash:)``. `testTheRealTrashIsANamedConstant` |

## One run in a folder at a time

| Rule | Why | Guard |
|---|---|---|
| A run holds an advisory lock on the folder, from before its scan to its end. A second run does not start, and reads and changes nothing. | The second run would take the first run's work file for a leftover and send it to the Trash. Each run could then act on the other's half-written file. | `testARunDoesNotStartWhileAnotherRunHoldsTheLock`, `testTheLockIsTakenBeforeTheScanAndHeldToTheLastFile`. With two processes, in `Tests/DesqueezeCLITests/`: `testASecondRunInTheSameFolderIsRefusedAndTheFirstCompletes` |
| The lock is `flock` on the folder itself. No lock file is made. | A lock file would be a file of the tool in a photo folder, and a run that ends hard would leave a stale one. This lock goes with the process. | `testTheLockMakesNoFileAndChangesNoFileInTheFolder`, `testASecondTakeInTheSameProcessIsBusyUntilTheFirstIsReleased` |
| The run releases the lock when it returns and when it throws. | A lock that stays would stop the next run in the same process, as in the window. | `testTheLockIsReleasedAfterARunWhoseScanThrows`, `testTwoRunsInARowBothPass` |
| A scan and a dry run take no lock. | They change no file. A person must be able to look at a folder while a run works in it. | `testADryRunTakesNoLock` |
| On a volume that gives no lock for a folder, the run goes on without one. | A lock that the volume does not give must not stop every run on that volume. | `testOnAVolumeWithNoSuchLockTheRunGoesOnWithoutOne` |
| A program that the run starts does not get the lock. | The lock must go when the run ends, also while a converter still works. | `testTheDescriptorOfTheLockIsClosedInAProgramThatTheRunStarts` |

Each front end has a test of what it says to a run that did not start:
`testARunWhileAnotherRunWorksInTheFolderGivesOneWithTheSentenceAndStartsNoProgram`
in `Tests/DesqueezeCLITests/`,
`testARunWhileAnotherRunWorksInTheFolderIsAToolErrorAndAScanAndADryRunAreNot`
in `MCPServer/Tests/DesqueezeMCPTests/`, and
`testARunWhileAnotherRunWorksInTheFolderShowsTheSentenceAndReturnsToIdle`
in `App/PlateworksDesqueezeTests/`.

## The scan

| Rule | Why | Guard |
|---|---|---|
| Top level only. Hidden files are ignored. | A subfolder of a shoot folder holds exports and the data of other programs. | `testReadsTheTopLevelOnly`, `testIgnoresHiddenFilesBackupsAndFoldersNamedLikeFiles` |
| Every read and write of `DefaultScale` names the group `SubIFD`. | That is the image directory that Camera Raw reads. | `testReadFolderPassesTheExactArguments`, `testWritePassesTheFactorAsOneArgument`, `testReadPassesTheExactArgumentsAndParsesTheValue` |
| A DNG with an unknown scale is never skipped. | exiftool prints no value both for a DNG with no tag and for a file that it cannot read. Only the write tells the two apart. | `testAnUnknownScaleIsNeverSkipped` |
| A run starts with its own scan. | Files and tag values change between a scan and a click. | `testARunFromAFolderScansAgainOnEveryCall` |
| The run and the dry run ask the same functions. | A dry run that disagrees with its run is worse than no dry run. | `testThePlanSummaryIsTheSummaryOfARunWhereEveryStepPasses`, `testARealPlanChangesNoFileAndAgreesWithTheRunThatFollows` |

## The match

| Rule | Why | Guard |
|---|---|---|
| Each number of the match table comes from a measurement. Never estimate one. | A wrong value changes how every photo of that camera renders, with no error. | `testTheTableIsTheDataFile`, and the drift check `AdobeDriftTests` against the real Adobe DNG Converter |
| The drift check decides with no code of the tool whether the table covers the fixture frame. | A broken reader of the facts must fail the check. It must not turn the check into a skip. | The helper `factsOfACoveredFrame` in `Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift` asks exiftool for each fact, and reads the data file. |

## Stopping

| Rule | Why | Guard |
|---|---|---|
| A cancel is honored between files, never in the middle of one. | A tool that ended at once would leave a backup beside the file that exiftool was writing. | `testCancelStopsBeforeTheNextFile`. In `Tests/DesqueezeCLITests/`: `InterruptTests` |
| A program starts in a process group of its own. | A Control-C in the terminal must not reach an exiftool that is writing a file. | `testAProgramStartsInAProcessGroupOfItsOwn` |
| The server runs one tool call at a time, and answers the call in work before it ends. | Two calls of one client must not meet in a folder: the second would be refused by the lock. A call in work must not end with a file half done. | In `MCPServer/Tests/DesqueezeMCPTests/`: `testCallsRunOneAtATime`, `testClosingStandardInputDuringARunLetsTheRunComplete` |

## The shape of the code

These rules have no test. Check them when you review a change.

- **`DesqueezeCore` and `DesqueezeCLI` import Foundation only.** AppKit and
  SwiftUI stay in `App/`. Only `MCPServer/` has third-party code. The root
  `Package.swift` has no dependency.
- **File work stays in the core, behind protocols,** so a test uses a fake.
- **Not sandboxed, offline, private.** `project.yml` has no entitlements
  file, on purpose: a sandboxed app cannot start the three programs. The
  code makes no network request and collects no data.

One more rule has tests:

- **Every sentence that two front ends say is made once, in the core.** A
  front end reads the `kind` of a note, never the English sentence. Text for
  a person is in sentence case, with no exclamation mark and no emoji.
  Guards: `testTheSentencesAboutWhoConvertsAreMadeOnce`,
  `testEachKindIsWrittenAsItsName`, and in `Tests/DesqueezeCLITests/`,
  `testHelpIsPlain`. The same holds for a rule about when a line shows: the
  Lightroom line shows only after a run that set a photo, and the core
  decides it for the window and the tool
  (`testTheLightroomLineShowsWhenTheRunSetAtLeastOnePhoto`,
  `testADryRunNeverShowsTheLightroomLine`).

## Two known gaps

On a volume with no exclusive rename, such as ExFAT, ``ExclusiveRename``
checks the name and then renames. A file that another program makes at
`<base>.dng` in the moment between the two calls is replaced. This is the
one path on which the tool can replace a file that it did not make.
`testOnExFATAFreeNameTakesTheCheckAndThenAPlainRename` pins that ExFAT takes
this path.

On a volume that gives no lock for a folder, ``FolderLock`` lets the run go
on, and two runs can then work in one folder. APFS, HFS+, ExFAT and FAT32
gave the lock when they were measured, and
`testOnExFATAFolderLockIsHeldAndASecondTakeIsBusy` pins ExFAT. A network
volume was not measured. The source comment of ``FolderLock`` has each
answer of the system and what it means.
