import { createJourneyState, transitionJourney } from './genui-journey-state.js';

const responses = [
  {
    id: 'early',
    name: 'Leave earlier',
    arrival: '16:05 today',
    cost: '¥0',
    change: 'Depart 1h 18m earlier',
    signal: 'Expected to run normally',
    tone: 'recommended',
    detail: 'Moves the rail and ferry connection earlier. Check-in and tomorrow’s museum reservation remain unchanged.',
    preview: [
      'Kyoto Station · 12:52',
      'Uno Port · 16:05',
      'Naoshima check-in · 17:20',
      'Chichu Art Museum · tomorrow 10:30',
    ],
  },
  {
    id: 'overnight',
    name: 'Stay in Okayama',
    arrival: '09:05 tomorrow',
    cost: '+ ¥12,400',
    change: 'Add an overnight stay',
    signal: 'Avoids today’s ferry risk',
    tone: 'neutral',
    detail: 'Keeps your afternoon in Kyoto, adds a hotel in Okayama, and uses the first ferry tomorrow morning.',
    preview: [
      'Kyoto Station · 14:10',
      'Okayama overnight · 18:00',
      'Uno Port · tomorrow 08:22',
      'Chichu Art Museum · tomorrow 10:30',
    ],
  },
  {
    id: 'wait',
    name: 'Keep current plan',
    arrival: '18:20 today',
    cost: '¥0',
    change: 'No itinerary change',
    signal: '17:20 ferry may be cancelled',
    tone: 'risk',
    detail: 'Makes no change now. You may need to find accommodation near Uno if the 17:20 ferry is cancelled.',
    preview: [
      'Kyoto Station · 14:10',
      'Uno Port · 17:05',
      'Naoshima check-in · 18:20',
      'Chichu Art Museum · tomorrow 10:30',
    ],
  },
];

const itineraryList = document.querySelector('#itinerary-list');
const responseList = document.querySelector('#response-list');
const selectionDetail = document.querySelector('#selection-detail');
const revisionLabel = document.querySelector('#revision-label');
const planStatus = document.querySelector('#plan-status');
const applyButton = document.querySelector('#apply-button');
const clearSelectionButton = document.querySelector('#clear-selection-button');
const undoButton = document.querySelector('#undo-button');
const toast = document.querySelector('#toast');

let state = createJourneyState();
let toastTimer;
let focusedResponseId = responses[0]?.id ?? null;

const itineraryRows = [];
const responseRows = [];

function selectedResponse() {
  return responses.find((response) => response.id === state.selectedOption) ?? null;
}

function splitStopText(stopText) {
  const dividerIndex = stopText.indexOf(' · ');
  if (dividerIndex === -1) {
    return { place: stopText, time: '' };
  }

  return {
    place: stopText.slice(0, dividerIndex),
    time: stopText.slice(dividerIndex + 3),
  };
}

function isProtectedStop(place) {
  return place === 'Chichu Art Museum';
}

function createItineraryRow(index) {
  const row = document.createElement('li');
  row.className = 'itinerary-stop';
  row.dataset.index = String(index);

  const marker = document.createElement('span');
  marker.className = 'stop-marker';
  marker.setAttribute('aria-hidden', 'true');

  const currentStop = document.createElement('div');
  currentStop.className = 'stop-version current-stop';
  currentStop.setAttribute('role', 'group');
  currentStop.setAttribute('aria-label', 'Current stop');
  const currentLabel = document.createElement('span');
  currentLabel.className = 'stop-version-label';
  currentLabel.textContent = 'Current';
  currentLabel.hidden = true;
  const label = document.createElement('strong');
  const placeText = document.createTextNode('');
  const protectedBadge = document.createElement('span');
  protectedBadge.className = 'protected-badge';
  protectedBadge.textContent = 'Protected';
  protectedBadge.hidden = true;
  const timeText = document.createTextNode('');
  const timeNode = document.createElement('span');
  timeNode.append(timeText);
  label.append(placeText, protectedBadge);
  currentStop.append(currentLabel, label, timeNode);

  const proposedStop = document.createElement('div');
  proposedStop.className = 'stop-version proposed-stop';
  proposedStop.setAttribute('role', 'group');
  proposedStop.setAttribute('aria-label', 'Proposed stop');
  proposedStop.hidden = true;
  const proposedLabel = document.createElement('span');
  proposedLabel.className = 'stop-version-label';
  proposedLabel.textContent = 'Proposed';
  const proposedPlace = document.createElement('strong');
  const proposedPlaceText = document.createTextNode('');
  proposedPlace.append(proposedPlaceText);
  const proposedTimeText = document.createTextNode('');
  const proposedTimeNode = document.createElement('span');
  proposedTimeNode.append(proposedTimeText);
  proposedStop.append(proposedLabel, proposedPlace, proposedTimeNode);

  const changeNote = document.createElement('span');
  changeNote.className = 'change-note';
  changeNote.hidden = true;

  row.append(marker, currentStop, proposedStop, changeNote);

  return {
    index,
    row,
    currentLabel,
    placeText,
    timeText,
    protectedBadge,
    proposedStop,
    proposedPlaceText,
    proposedTimeText,
    changeNote,
  };
}

