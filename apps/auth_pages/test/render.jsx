// Renders a page on the server, for test/pages.test.js. Loaded through Vite,
// so the page and React resolve the same way.
import { renderToStaticMarkup } from 'react-dom/server';

import { App } from '../src/App.jsx';

export function render(address) {
  globalThis.window = { location: new URL(address, 'https://auth.example.test') };
  return renderToStaticMarkup(<App />);
}
