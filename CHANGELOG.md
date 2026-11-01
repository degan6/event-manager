# Changelog

## [Unreleased]

## [v0.30.1] - 2026-11-01

### Fixed
- A venue email names the new place in the header as well as the rest of the message, including when a whole series has moved
- Putting one postponed date back on tells hosts that date is back on, without saying the RSVPs are still on it

## [v0.30.0] - 2026-11-01

### Added
- Hosts are emailed when they are added or removed, and the other hosts are told as well
- Hosts and people with an RSVP are emailed when an event is cancelled, postponed, or reactivated, or when its date, time, or location changes
- When a cancelled event or date is happening again, people who had RSVPed are asked to RSVP again. Their previous RSVP stays cancelled
- Those emails include an updated calendar file, and they say to delete the previous calendar entry by hand before adding the new file
- A postponed event that is put back on its schedule emails the hosts and the people still RSVPed. Their RSVP stays in place

### Security
- Addressable is 2.9.2 and Rack is 3.2.8, which closes the current addressable and Rack advisories

### Fixed
- Logging in to RSVP returns you to that event and submits the RSVP

## [v0.28.1] - 2026-10-28

### Fixed
- The busy and exclusive scheduling notices on an event page are shown only to that event's hosts

## [v0.28.0] - 2026-10-28

### Added
- Event descriptions can be written with formatting (headings, lists, and links). A plain text copy is kept for calendars, Slack, social posts, and search, and is included alongside the HTML in the JSON and RSS feeds

## [v0.27.2] - 2026-10-28

### Fixed
- Calendar apps that show the formatted description also get the cancellation, reschedule, and location notes, plus the more-info and event-page links
- A link used as a heading is kept in the plain-text description, including its address

## [v0.27.1] - 2026-10-28

### Fixed
- A plain-text event description that contains HTML tags is escaped in the RSS feed, so feed readers do not treat it as markup
- The description editor waits for its script to finish loading, including after navigating with Turbo, and saving no longer clears a plain-text description when that editor has not loaded

## [v0.27.0] - 2026-10-28

### Added
- Event descriptions can be written with formatting (headings, lists, and links). A plain text copy is kept for calendars, Slack, social posts, and search, and is included alongside the HTML in the JSON and RSS feeds

## [v0.26.1] - 2026-10-28

### Fixed
- A long busy or exclusive event still blocks times later in its run, and reactivating a cancelled date is refused when that time is reserved

## [v0.26.0] - 2026-10-28

### Added
- Events can be marked busy, which cautions anyone scheduling during that event or within a buffer around it (one hour by default, changeable per event or in site settings)
- Hosts can request that no other event be scheduled at the same time. An admin has to approve it before it blocks the calendar, and admins are emailed when a review is needed. Changing the schedule of an approved event sends it back for review
- The event form warns about busy times and nearby events while the date is being chosen, and refuses a time that overlaps an approved exclusive event. Admins can override that block, and the override is recorded in the event journal

## [v0.25.2] - 2026-10-28

### Fixed
- Event hosts can't RSVP to their own event

## [v0.25.1] - 2026-10-28

### Fixed
- RSVP events now show that an RSVP is required, how many spots are left, and the RSVP form on the event page, the date page, the event list, and the calendar

## [v0.25.0] - 2026-10-28

### Added
- Events can take RSVPs, with an optional capacity and a wait list. Hosts choose whether an open spot goes to the first person who claims it or is offered to one person at a time
- Guests can RSVP to public events with a name and email. The link in the confirmation email works until the event is over, and someone who already has an account is asked to log in
- Hosts and admins can see the RSVP and wait lists, cancel or promote people, check people in, and download a CSV. Hosts see names only; member names prefer the username
- Confirmed people get reminder emails, and a note to give up their spot when a capacity-limited event is full or has a wait list. Wait-listed people are emailed when a spot opens
- Hosts can opt in to an email for each new RSVP, cancellation, and wait-list join
- Guest names and emails are removed after the event (30 days by default). No-shows are recorded when a host actually used check-in

## [v0.24.4] - 2026-10-28

### Changed
- Ruby is now **4.0.8** in Docker, CI, and local development
- Pagination is **Pagy 43.8.1**
- Sign-in uses **OmniAuth 2.3.1** and **omniauth-oauth2 1.10.0**
- CSS build tools are **PostCSS 8.5.32** and **Sass 1.106.1**

### Security
- HTML sanitizing now uses **crass 1.0.8**, which closes a CSS sanitizer bypass (GHSA-pq4g-8rxf-4g29)

## [v0.24.2] - 2026-10-10

### Fixed
- Choosing a banner image from the event's pool for a single occurrence now sticks, even if "Choose from pool" wasn't selected first; that image overrides the event's image settings for the occurrence and is used in its Slack and social posts
- An occurrence's assigned banner image now follows it when it is postponed, instead of a new one being picked from the pool