function createResponseRow(response) {
  const row = document.createElement('button');
  row.type = 'button';
  row.className = `response-row ${response.tone}`;
  row.role = 'radio';
  row.dataset.response = response.id;

  const radioMark = document.createElement('span');
  radioMark.className = 'radio-mark';
  radioMark.setAttribute('aria-hidden', 'true');

  const nameCol = document.createElement('span');
  nameCol.className = 'response-name';
  const name = document.createElement('strong');
  name.textContent = response.name;
  const signal = document.createElement('small');
  signal.textContent = response.signal;
  nameCol.append(name, signal);

  const arrivalCol = document.createElement('span');
  arrivalCol.className = 'metric';
  const arrivalLabel = document.createElement('small');
  arrivalLabel.textContent = 'Arrival';
  const arrivalValue = document.createElement('strong');
  arrivalValue.textContent = response.arrival;
  arrivalCol.append(arrivalLabel, arrivalValue);

  const costCol = document.createElement('span');
  costCol.className = 'metric';
  const costLabel = document.createElement('small');
  costLabel.textContent = 'Cost';
  const costValue = document.createElement('strong');
  costValue.textContent = response.cost;
  costCol.append(costLabel, costValue);

  const changeCol = document.createElement('span');
  changeCol.className = 'response-change';
  const changeLabel = document.createElement('small');
  changeLabel.textContent = 'What changes';
  const changeValue = document.createElement('strong');
  changeValue.textContent = response.change;
  changeCol.append(changeLabel, changeValue);

  row.append(radioMark, nameCol, arrivalCol, costCol, changeCol);

  return { id: response.id, row };
}

function initializeRows() {
  if (itineraryRows.length === 0) {
    state.plan.items.forEach((_item, index) => {
      const view = createItineraryRow(index);
      itineraryRows[index] = view;
      itineraryList?.appendChild(view.row);
    });
  }

  if (responseRows.length === 0) {
    responses.forEach((response) => {
      const view = createResponseRow(response);
      responseRows.push(view);
      responseList?.appendChild(view.row);
    });
  }
}

function getResponseRow(responseId) {
  return responseRows.find((response) => response.id === responseId)?.row ?? null;
}


function focusResponse(responseId) {
  getResponseRow(responseId)?.focus();
}

function renderItinerary() {
  const selected = selectedResponse();

  for (let index = 0; index < itineraryRows.length; index++) {
    const row = itineraryRows[index];
    const currentStop = state.plan.items[index] ?? '';
    const proposedStop = selected?.preview[index] ?? currentStop;
    const isPreviewing = selected !== null;
    const wasChanged = isPreviewing && proposedStop !== currentStop;

    const { place: currentPlace, time: currentTime } = splitStopText(currentStop);
    const { place: proposedPlace, time: proposedTime } = splitStopText(proposedStop);

    row.placeText.data = currentPlace;
    row.timeText.data = currentTime;
    row.protectedBadge.hidden = !isProtectedStop(currentPlace);
    row.currentLabel.hidden = !wasChanged;
    row.proposedStop.hidden = !wasChanged;
    row.proposedPlaceText.data = proposedPlace;
    row.proposedTimeText.data = proposedTime;
    row.row.classList.toggle('proposed', wasChanged);

    row.changeNote.hidden = !isPreviewing;
    row.changeNote.textContent = wasChanged ? 'Replaces current stop' : 'Unchanged in preview';
  }
}

