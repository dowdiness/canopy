///|
/// Workflow node metadata shared by the MoonBit context menu and library.
priv struct CanvasNodeCatalogItem {
  key : String
  label : String
  description : String
}

///|
fn workflow_node_catalog() -> Array[CanvasNodeCatalogItem] {
  [
    {
      key: "timer",
      label: "Timer trigger",
      description: "Start on a schedule",
    },
    { key: "http", label: "HTTP request", description: "Call an external API", },
    {
      key: "formatter",
      label: "Format data",
      description: "Map and reshape payloads",
    },
    { key: "condition", label: "Condition", description: "Branch by a rule", },
    { key: "loop", label: "Loop", description: "Repeat over records", },
    {
      key: "parallel",
      label: "Parallel split",
      description: "Run branches together",
    },
    {
      key: "custom",
      label: "Custom step",
      description: "Reserve an integration point",
    },
  ]
}
