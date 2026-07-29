import { useEffect, useRef } from 'react';

export function useConversationSelectionScroll(
  isConversationVisible: boolean,
  selectedEntryId: string,
) {
  const conversationPanelRef = useRef<HTMLElement | null>(null);
  const selectedConversationRef = useRef<HTMLLIElement | null>(null);
  const revealConversationSelectionRef = useRef(false);
  const focusConversationSelectionRef = useRef(false);

  useEffect(() => {
    if (!isConversationVisible) return;
    const frame = window.requestAnimationFrame(() => {
      const panel = conversationPanelRef.current;
      const target = selectedConversationRef.current;
      if (panel === null || target === null) {
        revealConversationSelectionRef.current = false;
        focusConversationSelectionRef.current = false;
        return;
      }
      const usesInternalScroll = window.getComputedStyle(panel).overflowY !== 'visible';
      if (usesInternalScroll) {
        const panelBox = panel.getBoundingClientRect();
        const targetBox = target.getBoundingClientRect();
        const headingHeight = panel.querySelector<HTMLElement>('.pilot-panel-heading')
          ?.getBoundingClientRect().height ?? 0;
        panel.scrollTo({
          top: Math.max(
            0,
            panel.scrollTop + targetBox.top - panelBox.top - headingHeight - 4,
          ),
          behavior: 'auto',
        });
      } else if (revealConversationSelectionRef.current) {
        target.scrollIntoView({ block: 'center', behavior: 'auto' });
      }
      if (focusConversationSelectionRef.current) {
        target.focus({ preventScroll: true });
      }
      revealConversationSelectionRef.current = false;
      focusConversationSelectionRef.current = false;
    });
    return () => window.cancelAnimationFrame(frame);
  }, [isConversationVisible, selectedEntryId]);

  const revealConversationSelection = (): void => {
    revealConversationSelectionRef.current = true;
  };

  const focusConversationSelection = (): void => {
    focusConversationSelectionRef.current = true;
  };

  return {
    conversationPanelRef,
    revealConversationSelection,
    focusConversationSelection,
    selectedConversationRef,
  };
}
