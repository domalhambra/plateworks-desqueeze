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
| The tool never changes or deletes an ARW. It moves one only on the request of the next section. | The ARW is the original. | The tests on the real programs compare the bytes of the ARW before and after: `testARealRunConvertsTagsChecksAndClearsTheBackups`, `testARealPlanAndRunWithDnglabFirstConvertMatchTagAndClearTheBackups`. With the request, the ARW in the trash of the test has the bytes of the source: `testARealRunWithTheOptionOnLeavesTheDNGAndMovesItsARWToTheInjectedTrash`. |
| A DNG keeps its `_original` backup until the tag reads back correctly. Then the backup goes to the Trash. Nothing is deleted. | In a folder with no ARW files, the DNG is the only copy of the photo. | `testAFailedCheckRestoresTheBackup`, `testAReadBackWithNoTagAfterAGoodWriteCountsAsFailedAndRestores`, `testARefusedTrashCountsAsSetAndKeepsTheBackup` |
| A failed write restores only when a backup exists. | A write that fails makes no backup, and the file is unchanged. | `testAFailedWriteWithNoBackupDoesNotRestore` |
| The tool sets tags. It never resamples or exports an image. | The tag is reversible, and the pixels are the photographer's. | No test can prove an absence. The tests pin the exact arguments of every exiftool call, for example `testWritePassesTheFactorAsOneArgument`. |

## An original moves only on request

A run can move each original ARW to the Trash (design 14). This is the one
feature that takes a file of the user out of the folder, so every rule here
has a test that was seen to fail against a break.

