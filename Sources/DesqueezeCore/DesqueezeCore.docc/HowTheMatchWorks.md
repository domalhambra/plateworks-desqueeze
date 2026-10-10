# How the match works

Why a DNG from dnglab renders darker than Adobe's, the nine tags that close the gap, and how each value was measured.

## Overview

dnglab and Adobe DNG Converter make different DNG files from one ARW, and
Camera Raw renders the two differently. The *match* is a set of tags that
the tool writes into the DNG from dnglab, with exiftool, so that it renders
as the DNG from Adobe DNG Converter does. Each value is a copy of what Adobe
DNG Converter wrote for the same camera. No value is estimated.

The code is ``AdobeMatch``. It is pure: it reads no file. The values are in
a data file, `docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json`,
and the table in the code is a copy of that file.

Everything on this page was measured for one camera, the Sony A7S III
(`ILCE-7SM3`), firmware 5.00, compressed raw, with dnglab 0.8.0, Adobe DNG
Converter 18.7 and exiftool 13.55. For another camera, the method is the
same and every number can differ. <doc:AddingACamera> has the steps.

## The gap

The same ARW at ISO 800 was converted with both converters. Both DNG files
went through Camera Raw with default settings, and the two renders were
compared pixel by pixel.

| The DNG from dnglab | Brightness against Adobe's | Pixels that differ by more than 1/255 |
|---|---|---|
| As it comes | 0.055 stops darker | 66% |
| With `WhiteLevel` and `BaselineExposure` | 0.007 stops darker | 33% |
| With `CameraCalibration1` and `CameraCalibration2` too | 0.002 stops darker | 24% |

With every tag of the match, two more frames gave:

| Frame | Brightness against Adobe's | Pixels that differ by more than 1/255 |
|---|---|---|
| ISO 50 | 0.004 stops darker | 3.5% |
| ISO 12800, a dark frame | 0.027 stops darker | 0.47% |

A matched render is not bit-identical to Adobe's. The mean of each colour
channel is within 0.7%.

## Why the DNG from dnglab is darker

Two values differ, and they pull in opposite directions.

**The white level.** `WhiteLevel` is the raw value that a raw processor
takes as full white. A raw sample is scaled to the range from the black
level to the white level. In the two DNG files of one ISO 800 frame, both
converters write a black level of 512. dnglab writes a white level of 15360,
and Adobe DNG Converter writes 16383.

```
Adobe:   16383 - 512 = 15871
dnglab:  15360 - 512 = 14848
15871 / 14848 = 1.0689, and log2(1.0689) = 0.096 stops
```

So the lower white level alone makes the dnglab DNG 0.096 stops *brighter*.
It also loses highlights: the raw data of the test frame holds samples above
15360, and a white level of 15360 clips them. That is about 0.09 stops of
highlight headroom that Adobe's DNG keeps.

**The baseline exposure.** `BaselineExposure` is an exposure offset, in
stops, that the raw processor adds. Adobe DNG Converter writes 0.15 for this
camera, and -0.85 at ISO 50. dnglab writes no such tag, and a DNG without it
has an offset of 0. This makes Adobe's DNG 0.15 stops brighter.

**Together:**

```
0.15 - 0.096 = 0.054 stops darker
```

The render measured 0.055. The two values must change together. With the
baseline exposure alone, the dnglab DNG still has its lower white level, and
the render overshot Adobe's by 0.077 stops.

## The tags

``AdobeMatch/match(_:)`` gives these nine tags, in this order. Each name has
its exiftool group, because the group decides the image directory that the
tag goes to.

| Tag | Adobe's value for the A7S III | Varies with |
|---|---|---|
| `SubIFD:WhiteLevel` | 16383 | Nothing |
| `IFD0:BaselineExposure` | 0.15. At ISO 50: -0.85. | The ISO |
| `IFD0:CameraCalibration1` | The diagonal `r 0 0 0 1 0 0 0 b`. The next section has the rule. | The daylight levels of the ARW |
| `IFD0:CameraCalibration2` | The same value | The same |
| `IFD0:NoiseProfile` | Six numbers | The ISO |
| `IFD0:BaselineNoise` | 0.6 | Nothing |
| `IFD0:BaselineSharpness` | 1.25 | Nothing |
| `SubIFD:AntiAliasStrength` | 1 | Nothing |
| `SubIFD:BayerGreenSplit` | 250 | Nothing |

The converter also writes a tenth tag, `IFD0:OriginalRawFileName`, with the
file name of the ARW. It is not part of the render. dnglab does not write it
when the ARW is not embedded, and the scan needs it to know that this DNG
belongs to that ARW.

