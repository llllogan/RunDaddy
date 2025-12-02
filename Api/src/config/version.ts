import packageJson from '../../package.json' assert { type: 'json' };

const envVersion = process.env.APP_VERSION?.trim();
const fallbackVersion = typeof packageJson.version === 'string' ? packageJson.version : '0.0.0';

export const apiVersion = envVersion && envVersion.length > 0 ? envVersion : fallbackVersion;
