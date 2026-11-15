# UniFlow — updated editable source

Includes Academic Staff and IT dashboards, floating dock, mobile layouts and Arabic RTL.

## Run locally
1. Extract this ZIP.
2. Open the UniFlow folder in VS Code or any code editor.
3. With Python 3 installed, run this command from that folder:

    python -m http.server 8000 --directory dist

On macOS/Linux, use python3 if needed.
4. Open http://localhost:8000 and use the role selector beside “Logged in as” to preview Academic Staff or IT.
5. Edit files and refresh the browser. No npm install or build step is required.

## File guide
- dist/index.html: page shell and CSS/JS imports.
- dist/dashboards.js: NEW Academic Staff and IT dashboard content and actions.
- dist/dashboards.css: NEW dashboard layouts, cards, illustrations and responsive styling.
- dist/workspace.js: workflows, forms, records, Arabic navigation and floating dock.
- dist/workspace.css: theme, typography, mobile/RTL and floating dock styles.
- dist/app.js: original application logic and sample data.
- dist/style.css: original base styles.
- tests/validation.mjs: business-rule checks; requires Node.js.
- README.md: feature scope and validation details.
- .openai/hosting.json: existing Sites hosting configuration; unnecessary for local use.

## Optional checks (Node.js)
    node --check dist/app.js
    node --check dist/workspace.js
    node --check dist/dashboards.js
    node tests/validation.mjs

## Notes
This is a browser-local demo. No backend, university authentication or live AI/IT monitoring is connected. Existing browser records and attachments are not included in the source export; localhost uses separate browser storage. Fonts load from Google Fonts when available. Local edits do not automatically update the published site. To use another static host, deploy the contents of dist.

Published source revision: 7484458394418f006285575e2ecd7bae611b4224
