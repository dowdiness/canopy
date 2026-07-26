import journeyDocument from '../../../../genui-possibilities.html?raw';
import { JourneyClient } from './journey-client';

const shellMatch = journeyDocument.match(
  /<body[^>]*>([\s\S]*?)\s*<script type="module" src="\/src\/entries\/genui-possibilities\.js"><\/script>\s*<\/body>/,
);
if (shellMatch === null) {
  throw new Error('The canonical Journey document shell is unavailable');
}
const journeyShellMarkup = shellMatch[1];

export function JourneyRoute() {
  return (
    <JourneyClient>
      <div dangerouslySetInnerHTML={{ __html: journeyShellMarkup }} />
    </JourneyClient>
  );
}
