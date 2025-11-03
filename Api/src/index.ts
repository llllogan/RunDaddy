import express from 'express';
import cors from 'cors';
import { prisma } from './lib/prisma.js';
import { authRouter } from './routes/auth.js';
import { companiesRouter } from './routes/companies.js';
import { usersRouter } from './routes/users.js';
import { machineTypesRouter } from './routes/machine-types.js';
import { locationsRouter } from './routes/locations.js';
import { machinesRouter } from './routes/machines.js';
import { skusRouter } from './routes/skus.js';
import { runsRouter } from './routes/runs.js';
import { runImportsRouter } from './routes/run-imports.js';
import { debugRouter } from './routes/debug.js';

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
    console.log(`${req.method} ${req.originalUrl} - ${res.statusCode} - ${JSON.stringify(responseBody)}`);
  });

  next();
});

app.get('/health', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1 as ok`;
    res.json({ ok: true, database: 'up' });
  } catch (error) {
    res.status(500).json({ ok: false, database: 'down', error: (error as Error).message });
  }
});

app.use('/auth', authRouter);
app.use('/companies', companiesRouter);
app.use('/users', usersRouter);
app.use('/machine-types', machineTypesRouter);
app.use('/locations', locationsRouter);
app.use('/machines', machinesRouter);
app.use('/skus', skusRouter);
app.use('/runs', runsRouter);
app.use('/run-imports', runImportsRouter);
app.use('/debug', debugRouter);

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
