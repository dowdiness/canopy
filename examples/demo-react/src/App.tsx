import { useState } from 'react';
import { LambdaEditor } from './features/lambda-editor';
import { CollaborativeDemo } from './features/collaborative';

type DemoMode = 'single' | 'collaborative';

function App() {
  const [mode, setMode] = useState<DemoMode>('single');

  return (
    <div className="app">
      <header className="header">
        <h1>Lambda CRDT Editor</h1>
        <p className="subtitle">React + EditorProtocol + eg-walker Integration Demo</p>
      </header>

      <nav className="nav">
        <button
          className={`nav-btn ${mode === 'single' ? 'active' : ''}`}
          onClick={() => setMode('single')}
        >
          Single Editor
        </button>
        <button
          className={`nav-btn ${mode === 'collaborative' ? 'active' : ''}`}
          onClick={() => setMode('collaborative')}
        >
          Collaborative Demo
        </button>
      </nav>

      <main className="main">
        {mode === 'single' ? (
          <LambdaEditor />
        ) : (
          <CollaborativeDemo />
        )}
      </main>

      <footer className="footer">
        <p>
          Built with{' '}
          <a href="https://react.dev" target="_blank" rel="noreferrer">React</a>
          {' + '}
          <a href="https://www.moonbitlang.com" target="_blank" rel="noreferrer">MoonBit</a>
          {' (EditorProtocol)'}
        </p>
      </footer>
    </div>
  );
}

export default App;