These are in Adobe's DNG, and the match does not copy them:

- `CameraCalibrationSig` and `ProfileCalibrationSig`. They changed nothing
  in the render.
- The embedded camera profile. Camera Raw uses its own profile for the
  camera model.

## The calibration rule

Adobe DNG Converter writes the same 3 by 3 matrix into `CameraCalibration1`
and `CameraCalibration2`. It is a diagonal: `r 0 0 0 1 0 0 0 b`. The two
numbers come from a Sony tag of the ARW, `WB_RGBLevelsDaylight`: the red,
green and blue levels that the camera gives for daylight.

```
r = 2568 / red level      rounded to 4 decimal places
b = 1549 / blue level     rounded to 4 decimal places
The green level must be 1024.
```

2568, 1024 and 1549 are the *reference levels* of the A7S III: an ARW with
exactly these daylight levels gets the identity matrix.

For example, one frame from an adapted lens has the daylight levels
`2597 1024 1556`:

```
r = 2568 / 2597 = 0.98883...  ->  0.9888
b = 1549 / 1556 = 0.99550...  ->  0.9955
CameraCalibration1 = 0.9888 0 0 0 1 0 0 0 0.9955
```

That is the text that Adobe DNG Converter wrote for the same frame.

The rule gave Adobe's exact numbers for all 23 measured files, with two
lenses. The value varies with the lens: the camera changes its daylight
levels for a lens that reports itself.

The code rounds with whole numbers, a half up, so no value passes through a
floating-point number:

```
ten-thousandths = (reference * 20000 + level) / (2 * level)     whole-number division
(2568 * 20000 + 2597) / (2 * 2597) = 51362597 / 5194 = 9888     ->  0.9888
```

A red or a blue level of 0, a green level other than 1024, or no daylight
levels at all, fail rule 3 below. The rule divides by the red and the blue
level, so each must be above 0.

## The noise profile

`NoiseProfile` is six numbers. Adobe DNG Converter writes a different set at
each ISO, and the same set for every
frame at one ISO: four files at ISO 400 and four at ISO 3200, with different
lenses and shutter times, gave the same numbers.

The noise tags matter at a high ISO. At ISO 12800, 5.9% of the pixels
differed without `NoiseProfile`, and 0.47% with it.

The table keeps each of the six numbers as text, with the digits that
exiftool printed, for example `9.17112993057145e-05`. The text goes to
exiftool as it is. It is never parsed into a floating-point number and
printed again, so no digit can change on the way.

## The lens-correction block

The match cannot give one thing. For a frame from a lens that reports itself
to the camera, Adobe DNG Converter writes a lens-correction block into the
DNG (`OpcodeList3`, with a `WarpRectilinear` opcode), from data in the ARW.
dnglab writes none. For a frame from the Sony FE 24-105mm, the two renders
then differed in geometry, in 51% of the pixels.

For a frame from an adapted lens, the ARW says that it has no such data, and
neither converter writes a block. Every frame from an adapted anamorphic
lens is of this kind. The tool reads this from the ARW:

| Tag of the ARW | With `exiftool -n` | Without `-n` |
|---|---|---|
| `SubIFD:DistortionCorrection` | 255 | No correction params available |
| `SubIFD:SonyRawFileType` | 2 | Sony Compressed RAW |

The tool reads the numbers. The words are exiftool's, and a later exiftool
can change them.

## The five rules of a full match

A frame has a *full match* when all five rules hold. ``ARWFacts`` holds the
five facts, and ``AdobeMatch/Rule`` names the rules.

1. The camera model has a row in the table. Today that is `ILCE-7SM3`.
2. The ISO has a row: 50, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640,
   800, 1000, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000 or
   12800. ISO 1250 was not measured.
3. The daylight levels are there, with a green level of 1024, and a red and
   a blue level above 0.
4. The ARW says that it has no lens-correction data: the value 255.
5. The ARW says that it is compressed raw: the value 2. No other kind was
   measured.

A fact that the ARW does not give fails its rule. So does a file that
exiftool cannot read.

What the frame gets depends on the rule that fails:

| Rules | Tags that dnglab's DNG gets | Is it a full match |
|---|---|---|
| All five hold | All nine, and the file name | Yes |
| Only rule 4 fails | All nine, and the file name. The DNG has no lens-correction block. | No |
| Rule 1, 2, 3 or 5 fails | The file name only. The levels are dnglab's own. | No |

``ConverterChoice`` then decides who converts. With both converters
installed, a frame with no full match goes to Adobe DNG Converter, and
dnglab is not tried. With dnglab alone, dnglab converts it, and the result
has a note of the kind `convertedUnmatched`.

