# Place validation at lifecycle gates

Canopy runs no repository validation after individual edits. Before commit, Lefthook runs targeted `moon fmt` and `moon info` and stops when they produce changes for review; before push, it runs only checks selected for the pushed file classes. GitHub CI validates the exact pull-request commit and remains the only full-workspace build, test, and end-to-end gate.
