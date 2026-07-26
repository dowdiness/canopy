import postsDocument from '../../../../posts.html?raw';
import { PostsClient } from './posts-client';

const shellMatch = postsDocument.match(
  /<body[^>]*>([\s\S]*?)\s*<script type="module" src="\/src\/entries\/posts\.ts"><\/script>\s*<\/body>/,
);
if (shellMatch === null) {
  throw new Error('The canonical Posts document shell is unavailable');
}
const postsShellMarkup = shellMatch[1];

export function PostsRoute() {
  return (
    <PostsClient>
      <div dangerouslySetInnerHTML={{ __html: postsShellMarkup }} />
    </PostsClient>
  );
}
