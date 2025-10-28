import express from 'express';
import cors from 'cors';
import { prisma } from './lib/prisma.js';
import { authRouter } from './routes/auth.js';

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

app.get('/health', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ok: true, database: 'up' });
  } catch (error) {
    res.status(500).json({ ok: false, database: 'down', error: (error as Error).message });
  }
});

app.use('/auth', authRouter);

const port = process.env.PORT ? Number(process.env.PORT) : 3000;
const server = app.listen(port, () => {
  console.log(`API listening on http://localhost:${port}`);
});

const shutdown = async () => {
  console.log('Shutting down API...');
  await prisma.$disconnect();
  server.close(() => process.exit(0));
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
