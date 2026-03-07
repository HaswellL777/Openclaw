# heartbeat

At startup and periodically:
- confirm control files are present
- confirm SOP hash is known
- confirm pending approval state is readable
- confirm allowed worker list is readable
- do not infer host health from heartbeat alone
