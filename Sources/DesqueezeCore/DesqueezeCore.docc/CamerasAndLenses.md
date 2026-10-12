# Cameras and lenses

Which photos get a DNG that renders as Adobe's does, and what happens to every other photo.

## Overview

The tool does two things, and only one of them depends on the camera.

- **The tag does not depend on the camera.** A DNG that you have already
  gets the correct shape, whatever camera and whatever converter made it.
- **The conversion depends on the camera.** dnglab and Adobe DNG Converter
  make different DNG files from one ARW, and Lightroom shows the two a
  little differently. So the tool writes the values that Adobe DNG Converter
  writes into the DNG from dnglab. This is the *match*. The values were
  measured, and they were measured for one camera.

## The lens

The tool sets a horizontal stretch from 1 to 4. The common squeeze factors
are 1.33, 1.5, 1.8 and 2. The tool does not set a vertical stretch.

The match needs a lens that does not report itself to the camera. An
adapted anamorphic lens does not. A lens that reports itself, such as the
Sony FE 24-105mm, is covered below.

## The camera that is measured

| | |
|---|---|
| Camera | Sony A7S III (`ILCE-7SM3`), firmware 5.00 |
| Raw setting | Compressed raw |
| ISO | 50, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000 and 12800. ISO 1250 was not measured. |
| Lens | One that does not report itself to the camera |

A photo with all four has a *full match*: dnglab converts it, and the DNG
gets every value of the match. <doc:HowTheMatchWorks> has the exact rules.

A matched DNG renders close to Adobe's, and not bit-identical to it. The two
renders were compared in Camera Raw, pixel by pixel. At ISO 800 the matched
render was 0.002 stops darker than Adobe's. At ISO 50 it was 0.004 stops
darker, and for a dark frame at ISO 12800 it was 0.027 stops darker. The
mean of each colour channel is within 0.7%. <doc:HowTheMatchWorks> has the
measurements.

## Every other ARW

What happens depends on which converters are installed.

| Installed | A photo with a full match | A photo with no full match |
|---|---|---|
| dnglab and Adobe DNG Converter | dnglab converts it, with the match. | Adobe DNG Converter converts it. The DNG is the file that Adobe makes. |
| dnglab only | dnglab converts it, with the match. | dnglab converts it. The shape is correct. A note says what the DNG lacks. |
| Adobe DNG Converter only | Adobe DNG Converter converts it. | Adobe DNG Converter converts it. |
| Neither | Not converted. | Not converted. |

When dnglab fails on a photo and Adobe DNG Converter is installed, Adobe DNG
Converter gets that photo next.

With dnglab only, a photo with no full match still converts. It counts as
converted, not as failed. Its note says one of two things:

| The photo | The note | What it means |
|---|---|---|
| Another camera, an ISO that was not measured, or a raw setting other than compressed raw | "Converted. The levels are dnglab's own. Install Adobe DNG Converter for the same file that Lightroom makes." | The DNG has none of Adobe's values. Lightroom shows it a little differently from Adobe's DNG. For the A7S III at ISO 800, such a DNG rendered 0.055 stops darker than Adobe's, and dnglab's white level cut about 0.09 stops of highlight headroom. For another camera, the difference was not measured. |
| A lens that reports itself | "Converted. The DNG has no built-in lens correction. Install Adobe DNG Converter for the same file that Lightroom makes." | The DNG has every value of the match. For such a lens, Adobe DNG Converter also writes a lens-correction block from data in the ARW. dnglab writes none, so the two renders differ in geometry. |

A line below each note names the reason, for example "The table of Adobe's
values has no row for ISO 1250."

## Other raw files

The tool converts Sony ARW files only. A raw file from another camera
system is not listed and not touched. Convert it to DNG with a converter of
your choice. The tool then sets the tag in that DNG.

## About Adobe DNG Converter

Adobe DNG Converter is a program from Adobe. It is not part of this
project, the tool does not contain it, and the tool works without it. When
it is installed, the tool uses it for the photos that dnglab cannot match.
<doc:Privacy> speaks for the parts of this project only. It makes no
statement about what Adobe's program does.

Adobe DNG Converter starts as an app for each photo, so its icon shows in
the Dock once for each file that it converts. dnglab opens nothing.

## Known limits

- **One camera.** The table of the match has the A7S III, compressed raw, at
  the ISO settings above. Any other photo goes to Adobe DNG Converter, or
  gets the note.
- **Firmware.** The values were measured at firmware 5.00. The tool does not
  check the firmware of a photo. A later firmware can change a value, and
  the tool cannot know it.
- **Not bit-identical.** A matched render is close to Adobe's and is not the
  same file.
- **The source of the values.** Each value in the table comes from a file
  that Adobe DNG Converter wrote. The project has not yet decided whether a
  built app that is given to other people may carry the table.
- **Converter versions.** dnglab 0.8.0 and Adobe DNG Converter 18.7 are the
  versions that were tested. A later version can write other values.
- **Unusual file names.** exiftool prints a tab or a line end in a file name
  as a period. Two ARW files whose names print the same get no full match.
- **Very long file names.** A base name longer than 222 characters makes
  the name of a temporary file of the conversion too long for the file
  system. No converter starts for that photo, and its note says: "The file
  name is too long. Shorten it, then run again." An accented letter can
  count as two characters. <doc:WhatHappensToYourFiles> has the rule.

The limits that concern files, and not cameras, are in
<doc:WhatHappensToYourFiles>. <doc:AddingACamera> says how to measure
another camera and add it.
