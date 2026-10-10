# Adding a camera

Measure what Adobe DNG Converter writes for another Sony camera, add its row to the match table, and prove the row with the drift check.

## Overview

The match table has one camera. To add another, you measure the values that
Adobe DNG Converter writes for it, at each ISO setting. Read
<doc:HowTheMatchWorks> first: it says what each value does.

You need four things:

- **The camera,** and a lens that does not report itself to the camera.
- **Adobe DNG Converter,** in the Applications folder. It is the reference.
- **exiftool and dnglab.**
- **A Sony camera that writes ARW.** The tool converts Sony ARW files only,
  and the match reads Sony tags.

Three rules hold for the whole task:

- **No value is estimated.** Each number in the table is a copy of what
  Adobe DNG Converter wrote. When a value does not behave as this page says,
  stop, and open an issue with the numbers.
- **Work on copies of the frames.** Never commit a photo. The numbers are
  enough.
- **Never pass `-h` to Adobe DNG Converter.** It opens a window, and the
  process never returns. Never pass `-f` to dnglab: it writes over a file.

The commands below use three folders: `/path/to/frames` with the ARW files,
`/path/to/adobe` for Adobe's DNG files, and the root of the repo.

## Measure

1. **Make the frames.** Make one ARW at each ISO setting of the camera, as
   compressed raw, with a lens that does not report itself. Make a second
   set, or a part of one, with another lens. A lens that reports itself is
   the useful one: the camera changes its daylight levels for such a lens,
   and step 7 needs frames with different levels. Copy the frames to
   `/path/to/frames`.

2. **Write down the firmware version.** The ARW holds it:

   ```bash
   exiftool -T -filename -IFD0:Software "/path/to/frames"
   ```

   ```
   one file.ARW	ILCE-7SM3 v5.00
   ```

3. **Convert each ARW with Adobe DNG Converter,** into a folder of its own.
   Make the folder first. `-c` is lossless compression, and `-d` is the
   output folder.

   ```bash
   for f in "/path/to/frames"/*.ARW; do
     "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter" -c -d "/path/to/adobe" "$f"
   done
   ```

   The icon of the converter shows in the Dock for each file. Count the DNG
   files afterwards: Adobe DNG Converter returns 0 also for a file that it
   cannot read, and then makes no DNG.

4. **Read the facts of each ARW.** `-n` gives each value as the file holds
   it, and `-T` gives one row for each file, with tabs between the cells.

   ```bash
   exiftool -n -T -filename -IFD0:Model -ExifIFD:ISO -SR2SubIFD:WB_RGBLevelsDaylight -SubIFD:DistortionCorrection -SubIFD:SonyRawFileType "/path/to/frames"
   ```

   ```
   one file.ARW	ILCE-7SM3	800	2597 1024 1556	255	2
   ```

   The cells are the file name, the model, the ISO, the three daylight
   levels (red, green, blue), 255 for "no lens-correction data", and 2 for
   compressed raw. These are the five facts that the tool reads for each
   photo.

5. **Read Adobe's values from each DNG.**

   ```bash
   exiftool -n -T -filename -SubIFD:WhiteLevel -IFD0:BaselineExposure -IFD0:CameraCalibration1 -IFD0:CameraCalibration2 -IFD0:NoiseProfile -IFD0:BaselineNoise -IFD0:BaselineSharpness -SubIFD:AntiAliasStrength -SubIFD:BayerGreenSplit "/path/to/adobe"
   ```

   ```
   one file.dng	16383	0.15	0.9888 0 0 0 1 0 0 0 0.9955	0.9888 0 0 0 1 0 0 0 0.9955	9.17112993057145e-05 1.80963827089821e-07 0.000132825207904173 1.86198019692823e-07 6.88838025482567e-05 1.77853114759923e-07	0.6	1.25	1	250
   ```

   The cells are the file name, the white level, the baseline exposure, the
   two calibration matrices, the six numbers of the noise profile, and the
   four values that follow it. Keep this output as text. The data file needs
   the noise numbers with exactly these digits.

## Check what the numbers do

