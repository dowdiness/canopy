import { MarkdownClient } from './markdown-client';

export function MarkdownRoute() {
  return (
    <MarkdownClient>
      <div>
        <div className="container" role="region" aria-labelledby="markdown-route-title" data-route-heading tabIndex={-1}>
          <header className="visually-hidden">
            <h1 id="markdown-route-title"><span>&#9649;</span> Markdown Editor</h1>
          </header>

          <div className="markdown-app" inert data-markdown-ready="false">
            <div className="examples-bar" role="toolbar" aria-label="Markdown examples">
              <button className="example-btn" type="button" title="Apply Hello example" aria-label="Apply Hello example" data-example="# Hello World&#10;&#10;Welcome to the Canopy Markdown editor.&#10;&#10;This editor has three modes: raw, block, and preview.">Hello</button>
              <button className="example-btn" type="button" title="Apply Blog example" aria-label="Apply Blog example" data-example="# Getting Started&#10;&#10;Canopy is an incremental projectional editor.&#10;&#10;## Features&#10;&#10;The editor supports real-time collaboration via CRDT.&#10;&#10;Every keystroke is incrementally parsed and projected into a structured view.">Guide</button>
              <button className="example-btn" type="button" title="Apply List example" aria-label="Apply List example" data-example="# Shopping List&#10;&#10;Things to pick up:&#10;&#10;- Apples&#10;- Bread&#10;- Coffee&#10;- Dark chocolate">List</button>
              <button className="example-btn" type="button" title="Apply Code example" aria-label="Apply Code example" data-example="# README&#10;&#10;A minimal example project.&#10;&#10;## Install&#10;&#10;```bash&#10;npm install&#10;```&#10;&#10;## Usage&#10;&#10;- Run the dev server&#10;- Open the browser&#10;- Start editing">Code</button>
            </div>

            <div className="mode-tabs" role="tablist" aria-label="Editor view">
              <button id="block-tab" className="mode-tab active" type="button" role="tab" title="Block view" aria-label="Block view" aria-selected="true" aria-controls="block-pane" data-mode="block" data-route-focus="mode-block">
                <svg viewBox="0 0 20 20" aria-hidden="true"><rect x="3" y="3" width="5" height="5" rx="1"/><rect x="12" y="3" width="5" height="5" rx="1"/><rect x="3" y="12" width="5" height="5" rx="1"/><rect x="12" y="12" width="5" height="5" rx="1"/></svg>
              </button>
              <button id="raw-tab" className="mode-tab" type="button" role="tab" title="Raw Markdown" aria-label="Raw Markdown" aria-selected="false" aria-controls="raw-pane" tabIndex={-1} data-mode="raw" data-route-focus="mode-raw">
                <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M7.5 5 3 10l4.5 5M12.5 5l4.5 5-4.5 5"/><path d="m11 3-2 14"/></svg>
              </button>
              <button id="preview-tab" className="mode-tab" type="button" role="tab" title="Preview" aria-label="Preview" aria-selected="false" aria-controls="preview-pane" tabIndex={-1} data-mode="preview" data-route-focus="mode-preview">
                <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M2.5 10s2.8-5 7.5-5 7.5 5 7.5 5-2.8 5-7.5 5-7.5-5-7.5-5Z"/><circle cx="10" cy="10" r="2"/></svg>
              </button>
            </div>

            <div className="editor-panel">
              <div className="toolbar" id="toolbar" role="toolbar" aria-label="Block formatting" aria-controls="block-container" data-no-blur>
                <div className="toolbar-group" role="group" aria-label="Text style">
                  <button id="h1-btn" className="toolbar-btn toolbar-btn-heading" type="button" title="Heading 1 (Ctrl+1)" aria-label="Heading 1, Ctrl+1" aria-pressed="false" disabled>H1</button>
                  <button id="h2-btn" className="toolbar-btn toolbar-btn-heading" type="button" title="Heading 2 (Ctrl+2)" aria-label="Heading 2, Ctrl+2" aria-pressed="false" disabled>H2</button>
                  <button id="h3-btn" className="toolbar-btn toolbar-btn-heading" type="button" title="Heading 3 (Ctrl+3)" aria-label="Heading 3, Ctrl+3" aria-pressed="false" disabled>H3</button>
                </div>
                <div className="toolbar-divider" aria-hidden="true"></div>
                <div className="toolbar-group" role="group" aria-label="Block structure">
                  <button id="list-btn" className="toolbar-btn" type="button" title="Toggle list (Ctrl+Shift+L)" aria-label="Toggle list, Ctrl+Shift+L" aria-pressed="false" disabled>
                    <span className="list-glyph" aria-hidden="true"><i></i><i></i><i></i></span>
                  </button>
                </div>
                <div className="toolbar-spacer" aria-hidden="true"></div>
                <div className="toolbar-group toolbar-group-danger" role="group" aria-label="Block actions">
                  <button id="delete-btn" className="toolbar-btn toolbar-btn-delete" type="button" title="Delete block" aria-label="Delete selected block" disabled>
                    <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 6h12M8 3h4l1 3H7l1-3ZM6 6l.7 11h6.6L14 6M8.5 9v5M11.5 9v5"/></svg>
                  </button>
                </div>
              </div>

              <div className="editor-pane" id="raw-pane" role="tabpanel" aria-labelledby="raw-tab" hidden>
                <textarea id="raw-editor" data-route-focus="raw-editor" placeholder="Type Markdown here..." spellCheck={false}></textarea>
              </div>

              <div className="editor-pane" id="block-pane" role="tabpanel" aria-labelledby="block-tab">
                <div id="block-container"></div>
              </div>

              <div className="editor-pane" id="preview-pane" role="tabpanel" aria-labelledby="preview-tab" hidden>
                <div id="preview-container"></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </MarkdownClient>
  );
}
