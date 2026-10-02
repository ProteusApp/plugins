# React

JSX and TSX support for the Proteus code editor, on the language server that `lang.typescript` runs.

## What it does

- **Completion, hover help and go to definition** in `.jsx` and `.tsx` files, from the same server as plain TypeScript and JavaScript. A component knows the types of everything it imports.
- **Problems.** Mistakes show as underlines and in the Problems panel (Ctrl+Shift+M).
- **Hooks as whole statements.** A word alone on its line offers React's common hooks before the server's items. Picking `useState` writes `const [value, setValue] = useState()`. `useEffect`, `useMemo`, `useCallback`, `useRef`, `useContext` and `useReducer` work the same way.
- **A component skeleton.** `component` at the start of a line writes a component named after the file, with typed props in a `.tsx` file.
- **New React Component.** **React: New React Component…** asks for a name, such as `Button`, and makes `Button.tsx` beside the file in front, or in the open folder. It makes `Button.jsx` instead beside a JavaScript file, or in a folder with no `tsconfig.json`. Then it opens the new file.

Formatting comes from Prettier, which ships with Proteus.

## What it needs

`lang.typescript` and what it needs: Node.js, with `typescript-language-server` and TypeScript installed. The marketplace installs `lang.typescript` along with this plugin.

## How it is built

`init.lua` asks `lang.typescript` to serve JSX and TSX, adds the hook completion as a `completion` file association for `*.jsx` and `*.tsx`, and adds the command. `lib/hooks.lua` decides which items fit where the cursor is, and `lib/component.lua` writes a new component's text.
