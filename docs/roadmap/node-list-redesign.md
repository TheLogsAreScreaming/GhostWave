# Searchable node cards and filters

Status: built in the app (Chats → People: node cards with measured chips, filter counts). Host-tested; not yet tried on a phone.

## Requirements

- Use GhostWave charcoal surfaces and cyan/violet accents with compact node cards.
- Search names and node IDs; filter contacts and recently heard nodes with counts derived from real state.
- Show identity, last heard, trust state, and measured metrics without placeholder telemetry.
- Keep nodes with pending messages discoverable and preserve contact and messaging actions.

## Acceptance checks

- [ ] Check empty, offline, loading, and error states.
- [ ] Test search and combined filters against contacts and nearby nodes.
- [ ] Verify small Samsung-sized viewports, large text, TalkBack labels, and keyboard navigation.
