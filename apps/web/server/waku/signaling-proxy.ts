import type { Hono, MiddlewareHandler } from 'hono';
import {
  createWorkerTelemetryRecord,
  type WorkerErrorCategory,
  type WorkerTelemetryRecord,
} from './observability.ts';
import { decideWakuRequest } from './request-policy.ts';

type CanopyWorkerEnvironment = {
  Bindings: Env;
};

type RequestMiddlewareOptions = Readonly<{
  app: Hono;
  emit?: (record: WorkerTelemetryRecord) => void;
}>;

function createSafeWakuErrorResponse(request: Request): Response {
  const acceptsHtml = request.headers.get('accept')?.includes('text/html') === true;
  return new Response(
    acceptsHtml
      ? '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Temporarily unavailable — Canopy</title></head><body><main><h1>Route temporarily unavailable</h1><p>Canopy could not load this route.</p><p><a href="">Retry</a> · <a href="/">Back to demos</a></p></main></body></html>'
      : 'Route temporarily unavailable',
    {
      status: 500,
      headers: {
        'content-type': acceptsHtml
          ? 'text/html; charset=utf-8'
          : 'text/plain; charset=utf-8',
      },
    },
  );
}

export function createWakuRequestMiddleware(
  options: RequestMiddlewareOptions,
): MiddlewareHandler<CanopyWorkerEnvironment> {
  const emit = options.emit ?? ((record) => console.log(record));
  options.app.onError((_error, context) => createSafeWakuErrorResponse(context.req.raw));

  return async (context, next) => {
    const request = context.req.raw;
    const url = new URL(request.url);
    const decision = decideWakuRequest({
      pathname: url.pathname,
      search: url.search,
    });
    const deploymentVersion = context.env?.WORKER_VERSION?.id;
    const finish = (
      response: Response,
      errorCategory: WorkerErrorCategory = 'none',
    ): Response => {
      emit(createWorkerTelemetryRecord({
        deploymentVersion,
        routeClass: decision.routeClass,
        capability: decision.capability,
        status: response.status,
        errorCategory,
      }));
      return response;
    };

    if (decision.action === 'redirect') {
      return finish(new Response(null, {
        status: 308,
        headers: { Location: decision.location },
      }));
    }
    if (decision.action === 'serve-static-asset') {
      try {
        const assets = context.env?.ASSETS;
        if (assets === undefined) throw new Error('ASSETS binding unavailable');
        return finish(await assets.fetch(request));
      } catch {
        return finish(
          new Response('Asset temporarily unavailable', { status: 502 }),
          'asset-unavailable',
        );
      }
    }
    if (decision.action === 'proxy-signaling') {
      try {
        const signaling = context.env?.SIGNALING;
        if (signaling === undefined) throw new Error('SIGNALING binding unavailable');
        return finish(await signaling.fetch(request));
      } catch {
        return finish(
          new Response('Signaling temporarily unavailable', { status: 502 }),
          'signaling-unavailable',
        );
      }
    }

    try {
      await next();
      return finish(
        context.res,
        context.error === undefined ? 'none' : 'waku-unhandled',
      );
    } catch {
      return finish(createSafeWakuErrorResponse(request), 'waku-unhandled');
    }
  };
}
