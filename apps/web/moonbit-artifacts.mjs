export const moonbitModules = Object.freeze([
  Object.freeze({
    name: '@moonbit/crdt-lambda',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js',
  }),
  Object.freeze({
    name: '@moonbit/crdt-json',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/json/json.js',
  }),
  Object.freeze({
    name: '@moonbit/crdt-markdown',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js',
  }),
  Object.freeze({
    name: '@moonbit/crdt-jsx',
    path: '../..',
    output: '_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.js',
  }),
  Object.freeze({
    name: '@moonbit/graphviz',
    path: '../..',
    output: '_build/js/release/build/dowdiness/graphviz/browser/browser.js',
  }),
]);

export const moonbitImportIds = Object.freeze(
  moonbitModules.map((module) => module.name),
);

export const moonbitBuildCoordinator = Object.freeze({
  path: '../..',
  buildFlags: Object.freeze([]),
});
