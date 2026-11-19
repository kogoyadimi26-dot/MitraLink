// The phone has a built-in WebSocket. Supabase's realtime code asks for the Node "ws" package;
// this maps it to the built-in one so the bundle does not need Node-only code.
const WS = globalThis.WebSocket;
module.exports = WS;
module.exports.WebSocket = WS;
module.exports.default = WS;
