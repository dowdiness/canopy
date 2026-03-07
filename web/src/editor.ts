// Lambda Calculus Editor with CRDT backend

import { SyntaxHighlighter } from './syntax-highlighter';
import { NetworkSync } from './network';
import * as crdt from '@moonbit/crdt';
import * as graphviz from '@moonbit/graphviz';

export interface ASTNode {
  kind: string | [string, string | number];
  start: number;
  end: number;
  node_id: number;
  children: ASTNode[];
}

// Convert MoonBit's derived ToJson enum format to ASTNode.
// MoonBit array format: ["App", ["Lam", "x", ["Var", "x"]], ["Int", 42]]
// String for no-data variants: "Unit"
function termJsonToAstNode(raw: unknown, counter = { id: 0 }): ASTNode {
  const nodeId = counter.id++;

  // String variant (e.g., "Unit")
  if (typeof raw === 'string') {
    return { kind: raw, start: 0, end: 0, node_id: nodeId, children: [] };
  }

  if (!Array.isArray(raw) || raw.length === 0) {
    return { kind: ['Error', 'unknown'], start: 0, end: 0, node_id: nodeId, children: [] };
  }

  const tag = raw[0] as string;

  // Format: ["Tag", ...args] where args are values or nested terms
  switch (tag) {
    case 'Int':   // ["Int", 42]
      return { kind: ['Int', raw[1] as number], start: 0, end: 0, node_id: nodeId, children: [] };
    case 'Var':   // ["Var", "x"]
      return { kind: ['Var', raw[1] as string], start: 0, end: 0, node_id: nodeId, children: [] };
    case 'Lam':   // ["Lam", "x", <body>]
      return {
        kind: ['Lam', raw[1] as string], start: 0, end: 0, node_id: nodeId,
        children: [termJsonToAstNode(raw[2], counter)],
      };
    case 'App':   // ["App", <func>, <arg>]
      return {
        kind: 'App', start: 0, end: 0, node_id: nodeId,
        children: [termJsonToAstNode(raw[1], counter), termJsonToAstNode(raw[2], counter)],
      };
    case 'Bop':   // ["Bop", "Plus"|"Minus", <left>, <right>]
      return {
        kind: ['Bop', raw[1] as string], start: 0, end: 0, node_id: nodeId,
        children: [termJsonToAstNode(raw[2], counter), termJsonToAstNode(raw[3], counter)],
      };
    case 'If':    // ["If", <cond>, <then>, <else>]
      return {
        kind: 'If', start: 0, end: 0, node_id: nodeId,
        children: [
          termJsonToAstNode(raw[1], counter),
          termJsonToAstNode(raw[2], counter),
          termJsonToAstNode(raw[3], counter),
        ],
      };
    case 'Let':   // ["Let", "x", <init>, <body>]
      return {
        kind: ['Let', raw[1] as string], start: 0, end: 0, node_id: nodeId,
        children: [termJsonToAstNode(raw[2], counter), termJsonToAstNode(raw[3], counter)],
      };
    case 'Error': // ["Error", "msg"]
      return { kind: ['Error', raw[1] as string], start: 0, end: 0, node_id: nodeId, children: [] };
    default:
      return { kind: tag, start: 0, end: 0, node_id: nodeId, children: [] };
  }
}

export class LambdaEditor {
  private handle: number;
  private agentId: string;
  private editorElement: HTMLDivElement;
  private astGraphElement: HTMLDivElement;
  private astOutputElement: HTMLPreElement;
  private errorElement: HTMLUListElement;
  private highlighter: SyntaxHighlighter;
  private updating: boolean = false;
  private networkSync: NetworkSync | null = null;

  constructor(agentId: string) {
    this.agentId = agentId;
    console.log('Creating editor with agent ID:', agentId);
    console.log('create_editor function:', crdt.create_editor);

    try {
      this.handle = crdt.create_editor(agentId);
      console.log('Editor handle created:', this.handle);
    } catch (error) {
      console.error('Failed to create editor:', error);
      throw error;
    }

    this.editorElement = document.getElementById('editor') as HTMLDivElement;
    this.astGraphElement = document.getElementById('ast-graph') as HTMLDivElement;
    this.astOutputElement = document.getElementById('ast-output') as HTMLPreElement;
    this.errorElement = document.getElementById('error-output') as HTMLUListElement;

    this.highlighter = new SyntaxHighlighter();

    this.attachEventHandlers();
  }

  private lastSyncedText: string = '';
  private updateScheduled: boolean = false;

  private attachEventHandlers(): void {
    // Update AST/errors after user stops typing
    this.editorElement.addEventListener('input', () => {
      if (this.updateScheduled) return;

      this.updateScheduled = true;
      requestAnimationFrame(() => {
        this.updateScheduled = false;
        this.updateUI();
      });
    });
  }

