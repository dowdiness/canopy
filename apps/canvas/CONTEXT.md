# Canvas

A 2D workflow canvas where nodes have positions independent of graph connectivity. This glossary names what the user is placing.

## Language

**Source graph**:
The graph-dsl text that names nodes and edges. It does not contain positions.
_Avoid_: 正本, source of truth, Authority

**Live layout**:
The node positions of the running canvas. It is not part of the Source graph and does not survive reload.
_Avoid_: Local layout, 配置, Arrange, Auto layout, Readable placement

**Selection**:
The currently chosen nodes and edges. Both may be chosen at once. It is not a Connected group.
_Avoid_: Connected group

**Viewport**:
The visible window onto the canvas.
_Avoid_: 画面, screen

**Connected group**:
The nodes reachable from one another through edges. It is not the Selection.
_Avoid_: Selection

**Auto layout**:
A mode that rewrites Live layout by itself for human reading: connected groups stay together, unrelated groups may sit apart, spacing is comfortable — neither flush nor far-flung — heights align, then the Viewport pans and zooms so the result fits. It ignores the Selection.
_Avoid_: Readable placement, explicit command, Arrange, Arrange compactly, packing, Skyline, layout engine, 帯