## [v0.24.1] - 2026-10-02

### Fixed
- Postponed occurrences now stay in sync when a rescheduled occurrence is edited or postponed again, so calendars, event pages, feeds, and reminders show the latest date and time
- Event and calendar links for postponed occurrences now point at the active tail of a postponement chain, not an intermediate postponed occurrence
- `events:repair_postponement_chains` dry run now reports planned links and syncs and reserves replacement targets like the apply pass
- Postponement replacement links no longer fall back to the wrong occurrence when a stored link is broken, and still point at relocated replacements
- Added `events:repair_postponement_chains` (dry run by default; use `APPLY=1` to fix data) and `events:link_postponement` for repairing legacy postponement chains in the database

## [v0.24.0] - 2026-09-30

### Changed
- Ruby is now **4.0.7** in Docker, CI, and local development
- Pagination uses **Pagy 43**; out-of-range page links still show the last page of results instead of erroring

## [v0.23.2] - 2026-09-29

### Changed
- Occurrences now show whether they are **Open to All**, **Members Only**, or **Private**: a badge on the occurrence page, the event's upcoming occurrences, and the embedded calendar and event lists, and an icon on the calendar grid, with the label included in the grid link's accessible name

### Fixed
- The RSS feeds no longer label private events "Members Only"; the per-event feed now includes the open-to category too

## [v0.23.1] - 2026-09-29

### Changed
- Slack event reminders show the event banner across the full width of the message, like a picture someone attached, instead of as a small thumbnail beside the text

### Fixed
- The event wizard points at whichever field the browser will not accept, instead of appearing to do nothing. A malformed More Info URL or a duration off the 15-minute step silently stopped **Save and Exit**, **Update Event**, **Next**, and the step numbers alike: the browser refuses an invalid field but cannot explain itself while that field is on a hidden panel or scrolled out of sight. The wizard now opens the step holding the field, moves to it, and lets the browser name the problem

## [v0.23.0] - 2026-09-18

### Added
- Editing an event can be saved from any wizard step with a new **Save and Exit** button, instead of having to walk through to Promotion to reach the save. If a required field further along the wizard is empty, the wizard opens that step rather than the browser silently refusing to submit

### Changed
- The wizard's **Cancel** button reads **Cancel Edit** when editing an existing event, so it cannot be mistaken for cancelling the event itself

### Fixed
- Saving an event keeps the selection mode and fixed image chosen in the image pool. Those live in their own form so the pool can save them without leaving the wizard, and saving the event discarded them while still reporting success

## [v0.22.1] - 2026-09-18

### Fixed
- E-ink banner variants are generated again. `Spectra6BannerJob` built its storage key by joining the original key's directory, which for a normal upload is `.`, producing a `./spectra6-7.3/...` key that Active Storage rejects as a path traversal segment. Every run raised, so no event ever had a Spectra6 banner and the feeds always fell back to the full-size image. Run `bin/rails banners:generate_spectra6` to backfill
- Re-running `banners:generate_spectra6` replaces an existing variant instead of colliding with its storage key
- Deleting a user no longer fails outright. `event_journals.user_id` was `NOT NULL` while the association declared `dependent: :nullify`, so removing anyone who had ever edited an event raised a database error. Journal entries now outlive the account, as the audit log intended. (Users who created events are still held back by the events foreign key, which is a separate question)

### Added
- Test coverage for the activity journal and event host controllers, both of which were previously untested, and for `Spectra6BannerJob` end to end

## [v0.22.0] - 2026-09-18

### Fixed
- Co-hosts can view the private and draft events they host. Anyone added as a host could already edit, postpone, and cancel such an event but got "not authorized" trying to open it, and it never appeared in their event list

### Changed
- The events, users, and locations lists are paginated. The events list previously loaded every future occurrence of every event and sorted them in memory on each request, so the work grew with the whole calendar rather than with the page being shown
- Ordering the events list by each event's next date happens in the database, so pages stay cheap as more occurrences accumulate
- The public `/events.json`, `/events/eink`, and `/events/rss` feeds issue a fixed number of queries instead of one or more per event. They were looking up each event's e-ink banner variant, pooled images, and next date individually
- `/events.json` no longer runs the queries for the paginated HTML page it doesn't render
- The user list shows event counts from a single grouped query rather than one count per row

### Added
- Test coverage is measured and enforced. SimpleCov was a listed dependency that nothing ever loaded; `COVERAGE=1 bundle exec rspec` now reports coverage, and CI fails if it drops below the current level

## [v0.21.0] - 2026-09-18

### Changed
- The event wizard has a new **Images** step between Details and Scheduling holding the whole image pool, so images are no longer pinned above the wizard alongside whichever step happens to be open. Creating and editing an event walk the same five steps
- Actions taken in the image pool return to the Images step rather than to the top of the wizard

## [v0.20.0] - 2026-09-18

