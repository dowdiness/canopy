import { createMemoApp } from './app';
import { createMemoView } from './view';

export function mountMemo(): void {
  createMemoApp(createMemoView(document)).mount();
}