| Rule | Why | Guard |
|---|---|---|
| The option is off unless the caller turns it on. It has no default value in ``DesqueezeJob`` and in ``DesqueezeOperations``. | No caller moves an original by leaving an argument out, and none forgets to say that it does not. | A call with no `trashOriginals` does not compile. `testWithTheOptionOffAConversionThatPassedMovesNoARWAndAsksTheDiskNothing`, `testWithTheOptionOffAFailedConversionMovesNoARW`, `testWithTheOptionOffACancelledRunMovesNoARW`, `testWithTheOptionOffABlockedDNGMovesNoARW`, `testARealRunWithTheOptionOffLeavesTheARW` |
| Only an ARW that this run converted can go, and only when every check holds. One function decides. | The run watched that conversion. For an ARW that an earlier run converted, the only link to its DNG is a name. | `testAnOriginalMovesOnlyWhenEveryLineHolds`, `testNoSingleLineMovesAnOriginal`, `testOnlyTheARWFilesOfThisRunsConversionsReachTheTrash`, `testLine1AnARWWhoseConversionFailedStaysAndGetsNoSecondNote` |
| A DNG with no full match keeps its original. | That DNG is not complete, and the ARW is the way to convert the photo again. | `testLine2ADNGWithNoFullMatchKeepsItsOriginalAndCostsNoRead` |
| A DNG whose tag step did not end at the factor keeps its original. | A blocked DNG and a failed write are not a complete result. | `testLine3ADNGWhoseWriteFailedKeepsItsOriginal`, `testLine3ABlockedDNGKeepsItsOriginal` |
| The ARW must be the file that was converted: the same size, modification date and file number, read without following a link, and a regular file. The second read is the last thing before the move. | Another program can replace or write the ARW while the run works. A link or a folder is never the tool's to move. | `testLine4AnARWThatChangedDuringTheRunStays`, `testLine4ALinkOrAFolderAtTheNameOfTheARWNeverGoes`, `testTheDNGIsCheckedFirstAndTheOriginalIsReadLast`, `testTheRecordOfARealFileAFolderALinkAndNothing`, `testARealARWThatChangesAfterItsConversionStays` |
| Directly before the move, the DNG is a regular file with bytes, names the ARW, and holds the factor. One exiftool read, with `SubIFD` named. | The DNG is the only copy that stays in the folder. | `testTheReadHasExactlyTheArgumentsOfTheDesign`, `testTheParserReadsRealExiftoolOutput`, `testLine5ADNGThatIsNotARegularFileWithBytesKeepsItsOriginal`, `testLine5ADNGThatNamesAnotherARWOrHasAnotherScaleKeepsItsOriginal` |
| The originals move after the tag of the last DNG, and not after a cancel. | No ARW may go while its DNG still waits for its tag. A person who cancels wants the run to stop. | `testNoARWMovesBeforeTheTagOfTheLastDNG`, `testACancelBeforeTheFifthStepMovesNoARWAndTheRunIsStopped`, `testACancelDuringTheFifthStepLetsTheARWInWorkCompleteAndStartsNoOther` |
| The move is ``BackupHandling/trashFile(_:)``, once. A refusal keeps the ARW. There is no delete and no second way. | "Nothing is deleted" must hold for the original most of all. | `testATrashThatRefusesKeepsTheARWWithTheSystemsWordsAndTriesNothingElse` |
| Remove never moves an original. | Remove converts nothing, so it has no original of its own. | `testRemoveMovesNothingWhateverItIsGiven`, `testAPlanForRemoveHasNoSuchStepWhateverItIsGiven` |
| The step runs inside the lock of the folder. | A second run must not work in the folder while an original moves. | `testTheFifthStepRunsWhileTheRunHoldsTheLockOfTheFolder` |
| The dry run asks the same function, and reads no ARW and no DNG. | A dry run that lists a move that no run makes is worse than no dry run. | `testAPlanHasOneStepForEachOriginalAfterTheWriteSteps`, `testAConversionWithNoFullMatchGetsNoStepAndTheNoteOfTheRun`, `testAPlanReadsNoRecordStartsNoCheckAndMovesNothing`, `testThePlanSummaryIsTheSummaryOfARunWhereEveryStepPasses` |
| In the command line tool, only the flag `--trash-originals` turns the option on. No environment variable and no saved setting does. | A setting that stays on is a way to remove files that the person wants. | In `Tests/DesqueezeCLITests/`: `testTheFlagTurnsTheOptionOnAndNothingElseDoes`, `testWithoutTheFlagNoARWReachesTheTrashAndTheTextHasNoLineAboutOriginals`, `testWithoutTheFlagTheKeysSayOffAlsoWithAVariableThatLooksLikeTheFlag` |
| In the window, the box is off at every launch, for every folder and after every run. It is never saved, and no launch argument turns it on. | A box that stays on from an earlier day is the main way this option can remove files that the person wants. | In `App/PlateworksDesqueezeTests/`: `testTheBoxIsOffAtTheStartAndDoesNotShowWithNoFolder`, `testWithTheBoxOnARunMovesTheOriginalAndTheBoxIsOffAfterIt`, `testTheBoxIsOffAfterACancelledRun`, `testTheBoxIsOffWhenAnotherFolderLoadsAndWhenTheSameFolderLoadsAgain`, `testTheBoxIsNeverSavedAndTheNextModelStartsWithItOff`, `testNoLaunchArgumentTurnsTheBoxOn` |
| The MCP server never moves an original. It gives the core false, and it has no argument for the option. | An agent must never be able to remove a person's originals, by request or by mistake. | In `MCPServer/Tests/DesqueezeMCPTests/`: `testACallThatAsksToMoveTheOriginalsIsRefusedAndMovesNoARW`, `testToolsListHasThreeToolsWithTheirSchemasAndAnnotations` |

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
| An ARW gets no converter when the longest name that a conversion makes for it would have more than 255 UTF-16 units, counted in its decomposed form. That name is exiftool's temporary file beside the work file, so the longest base name has 222 units. One rule holds for both converters. | No file can have that name. dnglab converted such a photo, and exiftool then failed in the match with the system's words, which do not say what to do. A count in bytes refused a long name with accented or Japanese letters that works. | `testTheLongestBaseNameThatConvertsHas222Letters`, `testTheLengthOfANameIsCountedInUTF16UnitsAndNotInBytes`, `testTheLengthOfANameIsCountedInItsDecomposedForm`, `testARealRunStartsNoConverterForAnARWWithANameThatIsTooLong`, `testARealPhotoWithTheLongestNameConvertsAndIsTaggedAndLeavesNoFile` |
| Never pass `-f` to dnglab. | `-f` writes over an existing file. | `testNoCallEverPassesTheOverrideFlag` |
| Never pass `-h` to Adobe DNG Converter. | It opens a window, and the process never returns. | `testTheOutputNameIsTheNameOfTheWorkFileAndNeverAPath` |

## A conversion passes only on proof

| Rule | Why | Guard |
|---|---|---|
| A conversion passes only when the exit code is 0, the work file has bytes, and the rename passed. | Adobe DNG Converter returns 0 for a file that it cannot read. A converter that is ended in work can leave a file with no bytes. | `testThrowsWhenExitIsZeroButNoDNGExists`, `testExitZeroWithAnEmptyWorkFileFailsAndReportsTheWorkFile` |
| For dnglab, every tag of the match must also read back. | A DNG that looks complete and is not matched would render differently, with no note. | `testAReadBackThatDiffersInOneTagReportsTheWorkFileAndNamesTheTag` |
| A program that a signal ended has no exit code. | The signal number must not read as an exit code, and half a file must not pass as a whole one. | `testAProgramThatASignalEndedIsAnErrorThatNamesTheSignal` |

## Only the tool's own files go to the Trash

An original that the person asked the run to move is the one exception. The
section "An original moves only on request" has its rules.

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
