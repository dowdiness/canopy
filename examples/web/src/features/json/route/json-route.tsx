import jsonDocument from '../../../../json.html?raw';
import { JsonClient } from './json-client';

const JSON_SHELL_PATTERN = /<!-- json-shell:start -->([\s\S]*?)<!-- json-shell:end -->/;

export function JsonRoute() {
  const shellMatch = JSON_SHELL_PATTERN.exec(jsonDocument);
  if (shellMatch === null) {
    throw new Error('The canonical JSON document shell is unavailable');
  }

  return (
    <JsonClient>
      <div dangerouslySetInnerHTML={{ __html: shellMatch[1] }} />
    </JsonClient>
  );
}
