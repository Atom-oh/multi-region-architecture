# ADR-001: Complete Product Review Feature with Full CRUD, Voting, and Pagination

## Status
Accepted

## Context
The review service had a working backend (CRUD endpoints, DocumentDB storage, Valkey caching) and read-only frontend display, but three critical backend bugs and significant feature gaps made the review system incomplete:

1. **Kafka producer was never initialized** in `main.py` — all review events (`reviews.created`, `reviews.updated`, `reviews.deleted`) were silently dropped
2. **Database name mismatch** — `main.py` used `ServiceConfig` (base class with `db_name=""`) instead of `ReviewConfig` (which sets `db_name="reviews"`), causing the service to connect to the wrong database (`"mall"`)
3. **`user_name` was never populated** on review creation — no call to the user-profile service

On the frontend, users could see reviews but had no way to write, edit, delete, or vote on them. Star rating rendering was duplicated across 5+ files, and the sentiment analysis section displayed hardcoded fake percentages.

## Options Considered

### Option 1: Fix bugs only, defer frontend write capabilities
- **Pros**: Minimal change, low risk
- **Cons**: Users still can't write reviews — the core purpose of the feature remains unmet

### Option 2: Full feature completion (chosen)
- **Pros**: Users get complete review workflow (write, edit, delete, vote, sort, paginate). Shared components reduce code duplication. Backend becomes correct and event-driven.
- **Cons**: Larger changeset, more files modified

### Option 3: Replace with a third-party review service
- **Pros**: Feature-complete out of the box (moderation, sentiment, etc.)
- **Cons**: Adds external dependency, doesn't fit the learning/demo purpose of this project

## Decision
Implement Option 2: full feature completion across backend and frontend in a single coordinated change. This addresses all critical bugs, adds missing CRUD UI, shared components, voting, sorting, pagination, and ownership-based access control.

### Backend changes:
- Fix `main.py` to use `ReviewConfig` (correct `db_name="reviews"`)
- Initialize Kafka producer on startup, stop on shutdown
- Populate `user_name` from user-profile service on review creation
- Add `POST /{review_id}/helpful` endpoint with atomic `$inc`
- Add `sort` query parameter (newest/oldest/highest/lowest/helpful)
- Add `user_id` ownership check on PUT/DELETE (403 if mismatch)
- Fix Kafka topic names in seed script to match actual service topics
- Add `update_user_name` and `increment_helpful` to repository

### Frontend changes:
- Create shared `StarRating` component (display + interactive modes)
- Create `ReviewForm` modal component (create + edit modes)
- Add "Write a Review" button, sort dropdown, "Load More" pagination
- Add helpful voting with localStorage dedup
- Add edit/delete menu for own reviews
- Remove hardcoded sentiment analysis section
- Delete unused `ReviewCard.jsx`
- Add 30 i18n keys (en + ko) for all review interactions

## Consequences

### Positive
- Users can now write, edit, and delete their own reviews
- Helpful voting enables community-driven review quality signals
- Kafka events are actually published (previously silently dropped)
- Reviews connect to the correct database (`reviews` not `mall`)
- Shared `StarRating` component eliminates 5x code duplication
- Sort and pagination improve UX for products with many reviews
- Ownership check prevents unauthorized review modification

### Negative
- Ownership check relies on `user_id` query parameter (not JWT parsing) — sufficient because the API gateway validates JWT before proxying
- `delete_pattern` for cache invalidation uses SCAN which is O(N) — acceptable for current scale
- No server-side review moderation workflow yet (no `status` field)
- No aggregate rating update on the product when reviews change (future work)

## References
- Review service: `src/services/review/`
- Frontend ProductDetailPage: `src/frontend/src/pages/ProductDetailPage.jsx`
- API Gateway review routes: `src/services/api-gateway/main.go` (lines 97-99, 142-144)
- Shared Valkey client: `src/shared/python/mall_common/valkey.py`