6. **Check what varies.** For the A7S III, these facts hold. Check each one
   for your camera.

   | Value | For the A7S III |
   |---|---|
   | `WhiteLevel`, `BaselineNoise`, `BaselineSharpness`, `AntiAliasStrength`, `BayerGreenSplit` | The same in every file |
   | `BaselineExposure` | Varies with the ISO only |
   | `NoiseProfile` | Varies with the ISO only. Two frames at one ISO, with different lenses and shutter times, have the same six numbers. |
   | `CameraCalibration1` and `CameraCalibration2` | Equal to each other. A diagonal, `r 0 0 0 1 0 0 0 b`, that varies with the daylight levels only. |

   If a value of your camera varies with something else, the table cannot
   hold it. Stop, and open an issue with the numbers.

7. **Find the reference levels, and check the calibration rule.** For each
   file, multiply r by the red daylight level, and b by the blue level. For
   the frame above:

   ```
   0.9888 * 2597 = 2567.9     the red reference is 2568
   0.9955 * 1556 = 1549.0     the blue reference is 1549
   ```

   Each product is a little off a whole number, because Adobe's r and b are
   rounded to 4 decimal places. Take the whole number that is nearest in
   every file. Then turn the rule around, and compute r and b for every file
   from the two reference numbers:

   ```
   r = red reference / red level       rounded to 4 decimal places
   b = blue reference / blue level     rounded to 4 decimal places
   ```

   The rule must give Adobe's exact text for every file, with both lenses.
   If it does not, the camera cannot be added by this method. Also write
   down the green level. It is 1024 in every A7S III file, and the tool
   gives no match to a frame with another green level.

## Add the row

8. **Write the data file.** Put it beside
   `docs/superpowers/specs/2026-10-09-ilce-7sm3-adobe-values.json`, in the
   same shape: the model, the five values that do not vary, the three
   reference levels, and one entry for each ISO with its baseline exposure
   and its six noise numbers. Keep each noise number as text, with the
   digits that exiftool printed. In `about`, give the camera, the firmware
   version, the version of Adobe DNG Converter, and the date.

9. **Write the test first.** `testTheTableIsTheDataFile` in
   `Tests/DesqueezeCoreTests/AdobeMatchTests.swift` compares the table in
   the code with the data file, value by value. It pins one camera today.
   Extend it to your data file, run it, and see it fail.

   The tests on the real programs have a rule of their own for a frame that
   the table covers: `factsOfACoveredFrame`, in
   `Tests/DesqueezeCoreTests/DnglabIntegrationTests.swift`. It reads the
   data file of the A7S III, and it does not ask the table in the code. It
   takes the five facts of the frame from exiftool, each tag alone, and not
   from the reader of the tool. Extend it to your data file too. Until you
   do, the drift check skips for a frame of your camera, and a skip proves
   nothing.

10. **Add the row.** In `Sources/DesqueezeCore/AdobeMatch.swift`, add a
    `Camera` value with the digits of the data file, and add it to
    `cameras`. Run the test again, and see it pass.

## Run the drift check

The drift check is the proof against the real programs. It converts one
frame with Adobe DNG Converter and with dnglab plus your row, reads the nine
tags from both DNG files, and compares them as numbers.

11. Make the fixtures from one of your frames that the new row covers, then
    run the check:

    ```bash
    scripts/make_fixtures.sh "/path/to/frames/one file.ARW"
    swift test --filter AdobeDriftTests
    ```

    Look for the line of the test case in the output. It must end with
    `passed`, and a time:

    ```
    Test Case '-[DesqueezeCoreTests.AdobeDriftTests testEveryMatchedTagOfADnglabDNGEqualsAdobeDNGConverters]' passed
    ```

    The check skips, and does not fail, when the fixtures, dnglab or Adobe
    DNG Converter are absent. It also skips for a frame that the rule of
    step 9 does not cover. The same line then ends with `skipped`, and the
    suite still reads as passed. A skipped check proves nothing. When a tag
    differs, the failure names the tag and gives both values.

Run the drift check again after a new version of either converter, and
after new camera firmware. A value can change, and only this check finds it.

## Update the documents

12. Several documents say that the table has one camera: the design, in its
    sections 13.4 and 13.9, `README.md`, and on this site
    <doc:CamerasAndLenses> and <doc:HowTheMatchWorks>. Change them. Add a
    row to `docs/decisions.md` and a line to `CHANGELOG.md`. Give the
    firmware version and the ISO settings that you measured.

The values for the A7S III were also checked in the render: both DNG files
of a frame went through Camera Raw, and the renders were compared pixel by
pixel. If you can do that for your camera, put the numbers in the
pull request. `CONTRIBUTING.md` in the repo has the rules for a pull
request.