## How the match is written

``DnglabConverter`` writes the match into the hidden work file, before the
DNG gets its name. These are the commands of one real conversion, as
`desqueeze run --verbose` prints them. The lines that dnglab prints about
its own work are left out.

```
$ /opt/homebrew/bin/dnglab convert --embed-raw false '/Volumes/Card/Shoot 1/frame.ARW' '/Volumes/Card/Shoot 1/.frame.desqueeze-work.dng'
  exit 0
$ /opt/homebrew/bin/exiftool -m -overwrite_original -SubIFD:WhiteLevel=16383 -IFD0:BaselineExposure=0.15 '-IFD0:CameraCalibration1=0.9888 0 0 0 1 0 0 0 0.9955' '-IFD0:CameraCalibration2=0.9888 0 0 0 1 0 0 0 0.9955' '-IFD0:NoiseProfile=9.17112993057145e-05 1.80963827089821e-07 0.000132825207904173 1.86198019692823e-07 6.88838025482567e-05 1.77853114759923e-07' -IFD0:BaselineNoise=0.6 -IFD0:BaselineSharpness=1.25 -SubIFD:AntiAliasStrength=1 -SubIFD:BayerGreenSplit=250 -IFD0:OriginalRawFileName=frame.ARW '/Volumes/Card/Shoot 1/.frame.desqueeze-work.dng'
  exit 0
  stdout:     1 image files updated
$ /opt/homebrew/bin/exiftool -m -n -T -SubIFD:WhiteLevel -IFD0:BaselineExposure -IFD0:CameraCalibration1 -IFD0:CameraCalibration2 -IFD0:NoiseProfile -IFD0:BaselineNoise -IFD0:BaselineSharpness -SubIFD:AntiAliasStrength -SubIFD:BayerGreenSplit -IFD0:OriginalRawFileName '/Volumes/Card/Shoot 1/.frame.desqueeze-work.dng'
  exit 0
  stdout: 16383	0.15	0.9888 0 0 0 1 0 0 0 0.9955	0.9888 0 0 0 1 0 0 0 0.9955	9.17112993057145e-05 1.80963827089821e-07 0.000132825207904173 1.86198019692823e-07 6.88838025482567e-05 1.77853114759923e-07	0.6	1.25	1	250	frame.ARW
```

1. **Convert.** `--embed-raw false` is needed: without it, dnglab puts the
   whole ARW inside the DNG. The tool never passes `-f`, which writes over
   an existing file.
2. **Write.** One exiftool call writes every tag. `-overwrite_original`
   keeps no backup: the work file is a moment old and has no earlier state.
3. **Read back.** One exiftool call reads every tag. Each number is compared
   as a number: the two must be within one part in a million. The file name
   is compared as text.
4. **Rename.** The work file gets the name `<base>.dng` only after the
   read-back passed.

The conversion passes only when dnglab returned 0, the work file has bytes,
every tag read back, and the rename passed. dnglab's DNG is DNG version 1.6
with lossless raw data, and it passes `exiftool -validate`, also after the
tags are written.

## How it was measured

All measurements were made on copies of the frames.

- **The values.** One ARW at each of 23 ISO settings was converted with
  Adobe DNG Converter. exiftool read the nine tags from each DNG, and the
  facts from each ARW. The values that did not vary went into the table
  once. The values that varied with the ISO went into one row for each ISO.
- **The calibration rule.** The rule was checked against every file. It gave
  Adobe's exact numbers for all 23, with two lenses.
- **The renders.** Both DNG files of a frame went through Camera Raw, in
  Photoshop, with default settings. The two renders were compared pixel by
  pixel, for the brightness and for the part of the pixels that differ by
  more than 1/255. The repo has no script for this compare.

Two tests keep the table honest:

- `testTheTableIsTheDataFile` in `Tests/DesqueezeCoreTests/AdobeMatchTests.swift`
  fails when the table in the code and the data file differ.
- The drift check, `AdobeDriftTests`, converts one real frame with Adobe DNG
  Converter and with dnglab plus the match, and compares all nine tags. It
  fails when a new version of a converter, or new camera firmware, changes a
  value. <doc:AddingACamera> says how to run it.

## What is not known

- No other camera was measured. The white level, the baseline exposure, the
  reference levels and the noise numbers can all differ for another model.
- Only compressed raw was measured.
- The values were measured at firmware 5.00. The tool does not check the
  firmware of a frame.
- ISO 1250 was not measured, and no ISO above 12800.
