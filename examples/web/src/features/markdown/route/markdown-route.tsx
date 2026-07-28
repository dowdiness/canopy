import { MarkdownClient } from './markdown-client';

export function MarkdownRoute() {
  return (
    <MarkdownClient>
      <div>
        <div className="container">
          <header>
            <h1 data-route-heading tabIndex={-1}><span>&#9649;</span> Markdown Editor</h1>
            <p className="subtitle">Block-based Markdown editing with three view modes</p>
          </header>

          <div className="markdown-app" inert data-markdown-ready="false">
            <div className="examples-bar">
              <span className="examples-label">Examples:</span>
              <button className="example-btn" data-example="# Hello World&#10;&#10;Welcome to the Canopy Markdown editor.&#10;&#10;This editor has three modes: raw, block, and preview.">Hello</button>
              <button className="example-btn" data-example="# Getting Started&#10;&#10;Canopy is an incremental projectional editor.&#10;&#10;## Features&#10;&#10;The editor supports real-time collaboration via CRDT.&#10;&#10;Every keystroke is incrementally parsed and projected into a structured view.">Blog</button>
              <button className="example-btn" data-example="# Shopping List&#10;&#10;Things to pick up:&#10;&#10;- Apples&#10;- Bread&#10;- Coffee&#10;- Dark chocolate">List</button>
              <button className="example-btn" data-example="# README&#10;&#10;A minimal example project.&#10;&#10;## Install&#10;&#10;```bash&#10;npm install&#10;```&#10;&#10;## Usage&#10;&#10;- Run the dev server&#10;- Open the browser&#10;- Start editing">Code</button>
            </div>

            <div className="mode-tabs">
              <button className="mode-tab active" data-mode="block" data-route-focus="mode-block">Block</button>
              <button className="mode-tab" data-mode="raw" data-route-focus="mode-raw">Raw</button>
              <button className="mode-tab" data-mode="preview" data-route-focus="mode-preview">Preview</button>
            </div>

            <div className="editor-panel">
              <div className="toolbar" id="toolbar" data-no-blur>
                <div className="toolbar-group">
                  <button id="h1-btn" className="toolbar-btn" type="button" title="Heading 1 (Ctrl+1)" disabled>H1</button>
                  <button id="h2-btn" className="toolbar-btn" type="button" title="Heading 2 (Ctrl+2)" disabled>H2</button>
                  <button id="h3-btn" className="toolbar-btn" type="button" title="Heading 3 (Ctrl+3)" disabled>H3</button>
                </div>
                <div className="toolbar-divider"></div>
                <div className="toolbar-group">
                  <button id="list-btn" className="toolbar-btn" type="button" title="Toggle list (Ctrl+Shift+L)" disabled>List</button>
                </div>
                <div className="toolbar-divider"></div>
                <div className="toolbar-group">
                  <button id="delete-btn" className="toolbar-btn" type="button" title="Delete block" disabled>Delete</button>
                </div>
              </div>

              <div className="editor-pane" id="raw-pane" hidden>
                <textarea id="raw-editor" data-route-focus="raw-editor" placeholder="Type Markdown here..." spellCheck={false}></textarea>
              </div>

              <div className="editor-pane" id="block-pane">
                <div id="block-container"></div>
              </div>

              <div className="editor-pane" id="preview-pane" hidden>
                <div id="preview-container"></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </MarkdownClient>
  );
}
