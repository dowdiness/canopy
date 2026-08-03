import assert from 'node:assert/strict';
import test from 'node:test';

import { createJourneyState, transitionJourney } from './journey-state.js';

test('starts with a persistent itinerary under one active disruption', () => {
  const state = createJourneyState();

  assert.equal(state.phase, 'comparison');
  assert.equal(state.planId, 'naoshima-journey');
  assert.equal(state.revision, 3);
  assert.deepEqual(state.plan.items, [
    'Kyoto Station · 14:10',
    'Uno Port · 17:05',
    'Naoshima check-in · 18:20',
    'Chichu Art Museum · tomorrow 10:30',
  ]);
  assert.equal(state.selectedOption, null);
});

test('selecting a response previews it without mutating the itinerary', () => {
  const initial = createJourneyState();
  const selected = transitionJourney(initial, { type: 'select_option', option: 'early' });

  assert.equal(selected.selectedOption, 'early');
  assert.deepEqual(selected.plan, initial.plan);
  assert.equal(selected.revision, initial.revision);
});

test('selecting no response dismisses the preview without mutating the itinerary', () => {
  const initial = createJourneyState();
  const selected = transitionJourney(initial, { type: 'select_option', option: 'early' });
  const dismissed = transitionJourney(selected, { type: 'select_option', option: null });

  assert.equal(dismissed.selectedOption, null);
  assert.deepEqual(dismissed.plan, initial.plan);
  assert.equal(dismissed.revision, initial.revision);
});

test('applying with no selected response is a no-op', () => {
  const initial = createJourneyState();
  const applied = transitionJourney(initial, { type: 'apply_option' });

  assert.equal(applied.selectedOption, null);
  assert.equal(applied.previousPlan, null);
  assert.equal(applied.revision, initial.revision);
  assert.strictEqual(applied, initial);
});

test('undo with no previous itinerary is a no-op', () => {
  const initial = createJourneyState();
  const undone = transitionJourney(initial, { type: 'undo' });

  assert.equal(undone.selectedOption, null);
  assert.equal(undone.previousPlan, null);
  assert.equal(undone.revision, initial.revision);
  assert.strictEqual(undone, initial);
});
test('every response preserves the protected stop through apply and undo', () => {
  const protectedStop = 'Chichu Art Museum · tomorrow 10:30';

  for (const option of ['early', 'overnight', 'wait']) {
    const initial = createJourneyState();
    const selected = transitionJourney(initial, { type: 'select_option', option });
    const applied = transitionJourney(selected, { type: 'apply_option' });
    const undone = transitionJourney(applied, { type: 'undo' });

    assert.equal(applied.plan.items.length, initial.plan.items.length);
    assert.equal(applied.plan.items[3], protectedStop);
    assert.equal(undone.plan.items.length, initial.plan.items.length);
    assert.equal(undone.plan.items[3], protectedStop);
  }
});


test('applying a response updates the same itinerary and records its previous revision', () => {
  const initial = createJourneyState();
  const selected = transitionJourney(initial, { type: 'select_option', option: 'early' });
  const applied = transitionJourney(selected, { type: 'apply_option' });

  assert.equal(applied.planId, initial.planId);
  assert.equal(applied.revision, 4);
  assert.equal(applied.plan.status, 'updated');
  assert.equal(applied.plan.items[0], 'Kyoto Station · 12:52');
  assert.deepEqual(applied.previousPlan, initial.plan);
  assert.equal(applied.selectedOption, null);
});

test('undo restores the previous itinerary as a new revision', () => {
  const initial = createJourneyState();
  const applied = transitionJourney(
    transitionJourney(initial, { type: 'select_option', option: 'early' }),
    { type: 'apply_option' },
  );
  const undone = transitionJourney(applied, { type: 'undo' });

  assert.equal(undone.planId, initial.planId);
  assert.equal(undone.revision, 5);
  assert.deepEqual(undone.plan.items, initial.plan.items);
  assert.equal(undone.plan.status, 'restored');
  assert.equal(undone.previousPlan, null);
});
