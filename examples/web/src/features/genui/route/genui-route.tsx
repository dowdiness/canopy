import genuiDocument from '../../../../genui.html?raw';
import genuiStyles from './styles.css?inline';
import { GenuiClient } from './genui-client';

const GENUI_SHELL_PATTERN = /<!-- genui-shell:start -->([\s\S]*?)<!-- genui-shell:end -->/;

export function GenuiRoute() {
  const shellMatch = GENUI_SHELL_PATTERN.exec(genuiDocument);
  if (shellMatch === null) {
    throw new Error('The canonical GenUI document shell is unavailable');
  }

  return (
    <GenuiClient>
      <style data-genui-route-styles>{genuiStyles}</style>
      <div dangerouslySetInnerHTML={{ __html: shellMatch[1] }} />
    </GenuiClient>
  );
}