### Fixed
- Banner images picked while creating an event are actually uploaded. The event form was never marked as multipart, so the browser dropped the files and the new event ended up with an empty image pool
- Images picked in the image pool but never submitted with "Add to Pool" are uploaded when the event is saved, instead of being silently discarded
- Images uploaded to a pool that already has images are numbered from the next free position rather than skipping one

### Changed
- Creating and editing an event now present the same Image Pool section above the wizard. The separate "Banner Images" field on the wizard's Details step is gone
- Uploads submitted with the event form are added to the pool on edit as well as on create

### Added
- Selection mode can be chosen while creating an event rather than only afterwards

## [v0.19.5] - 2026-08-18

### Security
- Rate limits can no longer be bypassed by forging a request header. Visitor addresses are resolved by skipping the proxies listed in `config/trusted_proxies.yml`, and the localhost exemption now requires a genuine local connection, so a forged header can neither claim an exempt address nor evade login and lockout limits by rotating fake ones

## [v0.19.4] - 2026-08-18

### Fixed
- Images no longer come up blank or missing on image-heavy pages: rate limiting counted every image request against the same per-visitor page budget, so viewing a few events with a full image pool returned throttled responses that browsers render as broken images and that quietly started working again minutes later
- Rate limits are applied per visitor again rather than collectively. Behind Cloudflare and the reverse proxy, every request looked like it came from a Cloudflare edge address, so all visitors shared a single budget
- Sidekiq can read and write uploaded images, so background image processing no longer fails on a missing storage volume
- Release tags are named `v0.19.4` rather than `vv0.19.4`; the production workflow was prefixing a `v` onto a VERSION file that already had one
- CI gives each parallel test process its own database. Both processes shared one, so they intermittently deadlocked against each other and failed builds for reasons unrelated to the code under test

### Changed
- Image previews load a scaled-down version instead of the full-resolution original, so the image pool, event cards, calendar thumbnails, and pickers load a fraction of the data they used to
- Previews load as they scroll into view rather than all at once
- Images are delivered in one request instead of two and are cached by the browser and CDN, so revisiting a page no longer re-downloads every image
- The site runs multiple web workers by default, configurable with `WEB_CONCURRENCY`

### Added
- `rails images:preprocess_variants` generates preview sizes for images uploaded before previews existed
- [docs/IMAGE_DELIVERY.md](docs/IMAGE_DELIVERY.md) documents how images are served, what the reverse proxy needs to pass through, and how to diagnose missing images

## [v0.19.3] - 2026-08-17

### Fixed
- Calendar downloads and iCal feeds no longer shift event times: dates are now written as unambiguous UTC instants, so an event at 6:30 PM Pacific imports as 6:30 PM Pacific instead of drifting by the UTC offset
- Subscribed calendars outside the site's time zone show the correct start time rather than the local wall clock
- Occurrence status is mapped to a value the iCalendar standard allows, so cancelled and postponed events display correctly instead of being ignored
- Per-event feeds give each occurrence a stable identifier, so subscribers no longer accumulate duplicate copies on every refresh

### Changed
- Feeds and downloads carry a calendar name and display time zone, and every entry links back to its own occurrence page

### Added
- Calendar exports share a single builder, so the download button, the site-wide feed, the per-event feed, and the Google/Outlook/Yahoo links stay consistent

## [v0.19.2] - 2026-08-16

### Fixed
- README workflow badges now point at the correct workflows so CI, lint, and Docker build show accurate status

## [v0.19.1] - 2026-08-16

### Added
- README badges for CI, lint, Docker build, Ruby version, Rails version, and MIT license

## [v0.19.0] - 2026-08-16

### Added
- Reassign Existing Occurrences button in the image pool to apply the saved selection mode to all non-custom occurrences

### Fixed
- Occurrence edits no longer re-roll or advance the image cycle when the inherit option is unchanged
- Switching an occurrence from a custom image back to inherit advances the cycle index in cycle mode
- Image pool settings, reassign, and delete actions use separate forms instead of invalid nested forms
- Occurrence image reassignment follows schedule order (`occurs_at`) rather than database id order
- Pool image deletion clears references on soft-deleted occurrences so foreign keys do not block removal
- Event image pool migration sets `fixed_event_image_id` on the correct event after repointing banner attachments
- `bin/rubocop-local` rebuilds its cached image when the Ruby version or gems change, instead of silently reusing an image built on an older Ruby

## [v0.18.0] - 2026-08-16

### Added
- Event image pool: upload multiple banner images per event, reorder them, and remove images from the pool
- Image selection modes for new occurrences: fixed, random (avoid immediate repeat), or cycle through the pool in order
- Occurrence image editing: inherit auto-assigned image, pick from pool, or upload a custom image (optionally add to pool)
- Data migration moves existing event and occurrence banner attachments into the new pool on deploy

## [v0.13.2] - Thu Mar  5 09:13:59 PST 2026
