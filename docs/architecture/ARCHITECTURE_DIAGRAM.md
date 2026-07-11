# System Architecture

This diagram illustrates the high-level architecture of the Lambda Calculus CRDT Editor, showing the data flow between the Text CRDT, the Incremental Parser, and the Projectional Editor.

```mermaid
graph TD
    %% Subsystems
    subgraph "Text Layer (CRDT)"
        Doc[TextState\n(FugueMax)]
        OpLog[OpLog]
        Undo[UndoManager]
    end

    subgraph "Model Layer"
        Parser[Incremental Parser]
        AST[AST Term]
        ProjNode[ProjNode Tree\n(Stable IDs)]
    end

    subgraph "Projection Layer"
        TreeEditor[TreeEditorState\n(Selection, Drag/Drop)]
        TextEditor[Text View]
        SyncEditor[SyncEditor Facade]
    end

    subgraph "Network"
        Peers((Peers))
        Ephemeral[EphemeralStore\n(Presence)]
    end

    %% Data Flow - Text Edit
    TextEditor -- "insert/delete" --> SyncEditor
    SyncEditor -- "update" --> Doc
    Doc -- "ops" --> OpLog
    Doc -- "text change" --> Parser
    Parser -- "reparse" --> AST
    AST -- "reconcile" --> ProjNode
    ProjNode -- "update" --> TreeEditor

    %% Data Flow - Tree Edit (Round Trip)
    TreeEditor -- "TreeEditOp" --> SyncEditor
    SyncEditor -- "apply_edit_to_proj" --> ProjNode
    ProjNode -- "unparse" --> SyncEditor
    SyncEditor -- "diff & set_text" --> Doc
    Doc -- "propagate" --> TextEditor

    %% Synchronization
    Doc <-- "SyncMessage" --> Peers
    OpLog -- "history" --> Undo
    
    %% Ephemeral
    TreeEditor -- "cursor/selection" --> Ephemeral
    Ephemeral <-- "broadcast" --> Peers

    %% Styling
    classDef text fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef model fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef proj fill:#fff3e0,stroke:#ef6c00,stroke-width:2px;
    classDef net fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;

    class Doc,OpLog,Undo text;
    class Parser,AST,ProjNode model;
    class TreeEditor,TextEditor,SyncEditor proj;
    class Peers,Ephemeral net;
```

## Key Components

1.  **SyncEditor**: The central coordinator that ensures consistency between the text and tree views.
2.  **TextState**: The ground truth for the document state, managed by the `event-graph-walker` CRDT.
3.  **ProjNode**: A projection-specific AST that maintains stable identities (`NodeId`) across edits, enabling the tree editor to preserve state (selection, collapse) even when the underlying text changes.
4.  **Round-Trip Editing**: Structural edits in the tree view are applied to the `ProjNode` tree, unparsed to text, and then applied to the `TextState`. This ensures that all edits, regardless of origin, are eventually consistent and collaborative.
