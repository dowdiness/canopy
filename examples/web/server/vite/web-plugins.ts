import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { moonbitPlugin } from '../../vite-plugin-moonbit';
import { astGrepPlugin } from './ast-grep';
import { genUiFeasibilityPlugin } from './genui-feasibility';
import { piResumeChatPlugin } from './resume-chat';

const moonbitModules = [
  {
    name: '@moonbit/crdt-lambda',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js',
  },
  {
    name: '@moonbit/crdt-json',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/json/json.js',
  },
  {
    name: '@moonbit/crdt-markdown',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js',
  },
  {
    name: '@moonbit/crdt-jsx',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.js',
  },
  {
    name: '@moonbit/graphviz',
    path: '../../graphviz',
    output: '../_build/js/release/build/dowdiness/graphviz/browser/browser.js',
  },
];

export const moonbitImportIds = moonbitModules.map((module) => module.name);

/** Compose the plugins required by every examples/web demo server. */
export function createWebPlugins({ watchMoonBit }: { readonly watchMoonBit: boolean }) {
  return [
    react(),
    tailwindcss(),
    genUiFeasibilityPlugin(),
    piResumeChatPlugin(),
    astGrepPlugin(),
    moonbitPlugin({ modules: moonbitModules, watch: watchMoonBit }),
  ];
}
