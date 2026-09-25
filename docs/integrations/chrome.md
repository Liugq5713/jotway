# Chrome action

> Role: **Current**

Chrome opens a Google search for the current text.

## Routing

Local phrases include “Google 搜”, “谷歌搜”, and “Chrome 搜”. Jev may suggest the action for a public-information search. Chrome cannot be the default action.

## Execution

Jotway trims and percent-encodes the query, builds a Google search URL, locates Google Chrome by bundle identifier, and asks macOS to open the URL with Chrome.

On success Jotway leaves Chrome frontmost. If the query is empty, Chrome is unavailable, the URL cannot be built, or macOS rejects the open request, the draft is restored.

Jotway does not inspect the resulting page or treat browser loading as part of action completion.
