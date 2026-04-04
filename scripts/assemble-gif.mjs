// Assemble PNG frames into an animated GIF using gifenc + pngjs
import { GIFEncoder, quantize, applyPalette } from 'gifenc';
import { PNG } from 'pngjs';
import { readdirSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

const FRAMES_DIR = '/tmp/canopy-demo-frames';
const OUTPUT = 'docs/demo.gif';
const DELAY = 120; // ms per frame

function decodePNG(filePath) {
  const buf = readFileSync(filePath);
  const png = PNG.sync.read(buf);
  return { data: new Uint8Array(png.data), width: png.width, height: png.height };
}

function main() {
  const files = readdirSync(FRAMES_DIR)
    .filter(f => f.endsWith('.png'))
    .sort();

  if (files.length === 0) {
    console.error('No frames found');
    process.exit(1);
  }

  console.log(`Assembling ${files.length} frames...`);

  const first = decodePNG(join(FRAMES_DIR, files[0]));
  const { width, height } = first;

  const gif = GIFEncoder();

  for (let i = 0; i < files.length; i++) {
    const { data: rgba } = decodePNG(join(FRAMES_DIR, files[i]));
    const palette = quantize(rgba, 256);
    const indexed = applyPalette(rgba, palette);
    gif.writeFrame(indexed, width, height, { palette, delay: DELAY });
    if (i % 10 === 0) process.stdout.write('.');
  }

  gif.finish();
  const buffer = gif.bytes();
  writeFileSync(OUTPUT, buffer);
  console.log(`\nGIF saved to ${OUTPUT} (${(buffer.length / 1024).toFixed(0)} KB, ${files.length} frames)`);
}

main();
