# Quick Start: Deploy to Cloudflare

This guide gets you up and running with Cloudflare Workers in 5 minutes.

## Prerequisites

- Cloudflare account (free tier works!)
- Node.js 16+ installed

## 1. Install & Login (1 minute)

```bash
# Install Wrangler globally
npm install -g wrangler

# Or use the local version
cd examples/web
npm install -D wrangler

# Login to Cloudflare
wrangler login
```

## 2. Deploy Signaling Server (1 minute)

```bash
cd examples/web

# Deploy the WebSocket signaling server
wrangler deploy --config wrangler-signaling.toml
```

**Output:**
```
✨ Published crdt-signaling-server (X.XX sec)
  https://crdt-signaling-server.YOUR-SUBDOMAIN.workers.dev
```

**⚠️ Copy this URL!** You'll need it in the next step.

## 3. Configure Client (30 seconds)

### Option A: Edit main.ts directly

Open `examples/web/src/main.ts` and replace line 35:

```typescript
// Change this:
: 'wss://crdt-signaling-server.<your-subdomain>.workers.dev'

// To your actual URL:
: 'wss://crdt-signaling-server.YOUR-ACTUAL-SUBDOMAIN.workers.dev'
```

### Option B: Use environment variable

Create `examples/web/.env`:

```bash
VITE_SIGNALING_URL=wss://crdt-signaling-server.YOUR-ACTUAL-SUBDOMAIN.workers.dev
```

## 4. Test Locally (1 minute)

```bash
cd examples/web
npm run dev
```

Open http://localhost:5173 in two browser windows:
1. Click "Connect to Network" in both windows
2. Type in one window, see it sync to the other! ✨

## 5. Deploy Static Site (Optional - 2 minutes)

Deploy your editor to Cloudflare Pages:

```bash
cd examples/web

# Build the site
npm run build

# Deploy to Cloudflare Pages
wrangler pages deploy dist --project-name lambda-editor
```

**Done!** Your collaborative editor is now live on Cloudflare's global network. 🎉

## Troubleshooting

### "Connection failed" error

1. Check the signaling server URL in your code or `.env`
2. Verify the server is deployed:
   ```bash
   wrangler deployments list --config wrangler-signaling.toml
   ```
3. Check browser console for errors

### "Durable Object not found" or migration errors

Make sure you're using `new_sqlite_classes` (required for free tier):
```toml
[[migrations]]
tag = "v1"
new_sqlite_classes = ["SignalingRoom"]  # Not new_classes!
```

If issues persist, delete and redeploy:
```bash
wrangler delete --config wrangler-signaling.toml
wrangler deploy --config wrangler-signaling.toml
```

### TypeScript errors about `import.meta.env`

Make sure `examples/web/src/vite-env.d.ts` exists with the proper type definitions.

## Cost Estimate

**Free tier includes:**
- 100,000 requests/day
- 1M Durable Object requests/month
- Perfect for development and small teams!

**Typical usage:**
- 10 users × 8 hours/day × 20 days = ~16,000 requests/month
- **Well within free tier!** 🎉

## Next Steps

- **Monitor**: View metrics at https://dash.cloudflare.com
- **Custom Domain**: Add your own domain in `wrangler-signaling.toml`
- **Scale**: Free tier → Paid plan ($5/mo) for larger teams
- **Optimize**: Check `CLOUDFLARE_DEPLOYMENT.md` for advanced configuration

## Commands Cheat Sheet

```bash
# Deploy signaling server
wrangler deploy --config wrangler-signaling.toml

# View logs in real-time
wrangler tail --config wrangler-signaling.toml

# Check deployment status
wrangler deployments list --config wrangler-signaling.toml

# Local development (test before deploying)
wrangler dev --config wrangler-signaling.toml --local

# Delete deployment
wrangler delete --config wrangler-signaling.toml
```

## Architecture

```
┌─────────────┐         WebSocket          ┌──────────────────┐
│   Browser   │◄──────────────────────────►│ Cloudflare Worker│
│  (Client)   │      wss://...workers.dev  │ (Signaling Server)│
└─────────────┘                            └──────────────────┘
                                                    │
                                                    ▼
                                           ┌──────────────────┐
                                           │ Durable Object   │
                                           │ (Manages peers)  │
                                           └──────────────────┘
```

After signaling, peers connect directly via WebRTC for low-latency CRDT sync! 🚀
