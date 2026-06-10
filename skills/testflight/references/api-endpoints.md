# App Store Connect API — TestFlight Endpoints

Base URL: `https://api.appstoreconnect.apple.com`

## Authentication

All requests require a JWT bearer token signed with ES256 using an App Store Connect API key.

**JWT Claims:**

- `iss` — Issuer ID (from Apple Developer > Users and Access > Integrations > Keys)
- `iat` — Issued-at timestamp (Unix epoch)
- `exp` — Expiration (max 20 minutes from iat)
- `aud` — Must be `appstoreconnect-v1`
- `kid` (header) — API Key ID

**Required API Key Role:** App Manager or Admin. Read-only roles cannot access TestFlight data.

## Core Endpoints

### Apps

```
GET /v1/apps
GET /v1/apps?filter[bundleId]=com.example.app
GET /v1/apps/{id}
```

Filter params: `bundleId`, `name`, `sku`

### Builds

```
GET /v1/builds?filter[app]={appId}&sort=-uploadedDate&limit=20
GET /v1/builds/{id}
GET /v1/builds/{id}/betaBuildLocalizations
```

Key attributes:

- `version` — CFBundleShortVersionString
- `uploadedDate` — ISO 8601
- `processingState` — PROCESSING, FAILED, INVALID, VALID
- `expired` — boolean, true after 90 days

Filter params: `app`, `expired`, `processingState`, `version`, `betaAppReviewSubmission`
Sort: `uploadedDate`, `version`

### Beta Testers

```
GET /v1/betaTesters?filter[apps]={appId}&limit=200
GET /v1/betaTesters/{id}
GET /v1/betaTesters?filter[email]=user@example.com
```

Key attributes:

- `firstName`, `lastName`, `email`
- `inviteType` — EMAIL, PUBLIC_LINK
- `state` — INVITED, ACCEPTED, NOT_FOUND, REVOKED

Filter params: `apps`, `betaGroups`, `builds`, `email`, `firstName`, `lastName`, `inviteType`

### Beta Groups

```
GET /v1/apps/{appId}/betaGroups
GET /v1/betaGroups/{id}
GET /v1/betaGroups/{id}/betaTesters
```

Key attributes:

- `name` — Group display name
- `isInternalGroup` — boolean
- `publicLink` — URL for public TestFlight invite (null if disabled)
- `publicLinkEnabled` — boolean
- `publicLinkLimit` — max testers via public link

### Beta Feedback

```
GET /v1/apps/{appId}/betaFeedbacks?limit=25&sort=-timestamp
```

**Availability note:** This endpoint has limited availability. Apple may return 404 or restrict access. Shake-to-report feedback (screenshots + comments) is primarily accessible through the App Store Connect web UI and Xcode Organizer.

Key attributes (when available):

- `comment` — Tester's text feedback
- `timestamp` — ISO 8601
- `screenshot` — Relationship link to screenshot data

### Beta App Review Submissions

```
GET /v1/betaAppReviewSubmissions?filter[build]={buildId}
POST /v1/betaAppReviewSubmissions
```

Submit a build for beta app review (required for external testing groups).

### Beta Build Localizations

```
GET /v1/builds/{buildId}/betaBuildLocalizations
POST /v1/betaBuildLocalizations
PATCH /v1/betaBuildLocalizations/{id}
```

"What to Test" notes shown to testers for each build.

Key attributes:

- `locale` — e.g., `en-US`
- `whatsNew` — Release notes text

## Pagination

All list endpoints support:

- `limit` — Max items per page (default varies, max 200)
- `cursor` — Opaque cursor for next page

Pagination links in response:

```json
{
  "links": {
    "self": "...",
    "next": "...?cursor=abc123"
  }
}
```

Follow `links.next` until absent to fetch all pages.

## Common Filters

Most endpoints accept:

- `filter[fieldName]=value` — Exact match
- `sort=fieldName` or `sort=-fieldName` — Ascending/descending
- `fields[resourceType]=field1,field2` — Sparse fieldsets
- `include=relationship1,relationship2` — Sideload related resources
- `limit` — Page size

## Rate Limits

Apple enforces rate limits per API key. If receiving HTTP 429:

- Back off exponentially
- Reduce `limit` parameter
- Cache responses when possible