  private updateUI(): void {
    if (this.updating) return;
    this.updating = true;

    try {

      const currentText = this.editorElement.textContent || '';

      // Sync DOM text to MoonBit if it has changed
      if (currentText !== this.lastSyncedText) {
        try {
          this.syncTextToMoonBit(currentText);
          this.lastSyncedText = currentText;
        } catch (syncError) {
          console.error('Failed to sync text to MoonBit:', syncError);
          // Continue anyway - try to read state even if sync failed
        }
      }

      // Get AST and errors from MoonBit
      try {
        const astJson = crdt.get_ast_json(this.handle);
        const errorsJson = crdt.get_errors_json(this.handle);

        console.log('Raw AST JSON:', astJson);
        console.log('Raw errors JSON:', errorsJson);

        // Validate JSON before parsing
        if (!astJson || typeof astJson !== 'string') {
          throw new Error('Invalid AST JSON: ' + typeof astJson);
        }
        if (!errorsJson || typeof errorsJson !== 'string') {
          throw new Error('Invalid errors JSON: ' + typeof errorsJson);
        }

        const rawAst = JSON.parse(astJson);
        const ast: ASTNode = termJsonToAstNode(rawAst);
        const errors: string[] = JSON.parse(errorsJson);

        // Update side panels with current AST and errors
        this.updateASTDisplay();
        this.updateASTStructure(ast);
        this.updateErrorsDisplay(errors);
      } catch (parseError) {
        console.error('Failed to parse AST/errors:', parseError);
        const errorMsg = parseError instanceof Error ? parseError.message : String(parseError);
        this.updateErrorsDisplay(['Parse error: ' + errorMsg]);
      }
    } catch (error) {
      console.error('Unexpected error in updateUI:', error);
    } finally {
      this.updating = false;
    }
  }

  private syncTextToMoonBit(newText: string): void {
    try {
      // Use the new set_text function for efficient sync
      crdt.set_text(this.handle, newText);
    } catch (error) {
      console.error('Error in syncTextToMoonBit:', error);
      throw error;
    }
  }


  private async updateASTDisplay(): Promise<void> {
    try {
      // Get DOT representation from MoonBit
      const dotString = crdt.get_ast_dot_resolved(this.handle);
      console.log('[AST Display] DOT string length:', dotString.length);

      console.log('[AST Display] Rendering DOT to SVG using graphviz package...');
      // Render DOT to SVG using MoonBit graphviz package
      const svg = graphviz.render_dot_to_svg(dotString);
      console.log('[AST Display] SVG rendered, type:', typeof svg, 'length:', svg.length);

      // Update the DOM with the SVG
      this.astGraphElement.innerHTML = svg;

      // Style the SVG for dark theme
      const svgElement = this.astGraphElement.querySelector('svg');
      if (svgElement) {
        // Remove forced width - let CSS control sizing
        svgElement.style.height = 'auto';

        // Ensure dark theme compatibility
        const graphElement = svgElement.querySelector('g.graph');
        if (graphElement) {
          // Remove white background if present
          const polygon = graphElement.querySelector('polygon');
          if (polygon) {
            polygon.setAttribute('fill', 'transparent');
          }
        }
      }
    } catch (error) {
      console.error('Failed to render AST graph:', error);
      this.astGraphElement.innerHTML = `<p style="color: #ff0000; text-align: center; padding: 20px;">Error rendering graph: ${error}</p>`;
    }
  }

  private updateASTStructure(ast: ASTNode): void {
    const prettyPrinted = this.highlighter.printTermNode(ast)
    const treeView = this.highlighter.formatAST(ast)
    this.astOutputElement.textContent = `Expression: ${prettyPrinted}\n\nAST:\n${treeView}`
  }

  private updateErrorsDisplay(errors: string[]): void {
    if (errors.length === 0) {
      this.errorElement.innerHTML = '<li>No errors ✓</li>';
    } else {
      this.errorElement.innerHTML = errors
        .map(err => `<li class="error-item">${this.escapeHTML(err)}</li>`)
        .join('');
    }
  }

  private escapeHTML(text: string): string {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  getText(): string {
    return crdt.get_text(this.handle);
  }

  getHandle(): number {
    return this.handle;
  }

  getAgentId(): string {
    return this.agentId;
  }

  /**
   * Enable network synchronization
   */
  async enableNetworkSync(wsUrl: string): Promise<void> {
    if (this.networkSync) {
      console.warn('Network sync already enabled');
      return;
    }

    this.networkSync = new NetworkSync(this.handle, this.agentId);

    // Set callback for remote text changes
    this.networkSync.setTextChangeCallback((remoteText) => {
      this.handleRemoteTextChange(remoteText);
    });

    // Connect to signaling server
    await this.networkSync.connect(wsUrl);

    // Broadcast operations on local changes
    this.editorElement.addEventListener('input', () => {
      if (this.networkSync && !this.updating) {
        // Debounce broadcasts
        setTimeout(() => {
          this.networkSync?.broadcastOperations();
        }, 100);
      }
    });

    console.log('[LambdaEditor] Network sync enabled');
  }

  /**
   * Disable network synchronization
   */
  disableNetworkSync(): void {
    if (this.networkSync) {
      this.networkSync.disconnect();
      this.networkSync = null;
      console.log('[LambdaEditor] Network sync disabled');
    }
  }

  /**
   * Get network status
   */
  getNetworkStatus(): { connected: boolean; peers: number } | null {
    return this.networkSync?.getStatus() ?? null;
  }

  /**
   * Handle text changes from remote peers
   */
  private handleRemoteTextChange(remoteText: string): void {
    console.log('[LambdaEditor] Received remote text change');

    // Update DOM without triggering local sync
    this.updating = true;
    this.editorElement.textContent = remoteText;
    this.lastSyncedText = remoteText;

    // Update AST and errors
    try {
      const astJson = crdt.get_ast_json(this.handle);
      const errorsJson = crdt.get_errors_json(this.handle);

      const rawAst = JSON.parse(astJson);
      const ast: ASTNode = termJsonToAstNode(rawAst);
      const errors: string[] = JSON.parse(errorsJson);

      this.updateASTDisplay();
      this.updateASTStructure(ast);
      this.updateErrorsDisplay(errors);
    } catch (error) {
      console.error('Error updating UI after remote change:', error);
    } finally {
      this.updating = false;
    }
  }
}
