# RSS Ingestion — Core

The canonical pattern for workflow 2's RSS fan-out + dedup.

## Fan-out across RSS_FEEDS

`RSS_FEEDS` is a comma-separated string in `.env`. The pattern:

1. **Code node — split** — turn the env var into N items, one per feed URL.
2. **Split In Batches** — n8n's batching primitive, batch size 1 (process feeds serially to keep memory bounded).
3. **RSS Feed Read** — one feed per iteration.
4. **Merge — append** — concatenate all feed items into a single flat list.
5. **Code node — normalize** — unify field names across Atom / RSS 2.0 / RSS 1.0.
6. **Code node — dedup** — filter against `content_briefs.guid` last 7 days.
7. **Code node — sort + slice** — keep top N most recent.

### Split step

```javascript
// Code node — split $env.RSS_FEEDS into items
const feeds = ($env.RSS_FEEDS || '').split(',').map(s => s.trim()).filter(Boolean);
return feeds.map(url => ({ json: { feed_url: url } }));
```

### Normalize step

```javascript
// Code node — normalize fields across feed formats
return items.map(item => ({
  json: {
    guid:    item.json.guid || item.json.id || item.json.link,
    title:   item.json.title,
    link:    item.json.link,
    pubDate: item.json.pubDate || item.json.isoDate || item.json.published,
    source:  item.json.feed_url,
    snippet: (item.json.contentSnippet || item.json.summary || '').slice(0, 500),
  }
}));
```

### Dedup step (queries Supabase)

```javascript
// HTTP Request → Supabase
// GET /rest/v1/content_briefs?guid=in.(...)&created_at=gte.<7d ago>&select=guid
//
// Then a Code node filters:
const seen = new Set(items.filter(i => i.source === 'supabase').map(i => i.json.guid));
return items.filter(i => i.source !== 'supabase' && !seen.has(i.json.guid));
```

Or use Supabase RPC for a single round-trip:
```sql
create or replace function recent_guids(guids text[])
  returns table (guid text) language sql stable as $$
  select guid from content_briefs
   where guid = any(guids) and created_at >= now() - interval '7 days';
$$;
```

## Freshness window

Filter to items published in the last 24 hours:

```javascript
const cutoff = Date.now() - 24 * 3600 * 1000;
return items.filter(i => new Date(i.json.pubDate).getTime() >= cutoff);
```

## Failure handling (rule 03)

If a single feed errors:
- Bounded retry (2 attempts) per feed at the RSS node level.
- After 2 failures: skip that feed, log to `error_log` with `kind='rss_feed_error'`, continue with remaining feeds.
- The brief STILL ships — partial coverage is acceptable; missing brief is not.

If ALL feeds fail or return zero items after dedup:
- Skip the Anthropic call (don't bill for empty input).
- Insert `workflow_runs` row with `status='skipped_empty'`.
- Do NOT post to Slack — empty briefs train the team to ignore the channel.

## `content_briefs` schema (for archive + dedup)

```sql
create table content_briefs (
  guid       text primary key,
  title      text not null,
  link       text not null,
  source     text not null,
  pub_date   timestamptz,
  selected   boolean default false,  -- true if it made the final brief
  created_at timestamptz default now()
);
create index on content_briefs (created_at desc);
```

After Opus selects 3 items, mark `selected = true` for those guids; insert the rest with `selected = false` so they still count toward dedup horizon.
