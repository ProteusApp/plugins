// Takes on the app's theme. The page cannot read the app's style, so the plugin sends the
// theme's variables in a message, and this sets each one on the page, such as --bg and --fg.
// The style sheet has a value of its own for each, for the moment before the message comes.

(() => {
  'use strict';

  proteus.on((message) => {
    if (!message || message.type !== 'theme') return;
    const root = document.documentElement;
    const vars = message.vars || {};
    for (const key of Object.keys(vars)) {
      // Only plain names, so a value never reaches past its own variable.
      if (/^[a-z0-9-]+$/i.test(key)) root.style.setProperty('--' + key, String(vars[key]));
    }
    root.style.colorScheme = message.dark === false ? 'light' : 'dark';
  });
})();
