'use strict';

const path = require('node:path');

function monitorSource(mode, slots, timing, gpu, onTexture, onError) {
  const { MonitorCapture } = require(path.join(
    __dirname, '../../../build/screen-capture-probe/x86_64-pc-windows-msvc/release/glitch_screen_capture.node',
  ));
  let capture;
  let polling;

  return {
    start() {
      capture = new MonitorCapture(mode, slots, undefined, undefined, timing, gpu);
      polling = setInterval(() => {
        let frame;
        try {
          frame = capture.takeFrame();
        } catch (error) {
          onError(error);
          return;
        }
        if (!frame) return;
        onTexture({
          textureInfo: {
            handle: { ntHandle: frame.handle },
            pixelFormat: frame.pixelFormat,
            ...(frame.pixelFormat === 'nv12' && {
              colorSpace: { primaries: 'bt709', transfer: 'gamma22', matrix: 'bt709', range: 'limited' },
            }),
            codedSize: { width: frame.width, height: frame.height },
            timestamp: frame.timestamp,
          },
          release: () => capture.releaseFrame(frame.id),
        });
      }, 4);
    },
    stats: (reset) => capture?.stats(reset),
    stop() {
      clearInterval(polling);
      capture?.stop();
    },
  };
}

module.exports = { monitorSource };
