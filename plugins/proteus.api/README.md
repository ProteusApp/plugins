# API Client

An API client that sends HTTP requests, saves them, and shows the answers. Install the **API Client** profile from the marketplace to run it as an app of its own.

## What it does

- **Requests.** Each request has a method, an address, query parameters, headers, a body (JSON, text, form or multipart form) and authentication (a bearer token or a user name and password). Ctrl+Enter sends it.
- **Answers.** The answer shows its status, time and size, then the body, formatted when it is JSON, and the headers. Copy as curl and Import curl move a request to and from the command line. Import curl says what the request leaves out, such as a file the command sends, since a request holds only text.
- **Saved requests.** Each saved request is a JSON file in `data/proteus.api/`, in folders of your own. The Requests view lists them and searches them.
- **Environments.** `data/proteus.api/environments.json` holds sets of values, and `{{name}}` in a request takes the value from the chosen set.
- **History.** The History view keeps the last 50 requests sent.

New requests and unsaved changes stay in `app.store`, so a reload keeps them. Before 0.3.0 the requests lived in `data/api/`, and Proteus moves them on its first start.

## Permissions

| Permission | Why |
|------------|-----|
| `net` | It sends the requests you write, to any address, and uses the `http` service that builds them. |

It writes only in its own `data/proteus.api/` folder.
