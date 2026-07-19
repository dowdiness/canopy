const CURRENT_PLAN_ITEMS = [
  'Kyoto Station · 14:10',
  'Uno Port · 17:05',
  'Naoshima check-in · 18:20',
  'Chichu Art Museum · tomorrow 10:30',
];

const OPTION_PLAN_ITEMS = {
  early: [
    'Kyoto Station · 12:52',
    'Uno Port · 16:05',
    'Naoshima check-in · 17:20',
    'Chichu Art Museum · tomorrow 10:30',
  ],
  overnight: [
    'Kyoto Station · 14:10',
    'Okayama overnight · 18:00',
    'Uno Port · tomorrow 08:22',
    'Chichu Art Museum · tomorrow 10:30',
  ],
  wait: [...CURRENT_PLAN_ITEMS],
};

export function createJourneyState() {
  return {
    phase: 'comparison',
    planId: 'naoshima-journey',
    revision: 3,
    selectedOption: null,
    previousPlan: null,
    plan: {
      status: 'at-risk',
      items: [...CURRENT_PLAN_ITEMS],
    },
  };
}

export function transitionJourney(state, event) {
  switch (event.type) {
    case 'select_option':
      return { ...state, selectedOption: event.option };
    case 'apply_option': {
      if (state.selectedOption === null) return state;
      return {
        ...state,
        revision: state.revision + 1,
        selectedOption: null,
        previousPlan: state.plan,
        plan: {
          status: 'updated',
          items: [...OPTION_PLAN_ITEMS[state.selectedOption]],
        },
      };
    }
    case 'undo': {
      if (state.previousPlan === null) return state;
      return {
        ...state,
        revision: state.revision + 1,
        plan: { ...state.previousPlan, status: 'restored' },
        previousPlan: null,
      };
    }
    default:
      return state;
  }
}
