import { LambdaClient } from './lambda-client';

const SIGNAL_LAB_EXAMPLE = `fn increment(x : Int) {
  x + 1
}

fn decrement(x : Int) {
  x - 1
}

fn double(x : Int) {
  x + x
}

fn triple(x : Int) {
  x + x + x
}

fn compose(f : Int -> Int, g : Int -> Int, x : Int) {
  f (g x)
}

fn twice(f : Int -> Int, x : Int) {
  f (f x)
}

fn fourTimes(f : Int -> Int, x : Int) {
  twice f (twice f x)
}

fn choose(flag : Int, yes : Int, no : Int) {
  if flag then {
    yes
  } else {
    no
  }
}

let calibrate = compose increment double
let amplify = compose triple calibrate
let stabilize = fourTimes increment

let rawSignal = 4
let stableSignal = stabilize rawSignal
let amplifiedSignal = amplify stableSignal
let output = choose 1 amplifiedSignal (decrement amplifiedSignal)

output`;

export function LambdaRoute() {
  return (
    <LambdaClient>
      <div>
        <div className="container">
          <h1 data-route-heading tabIndex={-1}>Mini-ML CRDT Editor</h1>
          <p className="subtitle">Collaborative real-time editor with live evaluation</p>

          <div className="lambda-app" inert data-lambda-ready="false">
            <div id="status" className="status">Loading JavaScript...</div>

            <div className="panel network-panel">
              <h2>Network Collaboration (Beta)</h2>
              <div className="network-controls">
                <button id="connect-btn" className="network-btn primary-btn">
                  Connect to Network
                </button>
                <button id="disconnect-btn" className="network-btn secondary-btn" disabled>
                  Disconnect
                </button>
                <span id="network-status" className="network-status-text">Not connected</span>
              </div>
              <div className="network-info">
                <p>Connect to collaborate with other peers in real-time. Make sure the signaling server is running:</p>
                <pre style={{ marginTop: 5 }}>node apps/web/signaling-server.js</pre>
              </div>
            </div>

            <div className="docs-section">
              <h2>Mini-ML Syntax</h2>

              <div className="docs-grid">
                <div>
                  <h3>Definitions</h3>
                  <pre>let x = 42
fn double(x : Int) &#123; x + x &#125;
let result = double 5
result</pre>

                  <h3>Functions &amp; Application</h3>
                  <pre>fn inc(x : Int) &#123; x + 1 &#125;
fn twice(f : Int -&gt; Int, x : Int) &#123;
  f (f x)
&#125;
let result = twice inc 0
result</pre>
                </div>

                <div>
                  <h3>Conditionals</h3>
                  <pre>fn choose(x : Int) &#123; if x then &#123;
  x + 1
&#125; else &#123;
  42
&#125; &#125;
let result = choose 5
result</pre>

                  <h3>Grammar (EBNF)</h3>
                  <pre>Module       ::= ((FnDef | LetDef) '\n')* Expression?
FnDef       ::= 'fn' Identifier ParamList Block
LetDef      ::= 'let' Identifier '=' Expression
ParamList   ::= '(' Identifier (':' Type)? (',' Identifier (':' Type)?)* ')'
Expression  ::= Lambda | IfThenElse | BinaryOp
Lambda      ::= ParamList '=&gt;' (Expression | Block)
BinaryOp    ::= Application (('+' | '-') Application)*
Application ::= Atom+
Atom        ::= Integer | Variable | Block | '(' Expression ')'
Block       ::= '&#123;' ((FnDef | LetDef) (';' | '\n'))* Expression? '&#125;'
IfThenElse  ::= 'if' Expression 'then' Expression 'else' Expression</pre>
                </div>
              </div>
            </div>

            <div className="editor-container">
              <div className="examples-bar">
                <span className="examples-label">Examples:</span>
                <button className="example-btn" data-example="fn double(x : Int) {&#10;  x + x&#10;}&#10;let result = double 5&#10;result">Basics</button>
                <button className="example-btn" data-example="fn inc(n : Int) { n + 1 }&#10;fn twice(f : Int -> Int, x : Int) {&#10;  f (f x)&#10;}&#10;let result = twice inc 0&#10;result">Composition</button>
                <button className="example-btn" data-example="fn add(x : Int, y : Int) { x + y }&#10;let add5 = add 5&#10;let sum = add5 10&#10;sum">Currying</button>
                <button className="example-btn" data-example="fn choose(x : Int) { if x then {&#10;  x + 1&#10;} else {&#10;  42&#10;} }&#10;let a = choose 0&#10;let b = choose 5&#10;a + b">Conditional</button>
                <button className="example-btn" data-example="fn compose(f : Int -> Int, g : Int -> Int, x : Int) {&#10;  f (g x)&#10;}&#10;fn double(x : Int) { x + x }&#10;fn inc(x : Int) { x + 1 }&#10;let f = compose inc double&#10;f 5">Pipeline</button>
                <button className="example-btn" data-example={SIGNAL_LAB_EXAMPLE}>Signal Lab</button>
              </div>
              <div id="editor" contentEditable="plaintext-only" spellCheck={false} data-route-focus="editor"></div>
              <section className="structural-search" aria-labelledby="structural-search-heading">
                <div className="structural-search-heading-row">
                  <h2 id="structural-search-heading">Structural matches</h2>
                  <span id="structural-search-status" role="status" aria-live="polite">
                    No structural matches
                  </span>
                </div>
                <ol id="structural-search-results"></ol>
              </section>
            </div>

            <div className="info-panel">
              <div className="panel">
                <h2>AST Visualization</h2>
                <div id="ast-graph">
                  <p style={{ color: '#858585', textAlign: 'center', padding: 20 }}>Waiting for input...</p>
                </div>
              </div>

              <div className="panel">
                <h2>AST Structure &amp; Diagnostics</h2>
                <div style={{ marginBottom: 15 }}>
                  <h3 style={{ color: '#9cdcfe', fontSize: 13, marginBottom: 8 }}>Structure</h3>
                  <pre id="ast-output" style={{ background: '#1e1e1e', padding: 10, borderRadius: 3, overflowX: 'auto', fontSize: 12, maxHeight: 300, overflowY: 'auto' }}>Waiting for input...</pre>
                </div>
                <div>
                  <h3 style={{ color: '#9cdcfe', fontSize: 13, marginBottom: 8 }}>Diagnostics</h3>
                  <ul id="error-output" className="error-list">
                    <li>No errors</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </LambdaClient>
  );
}
