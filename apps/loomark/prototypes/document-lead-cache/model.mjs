// PROTOTYPE — throwaway model of the proposed Document-lead graph lifecycle.

function cloneState(state) {
  return {
    ...state,
    documents: state.documents.map((document) => ({ ...document })),
    cache: new Map(
      [...state.cache].map(([id, entry]) => [id, { ...entry, lead: { ...entry.lead } }]),
    ),
    mountedRows: new Set(state.mountedRows),
    counters: { ...state.counters },
  };
}

function extractLead(source) {
  const lines = source.split(/\r\n|\r|\n/).filter((line) => line.trim() !== "");
  return {
    primary: lines[0] ?? "(empty)",
    description: lines.slice(1).join(" / "),
  };
}

function pullPureCache(state) {
  const liveIds = new Set(
    state.documents.filter((document) => document.inRecent).map((document) => document.id),
  );
  const changedIds = [];

  for (const id of state.cache.keys()) {
    if (!liveIds.has(id)) {
      state.cache.delete(id);
      state.counters.pureDisposals += 1;
    }
  }

  for (const document of state.documents) {
    if (!document.inRecent || document.leadRevision === null) continue;
    const cached = state.cache.get(document.id);
    if (cached?.revision === document.leadRevision) continue;

    state.cache.set(document.id, {
      revision: document.leadRevision,
      lead: extractLead(document.leadSource),
    });
    state.counters.extractions += 1;
    changedIds.push(document.id);
  }

  return changedIds;
}

function show(state) {
  if (state.visible) return state;

  state.visible = true;
  const changedIds = new Set(pullPureCache(state));
  const ids = state.documents
    .filter((document) => document.inRecent)
    .map((document) => document.id);
  state.mountedRows = new Set(ids);
  state.counters.rowBuilds += ids.length;
  state.lastObservation = changedIds.size === 0
    ? "Reopened with cached leads; only visible rows were rebuilt."
    : `Opened and extracted: ${[...changedIds].join(", ")}.`;
  return state;
}

function hide(state, reason = "Closed") {
  if (!state.visible) return state;

  state.visible = false;
  state.counters.rowDisposals += state.mountedRows.size;
  state.mountedRows.clear();
  state.lastObservation = `${reason}; visible row scopes were disposed.`;
  return state;
}

export function initialState(viewport = "narrow") {
  const state = {
    viewport,
    visible: false,
    selectedId: "A",
    nextRevision: 3,
    documents: [
      {
        id: "A",
        text: "# Alpha\nFirst document",
        currentRevision: 1,
        leadSource: "# Alpha\nFirst document",
        leadRevision: 1,
        inRecent: true,
      },
      {
        id: "B",
        text: "- [ ] Beta task",
        currentRevision: 2,
        leadSource: "- [ ] Beta task",
        leadRevision: 2,
        inRecent: true,
      },
    ],
    cache: new Map(),
    mountedRows: new Set(),
    counters: {
      extractions: 0,
      pureDisposals: 0,
      rowBuilds: 0,
      rowDisposals: 0,
    },
    lastObservation: "Narrow startup is hidden; no lead has been extracted.",
  };

  if (viewport === "wide") {
    show(state);
    state.lastObservation = "Wide startup is visible; initial leads were demanded.";
  }
  return state;
}

export function reduce(previous, action) {
  const state = cloneState(previous);
  state.lastObservation = "No state change.";

  switch (action.type) {
    case "open":
      return show(state);
    case "close":
      return hide(state);
    case "toggle":
      return state.visible ? hide(state) : show(state);
    case "resize":
      state.viewport = state.viewport === "wide" ? "narrow" : "wide";
      state.lastObservation = `Viewport is now ${state.viewport}; visibility was preserved.`;
      return state;
    case "select": {
      if (!state.documents.some((document) => document.id === action.id)) {
        state.lastObservation = `Document ${action.id} does not exist.`;
        return state;
      }
      state.selectedId = action.id;
      if (state.viewport === "narrow") {
        return hide(state, `Selected ${action.id} on narrow viewport`);
      }
      state.lastObservation = `Selected ${action.id}; wide pane stayed visible.`;
      return state;
    }
    case "add": {
      if (state.documents.some((document) => document.id === action.id)) {
        state.lastObservation = `Document ${action.id} already exists.`;
        return state;
      }
      state.documents.push({
        id: action.id,
        text: "",
        currentRevision: state.nextRevision++,
        leadSource: "",
        leadRevision: null,
        inRecent: false,
      });
      state.selectedId = action.id;
      state.lastObservation = `Added empty ${action.id}; it enters Recent documents on first input.`;
      return state;
    }
    case "edit": {
      const document = state.documents.find((item) => item.id === action.id);
      if (!document) {
        state.lastObservation = `Document ${action.id} does not exist.`;
        return state;
      }
      document.text = action.text;
      document.currentRevision = state.nextRevision++;
      if (!document.inRecent) {
        document.inRecent = true;
        document.leadSource = document.text;
        document.leadRevision = document.currentRevision;
        if (state.visible) {
          const changed = pullPureCache(state);
          state.mountedRows.add(document.id);
          state.counters.rowBuilds += 1;
          state.lastObservation = `First input seeded and extracted ${changed.join(", ")}.`;
        } else {
          state.lastObservation = `First input seeded ${document.id}; extraction remains lazy.`;
        }
      } else {
        state.lastObservation = `Edited ${document.id}; its previous quiet lead remains current.`;
      }
      return state;
    }
    case "quiet": {
      const document = state.documents.find((item) => item.id === action.id);
      if (!document || !document.inRecent) {
        state.lastObservation = `No Recent-document source exists for ${action.id}.`;
        return state;
      }
      document.leadSource = document.text;
      document.leadRevision = document.currentRevision;
      if (!state.visible) {
        state.lastObservation = `Accepted quiet source for ${document.id}; cache is dirty but unpulled.`;
        return state;
      }
      const changed = pullPureCache(state);
      state.counters.rowBuilds += changed.length;
      state.lastObservation = changed.length === 0
        ? `Quiet source for ${document.id} already matched the cache.`
        : `Extracted and rebuilt only: ${changed.join(", ")}.`;
      return state;
    }
    case "delete": {
      const existed = state.documents.some((document) => document.id === action.id);
      state.documents = state.documents.filter((document) => document.id !== action.id);
      if (!existed) {
        state.lastObservation = `Document ${action.id} does not exist.`;
        return state;
      }
      if (state.selectedId === action.id) {
        state.selectedId = state.documents[0]?.id ?? null;
      }
      if (!state.visible) {
        state.lastObservation = `Deleted ${action.id}; hidden pure cache remains until next demand.`;
        return state;
      }
      if (state.mountedRows.delete(action.id)) state.counters.rowDisposals += 1;
      pullPureCache(state);
      state.lastObservation = `Deleted ${action.id}; visible and pure scopes were reconciled.`;
      return state;
    }
    default:
      state.lastObservation = `Unknown action: ${action.type}.`;
      return state;
  }
}
