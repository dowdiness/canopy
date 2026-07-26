import jsonDocument from '../../../../json.html?raw';
import { JsonClient } from './json-client';

const shellMatch = jsonDocument.match(
  /<body[^>]*>([\s\S]*?)\s*<script type="module" src="\/src\/entries\/json\.ts"><\/script>\s*<\/body>/,
);
if (shellMatch === null) {
  throw new Error('The canonical JSON document shell is unavailable');
}
const jsonShellMarkup = shellMatch[1];

export function JsonRoute() {
  return (
    <JsonClient>
      <div dangerouslySetInnerHTML={{ __html: jsonShellMarkup }} />
    </JsonClient>
  );
}
