// Loads the Web Audio Modules SDK as a module and hands the host part to the engine's classic
// scripts, which load before it. The SDK is vendored: see vendor.json. Modules load from here
// too, since an engine lets a module script import across the page's opaque origin, and may
// refuse a classic one.
import { initializeWamHost } from './wam/index.js';

window.WAM_SDK = { initializeWamHost, load: (url) => import(url) };
dispatchEvent(new Event('wam-sdk'));
