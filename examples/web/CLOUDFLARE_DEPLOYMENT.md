# Cloudflare Deployment Guide

This guide explains how to deploy the CRDT signaling server to Cloudflare Workers with Durable Objects.

## Architecture Overview

The deployment uses:
- **Cloudflare Workers** - Edge compute platform for serverless JavaScript
- **Durable Objects** - Stateful objects for managing WebSocket connections
- **WebSockets** - Real-time bidirectional communication for signaling

## Prerequisites

1. **Cloudflare Account** - Sign up at https://dash.cloudflare.com/sign-up
2. **Wrangler CLI** - Cloudflare's command-line tool
3. **Node.js** - Version 16 or higher

## Step 1: Install Wrangler

If you haven't already installed Wrangler:

```bash
npm install -g wrangler
```

Or install locally in your project:

```bash
cd examples/web
npm install -D wrangler
```

## Step 2: Authenticate with Cloudflare

Log in to your Cloudflare account:

```bash
wrangler login
```

This will open a browser window for authentication.

## Step 3: Deploy the Signaling Server

From the `examples/web/` directory:

```bash
# Deploy the signaling server
wrangler deploy --config wrangler-signaling.toml

# Expected output:
# Total Upload: XX.XX KiB / gzip: XX.XX KiB
# Uploaded crdt-signaling-server (X.XX sec)
# Published crdt-signaling-server (X.XX sec)
#   https://crdt-signaling-server.<your-subdomain>.workers.dev
```

**Important**: Copy the deployed URL - you'll need it for the client configuration.

## Step 4: Test the Deployment

You can test the WebSocket connection using a simple script:

```javascript
const ws = new WebSocket('wss://crdt-signaling-server.<your-subdomain>.workers.dev');

ws.onopen = () => {
  console.log('Connected!');
  ws.send(JSON.stringify({ type: 'join', agentId: 'test-client' }));
};

ws.onmessage = (event) => {
  console.log('Received:', event.data);
};
```

## Step 5: Update Client Code

Update your application to use the Cloudflare Workers URL instead of `localhost:8080`.

### Option A: Environment Variable

Create a `.env` file in the `examples/web/` directory:

```bash
VITE_SIGNALING_URL=wss://crdt-signaling-server.<your-subdomain>.workers.dev
```

Then in your code:

```typescript
const wsUrl = import.meta.env.VITE_SIGNALING_URL || 'ws://localhost:8080';
await networkSync.connect(wsUrl);
```

### Option B: Auto-detect

Automatically use Cloudflare in production:

```typescript
const wsUrl = window.location.hostname === 'localhost'
  ? 'ws://localhost:8080'
  : 'wss://crdt-signaling-server.<your-subdomain>.workers.dev';

await networkSync.connect(wsUrl);
```

## Monitoring and Debugging

### View Logs

Stream real-time logs from your Worker:

```bash
wrangler tail --config wrangler-signaling.toml
```

### Check Deployment Status

```bash
wrangler deployments list --config wrangler-signaling.toml
```

### View Metrics

Visit the Cloudflare Dashboard:
1. Go to https://dash.cloudflare.com
2. Navigate to Workers & Pages
3. Click on "crdt-signaling-server"
4. View metrics: requests, errors, CPU time, etc.

## Pricing

Cloudflare Workers pricing (as of 2024):

### Free Tier
- 100,000 requests/day
- 10ms CPU time per request
- Includes Durable Objects:
  - 1 million requests/month
  - 400,000 GB-seconds/month

### Paid Plan ($5/month)
- 10 million requests/month
- 30 million Durable Object requests/month
- Additional requests: $0.50 per million

**For most collaborative editing use cases, the free tier is sufficient.**

## Custom Domain (Optional)

To use a custom domain like `signaling.yourdomain.com`:

1. Add your domain to Cloudflare
2. Update `wrangler-signaling.toml`:

```toml
routes = [
  { pattern = "signaling.yourdomain.com", custom_domain = true }
]
```

3. Redeploy:

```bash
wrangler deploy --config wrangler-signaling.toml
```

## Troubleshooting

### WebSocket Connection Fails

**Check CORS**: The worker includes CORS headers, but if you're still having issues:

```javascript
// In signaling-worker.js, update the fetch handler:
headers: {
  'Access-Control-Allow-Origin': 'https://yourdomain.com',
  // ...
}
```

### "Durable Object not found" Error

This usually means the migration hasn't run. Try:

```bash
wrangler delete --config wrangler-signaling.toml
wrangler deploy --config wrangler-signaling.toml
```

### High Latency

Durable Objects are automatically placed in the optimal region. However, you can specify a location hint:

```javascript
// Instead of idFromName
const id = env.SIGNALING_ROOM.idFromName('global-room');

// Use jurisdiction (if needed for compliance)
const id = env.SIGNALING_ROOM.newUniqueId({ jurisdiction: 'eu' });
```

## Development Workflow

### Local Development with Wrangler

```bash
# Start local development server
wrangler dev --config wrangler-signaling.toml --local

# This starts a local server on http://localhost:8787
# Update your client to connect to ws://localhost:8787
```

### Testing Changes

1. Make changes to `signaling-worker.js`
2. Test locally with `wrangler dev`
3. Deploy to production with `wrangler deploy`

## Rollback

If you need to rollback to a previous version:

```bash
# List deployments
wrangler deployments list --config wrangler-signaling.toml

# Rollback to specific deployment
wrangler rollback <deployment-id> --config wrangler-signaling.toml
```

## Security Considerations

### Rate Limiting

Add rate limiting to prevent abuse:

```javascript
// In SignalingRoom class
async fetch(request) {
  const ip = request.headers.get('CF-Connecting-IP');

  // Implement rate limiting logic here
  // See: https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/

  // ... rest of code
}
```

### Authentication (Optional)

For private collaboration sessions, add authentication:

```javascript
async fetch(request) {
  const authToken = request.headers.get('Authorization');

  // Validate token
  if (!isValidToken(authToken)) {
    return new Response('Unauthorized', { status: 401 });
  }

  // ... rest of code
}
```

## Multi-Region Considerations

Cloudflare automatically routes requests to the nearest data center. However, Durable Objects are single-instance per room, which means:

- All peers in the same room connect to the same Durable Object instance
- Cross-region latency may occur for geographically distributed teams
- For global teams, consider implementing regional rooms:

```javascript
// Use region-specific room names
const region = getRegionFromRequest(request);
const id = env.SIGNALING_ROOM.idFromName(`room-${region}`);
```

## Next Steps

1. **Deploy the static site**: Use the existing `wrangler.jsonc` for Cloudflare Pages
2. **Set up monitoring**: Configure alerts in Cloudflare Dashboard
3. **Optimize performance**: Review metrics and adjust as needed
4. **Add analytics**: Track collaboration sessions and peer connections

## Resources

- [Cloudflare Workers Documentation](https://developers.cloudflare.com/workers/)
- [Durable Objects Guide](https://developers.cloudflare.com/durable-objects/)
- [WebSocket API](https://developers.cloudflare.com/workers/runtime-apis/websockets/)
- [Wrangler CLI Reference](https://developers.cloudflare.com/workers/wrangler/)
