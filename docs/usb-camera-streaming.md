# USB camera streaming on Linux

This note covers the simplest setup for using a USB UVC camera on Linux as a
source of images for a computer vision pipeline.

## Goal

Get a continuous stream of frames from a USB webcam so WATERBOT can:

- inspect the live image
- save images for debugging
- pass frames into a CV pipeline
- eventually report where a detected object appears in image coordinates

## Mental model

For this phase, think of the system like this:

`USB camera -> Linux video device -> frame stream -> CV code`

On Linux, a USB webcam usually appears as one or more `/dev/video*` devices.
The common interface is:

- `UVC` on the USB side
- `V4L2` (`Video4Linux2`) on the Linux side

For practical purposes, this means the camera can usually be treated as a
standard video device that produces frames.

## Continuous stream of images

A "continuous stream of images" usually means:

1. Open the camera device such as `/dev/video0`
2. Choose a resolution, frame rate, and pixel format
3. Read frames in a loop
4. Feed those frames into the next stage of the CV pipeline

The data you receive is often one of:

- `MJPEG`: compressed JPEG-like frames, common for webcams
- `YUYV`: uncompressed pixel format, larger bandwidth but simple

For early prototyping, `1280x720 @ 30fps` with `MJPEG` is a good default.

## Tools to validate the camera

Install these packages if needed:

```bash
sudo apt install v4l-utils ffmpeg
```

These tools are enough to confirm that the camera is visible and streaming.

## Step 1: list video devices

Check whether Linux sees the camera:

```bash
v4l2-ctl --list-devices
```

Expected outcome:

- the webcam appears by name
- it exposes one or more nodes such as `/dev/video0`

## Step 2: inspect supported formats

Find out what the camera can stream:

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
```

This shows:

- pixel formats such as `MJPG` or `YUYV`
- supported resolutions
- supported frame rates

Pick one stable mode first instead of trying to maximize quality immediately.

## Step 3: test live streaming

Use `ffplay` to verify that frames arrive continuously:

```bash
ffplay -f v4l2 -framerate 30 -video_size 1280x720 -input_format mjpeg /dev/video0
```

If this opens a live preview, the streaming path is working.

If `mjpeg` does not work, inspect the exact format name from
`--list-formats-ext` and retry with a supported format.

## Step 4: capture a still image

Save one frame to confirm basic capture:

```bash
ffmpeg -f v4l2 -framerate 30 -video_size 1280x720 -input_format mjpeg \
  -i /dev/video0 -frames:v 1 test.jpg
```

This is useful for:

- checking exposure and focus
- collecting sample images for later CV work
- confirming that the selected mode is valid

## How this fits into a CV pipeline

Once streaming works, the next layers are straightforward:

`camera -> frame capture -> preprocessing -> detection -> output coordinates`

Example first milestone:

- capture each frame
- detect a known symbol or marker
- compute its center
- report `(x, y)` pixel coordinates

That is already a complete CV pipeline.

## Interface options for software

There are three realistic ways to consume the camera stream:

### Option 1: shell out to existing tools

This is the simplest way to validate the setup.

Examples:

- `ffplay` for live preview
- `ffmpeg` for saving frames or video

This is a good first step even if the final implementation is written in Zig.

### Option 2: use OpenCV

OpenCV can open a camera and return frames in a loop. This is convenient for
quick experimentation, especially in Python or C++.

### Option 3: use V4L2 directly

This is the most native Linux approach and the best fit for Zig in the long
term because V4L2 is a C-based API.

High-level loop:

1. open `/dev/video0`
2. configure format and frame size
3. start streaming
4. read frames in a loop
5. hand each frame to CV code

## Recommendation for WATERBOT

Start simple:

- use the existing USB webcam
- validate it with `v4l2-ctl` and `ffplay`
- choose one stable mode such as `1280x720 MJPEG`
- only then build detection logic on top of that frame stream

For Zig, the likely progression is:

1. validate streaming with external tools
2. prototype frame handling however is fastest
3. move to direct `V4L2` integration when the rest of the perception loop is
   clear

## Notes and pitfalls

- Some webcams expose multiple `/dev/video*` nodes. Only one may be the main
  image stream.
- Autofocus and auto-exposure can make CV results unstable. This is acceptable
  for initial experiments, but it may need tuning later.
- If frame rate or latency is poor, try lowering resolution before changing
  anything else.
- If `MJPEG` behaves poorly, try `YUYV` and compare stability versus bandwidth.

## Related reading

- [WATERBOT design notes](./DOODLE.md)
- [Boards and modules](./BOARDS.md)
