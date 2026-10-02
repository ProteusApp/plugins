# API Client

An API client that sends HTTP requests, saves them, and shows the answers. Install the **API Client** profile from the marketplace to run it as an app of its own.

## What it does

- **Requests.** Each request has a method, an address, query parameters, headers, a body and a sign-in. Ctrl+Enter sends it, and Cancel stops it on the way.
- **Bodies.** JSON, text, form, multipart form, GraphQL with its variables, or a file. A multipart row can send a file too. You pick each file in the system's dialog, and the request keeps it for next time.
- **Sign-ins.** A bearer token, a user name and password (Basic or Digest), an API key in a header or the query, or OAuth 2 with client credentials or a password, which gets a token and keeps it in memory until it runs out. A request set to **From folder** uses the sign-in of its folder, which you set with **Folder Sign-in** on the folder's menu.
- **Options.** How long to wait for the answer, and whether to follow redirects.
- **Answers.** The answer shows its status, the time the app measured, its size and where a redirect led, then the body, formatted when it is JSON and in hex when it is bytes, and every header, repeats included.
- **Import.** Import Collection reads a Postman collection, an OpenAPI or Swagger description in JSON or YAML, an Insomnia export or a HAR file into a folder of its own, with its folder sign-ins, and puts its variables in a new environment. Copy as curl and Import curl move a request to and from the command line. A file a collection or a command sends waits for you to pick it.
- **Saved requests.** Each saved request is a JSON file in `data/proteus.api/`, in folders of your own. The Requests view lists them and searches them.
- **Environments.** `data/proteus.api/environments.json` holds sets of values, and `{{name}}` in a request takes the value from the chosen set.
- **History.** The History view keeps the last 50 requests sent.

New requests and unsaved changes stay in `app.store`, so a reload keeps them. Before 0.3.0 the requests lived in `data/api/`, and Proteus moves them on its first start.

It needs Proteus with the features `grants`, `grants-read` and `http-bodies`.

## Permissions

| Permission | Why |
|------------|-----|
| `net` | It sends the requests you write, to any address, and uses the `http` service that builds them. |

It writes only in its own `data/proteus.api/` folder. It reads and sends only the files you pick, so it needs no `files` permission.
