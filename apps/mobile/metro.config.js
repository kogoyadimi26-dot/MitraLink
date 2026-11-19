const path = require('path');
const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// Node-only modules pulled in by supabase-js. Map them to the phone's built-in WebSocket or to empty stand-ins.
const SHIMS = {
  ws: path.resolve(__dirname, 'shims/ws.js'),
  zlib: path.resolve(__dirname, 'shims/empty.js'),
};

config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (SHIMS[moduleName]) {
    return { type: 'sourceFile', filePath: SHIMS[moduleName] };
  }
  return context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
