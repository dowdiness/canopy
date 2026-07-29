import fixtureSource from '../../../../tests/fixtures/pi-session-v3.jsonl?raw';
import {
  parsePiSessionJsonl,
  reducePiSession,
} from '../core/session';
import {
  createResumeReducer,
  createResumeState,
  reducePilotViewState,
  initialPilotViewState,
  type ImportStatus,
  type PilotSourceSelection,
  type PilotViewEvent,
  type PilotViewState,
  type ResumeEvent,
  type ResumeState,
} from './resume-reducer';

export type {
  ImportStatus,
  PilotSourceSelection,
  PilotViewEvent,
  PilotViewState,
  ResumeEvent,
  ResumeState,
};

const demoSession = reducePiSession(parsePiSessionJsonl(fixtureSource));
const demoBaseline = createResumeState(demoSession);

export const initialResumeState: ResumeState = demoBaseline;
export const reduceResumeState = createResumeReducer(demoBaseline);

export {
  initialPilotViewState,
  reducePilotViewState,
};
