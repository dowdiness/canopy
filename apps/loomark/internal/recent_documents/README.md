# Recent documents

This package owns Recent documents presentation and its keyed, demand-driven
DocumentLead projection. The app supplies resolved `Seed` values and handles
`Intent` values; repository and persistence policy do not cross this boundary.

Lead extraction is performed only from accepted source text. The pure keyed
projection is retained while the visible row branch is disposable when the
sidebar is hidden. Each row renders a direct icon-only Delete button rather than
an Actions menu; its bounded row label is used for the accessible name and
confirmation text.
