import express from 'express';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import { prisma } from './lib/prisma.js';
import { authRouter } from './routes/auth.js';
import { usersRouter } from './routes/users.js';
import { runImportsRouter } from './routes/run-imports.js';
import { runRouter, getRunDetailPayload } from './routes/runs.js';
import { skuRouter } from './routes/skus.js';
import { inviteCodesRouter } from './routes/invite-codes.js';
import { authenticate } from './middleware/authenticate.js';

const app = express();
const defaultOrigins = ['http://localhost:4200'];
const allowedOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',').map((origin) => origin.trim()).filter(Boolean)
  : defaultOrigins;

app.use(
  cors({
    origin: allowedOrigins,
    credentials: true,
  }),
);
app.use(cookieParser());
app.use(express.json());

// Logging middleware
app.use((req, res, next) => {
  let responseBody: any;

  const originalJson = res.json;
  res.json = function (body) {
    responseBody = body;
    return originalJson.call(this, body);
  };

  const originalSend = res.send;
  res.send = function (body) {
    responseBody = body;
    return originalSend.call(this, body);
  };

  res.on('finish', () => {
    let responseStr = '';

    if (typeof responseBody === 'string') {
      responseStr = responseBody;
    } else if (Buffer.isBuffer(responseBody)) {
      responseStr = responseBody.toString('utf8');
    } else if (responseBody !== undefined) {
      try {
        responseStr = JSON.stringify(responseBody);
      } catch {
        responseStr = '[unserializable response]';
      }
    }

    const truncatedResponse = responseStr.length > 20 ? `${responseStr.substring(0, 20)}...` : responseStr;
    console.log(`${req.method} ${req.originalUrl} - ${res.statusCode} - ${truncatedResponse}`);
  });

  next();
});

app.get('/api/health', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1 as ok`;
    res.json({ ok: true, database: 'up' });
  } catch (error) {
    res.status(500).json({ ok: false, database: 'down', error: (error as Error).message });
  }
});

app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);
app.use('/api/run-imports', runImportsRouter);
app.use('/api/runs', runRouter);
app.use('/api/skus', skuRouter);
app.use('/api/invite-codes', inviteCodesRouter);

if (process.env.NODE_ENV !== 'production') {
  const { debugRouter } = await import('./routes/debug.js');
  app.use('/api/debug', debugRouter);
}

const port = process.env.PORT ? Number(process.env.PORT) : 3000;
let server: ReturnType<typeof app.listen> | undefined;

const start = async () => {
  try {
    console.log('Verifying database connectivity...');
    await prisma.$connect();
    await prisma.$queryRaw`CALL sp_health_check()`;
    server = app.listen(port, () => {
      console.log(`API listening on http://localhost:${port}`);
    });
  } catch (error) {
    console.error('Failed to connect to the database. Shutting down.');
    console.error(error);
    await prisma.$disconnect().catch(() => null);
    process.exit(1);
  }
};

const shutdown = async () => {
  console.log('Shutting down API...');
  await prisma.$disconnect();
  if (server) {
    server.close(() => process.exit(0));
  } else {
    process.exit(0);
  }
};

void start();

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
