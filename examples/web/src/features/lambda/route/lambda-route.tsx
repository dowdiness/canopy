import lambdaDocument from '../../../../index.html?raw';
import { LambdaClient } from './lambda-client';

const LAMBDA_SHELL_PATTERN = /<!-- lambda-shell:start -->([\s\S]*?)<!-- lambda-shell:end -->/;

export function LambdaRoute() {
  const shellMatch = LAMBDA_SHELL_PATTERN.exec(lambdaDocument);
  if (shellMatch === null) {
    throw new Error('The canonical Mini-ML document shell is unavailable');
  }

  return (
    <LambdaClient>
      <div dangerouslySetInnerHTML={{ __html: shellMatch[1] }} />
    </LambdaClient>
  );
}
