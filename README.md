# Stonks

The app uses Finnhub quote and company-profile endpoints for a fixed ten-ticker universe: AAPL, MSFT, NVDA, AMZN, GOOGL, META, TSLA, JPM, XOM, and WMT.

## Local setup

Copy `Secrets.plist.example` to `Stonks/Configuration/Secrets.plist` and insert a reviewer-owned `FINNHUB_API_KEY`. The local plist is ignored by Git and the key is never stored in source, logs, reducer state, or test fixtures. This protects Git history only: resources shipped inside an iOS app can be extracted. A production deployment should put Finnhub behind a backend proxy and use appropriate commercial data rights.

Finnhub requests carry the key only in `X-Finnhub-Token`. It is independent from DummyJSON access and refresh tokens. The composition root creates one shared credential-free `HTTPClient` value below separate provider-specific clients; neither provider's credential policy is owned by that transport.

## Concurrency and state behavior

The initial load starts quote and company-profile work concurrently for each ticker, while a structured scheduler bounds active ticker jobs to five. Leaving the Stocks screen cancels its structured load. A refresh reloads every quote, reuses successful profiles already held in memory, and fetches only missing profiles concurrently with their quote. New loads cancel older work, and load generations reject stale responses. Endpoint failures remain on their individual cards, so partial data is renderable, and safe banners describe settled screen-wide conditions. Best and worst movers are derived only after the current card set settles and require two finite successful quotes.

Stocks are not persisted across launches. Profiles reused during refresh exist only in process memory and are fetched again after relaunch. Logout cancels active authenticated work, clears the local session, and returns to a fresh login screen.