function renderResponses() {
  for (const response of responseRows) {
    const isChecked = response.id === state.selectedOption;
    response.row.setAttribute('aria-checked', String(isChecked));
    response.row.tabIndex = response.id === focusedResponseId ? 0 : -1;
  }
}

function renderDetail() {
  selectionDetail.textContent = '';
  const response = selectedResponse();

  if (response === null) {
    const emptyMessage = document.createElement('p');
    emptyMessage.textContent = 'Select a response to see exactly what would change in your itinerary.';
    selectionDetail.append(emptyMessage);
    applyButton.disabled = true;
    applyButton.textContent = 'Apply to itinerary';
    clearSelectionButton.disabled = true;
    return;
  }

  const header = document.createElement('div');
  const detailLabel = document.createElement('span');
  detailLabel.className = 'detail-label';
  detailLabel.textContent = 'Previewing';
  const detailName = document.createElement('strong');
  detailName.textContent = response.name;

  const detailText = document.createElement('p');
  detailText.textContent = response.detail;

  header.append(detailLabel, detailName);
  selectionDetail.append(header, detailText);

  applyButton.disabled = false;
  clearSelectionButton.disabled = false;
  applyButton.textContent = response.id === 'wait' ? 'Keep current itinerary' : 'Apply to itinerary';
}

function render() {
  revisionLabel.textContent = `Revision ${state.revision}`;
  planStatus.textContent =
    state.plan.status === 'updated'
      ? 'Updated · booking unchanged'
      : state.plan.status === 'restored'
        ? 'Previous plan restored'
        : 'Needs attention';
  planStatus.className = `plan-status ${state.plan.status}`;
  undoButton.disabled = state.previousPlan === null;

  renderItinerary();
  renderResponses();
  renderDetail();
}

function showToast(message) {
  window.clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add('visible');
  toastTimer = window.setTimeout(() => toast.classList.remove('visible'), 2800);
}

function selectResponse(responseId, focus = false) {
  state = transitionJourney(state, { type: 'select_option', option: responseId });
  focusedResponseId = responseId;
  render();
  if (focus) {
    focusResponse(responseId);
  }
}

function renderAll() {
  initializeRows();
  render();
}

responseList.addEventListener('click', (event) => {
  const response = event.target.closest('[data-response]');
  if (response === null) return;
  selectResponse(response.dataset.response, true);
});

responseList.addEventListener('keydown', (event) => {
  const response = event.target.closest('[data-response]');
  if (response === null) return;

  const currentIndex = responses.findIndex((item) => item.id === response.dataset.response);
  let nextIndex;

  switch (event.key) {
    case 'ArrowDown':
    case 'ArrowRight':
      nextIndex = (currentIndex + 1) % responses.length;
      break;
    case 'ArrowUp':
    case 'ArrowLeft':
      nextIndex = (currentIndex - 1 + responses.length) % responses.length;
      break;
    case 'Home':
      nextIndex = 0;
      break;
    case 'End':
      nextIndex = responses.length - 1;
      break;
    default:
      return;
  }

  event.preventDefault();
  const targetId = responses[nextIndex].id;
  focusedResponseId = targetId;
  selectResponse(targetId, true);
});

applyButton.addEventListener('click', () => {
  if (state.selectedOption === null) return;
  const chosen = selectedResponse();
  const previousFocus = focusedResponseId;
  state = transitionJourney(state, { type: 'apply_option' });
  render();
  if (previousFocus !== null) {
    focusResponse(previousFocus);
  }
  showToast(`${chosen.name} applied to the itinerary. No booking was changed.`);
});

clearSelectionButton.addEventListener('click', () => {
  if (state.selectedOption === null) return;
  const previousFocus = focusedResponseId;
  state = transitionJourney(state, { type: 'select_option', option: null });
  render();
  if (previousFocus !== null) {
    focusResponse(previousFocus);
  }
  showToast('Selection cleared. Current itinerary unchanged.');
});

undoButton.addEventListener('click', () => {
  const previousFocus = focusedResponseId;
  state = transitionJourney(state, { type: 'undo' });
  render();
  if (previousFocus !== null) {
    focusResponse(previousFocus);
  }
  showToast('Previous itinerary restored as a new revision.');
});

renderAll();
