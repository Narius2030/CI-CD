import Fastify, { type FastifyInstance, type FastifyServerOptions } from 'fastify';

/**
 * Build the Fastify app WITHOUT listening, so tests can drive it via `app.inject()`.
 * server.ts is the only place that calls `.listen()`.
 */
export function buildApp(opts: FastifyServerOptions = { logger: true }): FastifyInstance {
  const app = Fastify(opts);

  // Liveness: process is up.
  app.get('/health', async () => ({ status: 'ok' }));

  // Readiness: ready to serve traffic (add DB/dependency checks here as the app grows).
  app.get('/ready', async () => ({ status: 'ready' }));

  return app;
}
