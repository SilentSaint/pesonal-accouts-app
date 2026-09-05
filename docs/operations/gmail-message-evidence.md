# Gmail message-body evidence

`POST /api/gmail/scan` fetches Gmail messages with `format=full`. Its existing
`snippet` response field now holds bounded decoded message-body evidence when
available, rather than always containing Gmail's short preview. Both Gemini and
the deterministic parser consume this evidence; transaction candidates and
`rawScannedEmails` expose the same text for the existing review flow.

## Coverage contract

Each raw email and transaction candidate includes:

| Field | Values and meaning |
| --- | --- |
| `contentSource` | `plain_text`, `html`, or `snippet`. `html` also covers combined inline parts that include HTML. |
| `contentStatus` | `complete`: the selected supported body fits the limits; `snippet_only`: no usable body was supplied; `unsupported`: some required inline content could not be decoded; `truncated`: a size or traversal limit was reached. |

Coverage is not merchant confidence, sender authenticity, or proof of payment.
`truncated` takes precedence if more than one limitation applies. When no usable
body text is available, the bounded Gmail preview remains available with its
explicit limitation status. Unsupported parts do not discard other supported
inline evidence.

The decoder supports base64url UTF-8 and US-ASCII text/plain and text/html.
It prefers plain text within multipart alternatives, joins inline mixed parts,
and excludes named files and attachment-disposition parts. It does not retrieve
attachment bodies or follow links. Unsupported encodings and attachment-backed
inline body parts are reported as unsupported.

HTML is converted to plain text without executing it, preserving common block
separators and decoding common/numeric entities. Scripts, styles, and the head
are omitted. This is a bounded text extractor, not an HTML sanitizer, a browser
layout engine, or a prompt-injection defense. The returned text must remain
untrusted data.

## Bounds

- At most 8,000 UTF-16 code units of evidence per message, without splitting a
  surrogate pair.
- A 1 MiB serialized-evidence budget is shared fairly across the messages in a
  scan. This further limits each message in large scans and reserves space for
  duplicated candidate/raw evidence and JSON proxy escaping.
- At most 65,536 base64url characters are decoded per inline part.
- MIME traversal visits at most 64 nodes, with a maximum depth of 16.

The bounds apply to evidence processing and model/review output. They are not a
streaming download limit on Gmail's HTTP response, nor a guarantee that arbitrary
provider headers or model responses fit a response-size budget. Large-scan worker
orchestration remains outside this slice.

## Local validation

```sh
backend/lambda/build.sh
node --test backend/lambda/test/gmail_body_scan.test.js \
  backend/lambda/test/gmail_scan_query.test.js \
  backend/lambda/test/deployed_gmail_scan.test.js \
  backend/lambda/test/archive_parity.test.js \
  backend/lambda/test/analytics_api.test.js \
  backend/lambda/test/sync_publication.test.js
cd frontend
flutter test test/gmail_oauth_recovery_test.dart \
  test/transaction_review_confirmation_test.dart
```

Handler regressions use fictional messages and fake only external Gmail, Gemini,
and AWS calls. Mock model responses establish transport/contract behavior, not
model extraction accuracy. The archive tests concern the local deployment
artifact, not a deployed AWS function.

## Scope

This implements the input-evidence portion of #102, under #101. It does not
remove subject-to-merchant fallbacks, change categorization or due-date policy,
or protect alias learning. Those end-to-end identity safeguards are tracked in
#103 and #104. The existing review preview remains three lines; coverage-state
presentation and identity provenance persistence belong to those follow-up slices.
