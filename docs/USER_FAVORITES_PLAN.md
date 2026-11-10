# Plan: User Favorites

Status: planned, not implemented. Target version: **0.32.0** (feature release).
Branch: `feature/user-favorites` (off `main`)

## Goals

- Logged-in users can favorite a whole event (every date) or a single occurrence (one date).
- The dashboard shows a user's favorites and their upcoming dates.
- Users get an email when something they favorited changes: description, banner, title, time, venue, cancellation, or postponement.
- Users get a reminder before each upcoming date they're following.
- Users are not emailed every time a recurring event adds another date further out on the calendar.

## Out of scope

- Favorites for guests. A favorite belongs to a `User`.
- Slack or other non-email notifications.
- Showing favorite counts publicly or to hosts. This could come later, but hosts seeing who follows their event is a privacy question to decide separately.
- Changes to who can see the dashboard. Non-hosts already reach it; they will now have something on it.

## Key design decisions

### What a favorite covers

| Favorite on        | Change emails                                                                          | Reminders                       |
|--------------------|----------------------------------------------------------------------------------------|---------------------------------|
| An event           | Changes to the event, and changes to any of its upcoming dates                         | Every upcoming date             |
| An occurrence      | Changes to that date, plus event changes that show up on that date (inherited description or banner, title, venue) | That date only |

A user can favorite an event and one of its dates at the same time. They still get one email per change and one reminder per date.

When an occurrence is postponed, `postpone!` creates a new occurrence. Favorites on the old date move to the new one, the same way `RsvpLifecycle.transfer!` moves RSVPs, and the user gets the postponement email.

### Who can favorite

Anyone who passes `EventPolicy#show?` for the event. Visibility is checked again when an email is sent. If an event becomes private or goes back to draft, followers who can no longer see it are skipped, and their favorites are kept in case it becomes visible again.

### New dates: when to notify

Occurrences are created by `OccurrenceGenerator`. That happens when an event is created, when its schedule is edited, and in the nightly `RegenerateEventOccurrencesJob`, which tops up the rolling window (`max_occurrences`, default 5). There is no "add a date" action. The only other way a date is created is `postpone!`, and that's handled as a postponement.

The rule: **a new date sends an email only if the event had no other upcoming dates when it was added.** Every other new date is silent, and the user hears about it from the reminder as it gets close.

| Situation                                                                   | Email?                                    |
|-----------------------------------------------------------------------------|-------------------------------------------|
| Weekly event; the nightly job adds the date five weeks out                  | No                                        |
| One-time event already happened; host schedules it again                    | Yes, "a new date was added"               |
| Recurring event had run out of dates (or was paused) and gets new ones      | Yes, one email listing the next date      |
| One-time event still upcoming; a second date is added through a schedule edit | No new-date email. The schedule edit sends its own series email (see below) |
| A date is postponed (which creates a new occurrence)                        | Postponement email, not a new-date email  |

Schedule edits that regenerate dates already run inside `ScheduleNotifier.silence_occurrence_hosts`, and hosts get one series summary. Followers get the same: one "the schedule changed" email with the next few dates, and no individual emails for each date that was dropped or added.

### Reminders

- Every followed date gets a reminder the day before (default 24 hours, as a site setting).
- A date followed on its own (an occurrence favorite) also gets a heads-up 7 days before. Event followers don't, because on a weekly event it would arrive right after the previous day-before reminder. If the date is added less than 7 days out, the heads-up is skipped and only the day-before reminder is sent.
- Reminders are on by default for every favorite, and the user can turn them off for each one.
- Only for dates that are `active` or `relocated`, on published events that are `active`.
- If the user has an active RSVP for that date, skip the favorite reminder. `RsvpReminderJob` already reminds them.
- A weekly event therefore means one email a week, the day before. That's the "the one next Thursday is coming up" case.
- Reminders are logged per user and per date, so the hourly job can't send twice, and a user following both the event and the date gets one reminder.

### Change emails: immediate or batched

- **Schedule changes** (cancelled, postponed, time or duration changed, relocated, venue changed, reactivated) are sent right away. They already flow through `ScheduleNotifier`, and favorites hook in there.
- **Content changes** (description, banner, title, more-info link) are batched. Hosts often save a description several times or upload a banner right after editing text. Each change is recorded, and a job sends one email per follower per event once there have been no more edits for 30 minutes. The email shows the current description and banner, not a diff.
- The person who made the change is never emailed about their own change.
- If a user has an active RSVP for an affected date, skip the favorite schedule email for that date, because `RsvpNotifier` already sends one. Content changes still go out, since RSVP emails don't cover them.

### Only human edits count as changes

Content changes are detected in `after_update` callbacks only when `current_user_for_journal` is set. Controllers already set it for host edits, and it isn't set for automated saves. That keeps these out of notifications:

- Banner rotation in `random` and `cycle` image modes, including `EventImageSelector` advancing `image_cycle_index`
- `EventImageReassigner` and pool images being added to occurrences when they're generated
- The nightly regeneration job

What counts as a banner change:

- An occurrence gets a custom banner, or its custom banner changes or is removed
- The event's fixed banner (`fixed_event_image_id`) changes while in `fixed` mode
- The image selection mode changes

Adding or removing images in a random or cycle pool is not a change. Followers see the pool when the banner on each date changes.

### Unsubscribing

- Every email has a one-click "Stop following" link that removes that favorite, using a signed token (`generates_token_for`), plus a `List-Unsubscribe` header.
- Users can turn off all favorite emails on their profile (`favorite_emails_enabled`) and keep favorites on the dashboard. This sits next to the existing `email_reminders_enabled` setting.
- Each favorite has its own `reminders_enabled` toggle. That way a user can follow changes to a weekly event without getting the weekly reminder.

## Data model

### New table: `favorites`

| Column                | Notes                                                  |
|-----------------------|--------------------------------------------------------|
| `user_id`             | FK, not null                                           |
| `event_id`            | FK, not null. Set for occurrence favorites as well     |
| `event_occurrence_id` | FK, nullable. Null means the whole event               |
| `reminders_enabled`   | boolean, default true                                  |
| timestamps            |                                                        |

Storing `event_id` on every favorite means "everyone following this occurrence" is one query: `where(event_id: occ.event_id, event_occurrence_id: [nil, occ.id])`.

Indexes:

- Unique on `(user_id, event_id)` where `event_occurrence_id IS NULL`
- Unique on `(user_id, event_occurrence_id)` where `event_occurrence_id IS NOT NULL`
- `(event_id)` and `(event_occurrence_id)` for fan-out

### New table: `favorite_changes`

A queue of content changes waiting to be batched.

| Column                | Notes                                                              |
|-----------------------|--------------------------------------------------------------------|
| `event_id`            | FK, not null                                                       |
| `event_occurrence_id` | FK, nullable. Set when the change is to one date                   |
| `kind`                | `description`, `banner`, `title`, `details` (check constraint)     |
| `actor_id`            | FK to users, nullable                                              |
| `delivered_at`        | datetime, null until sent                                          |
| timestamps            |                                                                    |

Followers are looked up when the email is sent, not when the change is recorded. That way someone who unfollows in the meantime doesn't get it.

### New table: `favorite_reminder_deliveries`

| Column                | Notes                              |
|-----------------------|------------------------------------|
| `user_id`             | FK, not null                       |
| `event_occurrence_id` | FK, not null                       |
| `kind`                | `7d` or `1d` (check constraint)    |
| `sent_at`             | datetime, not null                 |

Unique on `(user_id, event_occurrence_id, kind)`. When a date's time changes, its delivery rows are deleted so the reminder goes out again for the new time.

### Migration: `users`

- `favorite_emails_enabled` boolean, default true

### Migration: `site_configs`

- `favorites_enabled` boolean, default true (site-wide kill switch)
- `favorite_reminder_hours` integer, default 24
- `favorite_change_quiet_minutes` integer, default 30

### Models and services

- `Favorite` model: `belongs_to :user, :event`, optional `:event_occurrence`, `event_favorite?` / `occurrence_favorite?`, and a validation that the occurrence belongs to the event.
- `User has_many :favorites`. `Event` and `EventOccurrence` get `has_many :favorites, dependent: :destroy`.
- `Favorite.followers_of(occurrence)` and `Favorite.followers_of_event(event)` return distinct users, filtered for `favorite_emails_enabled` and the visibility check.
- `FavoriteService` handles toggling, including moving favorites when a date is postponed.
- `FavoriteNotifier` is the one place emails go out from. It's called from `ScheduleNotifier` (schedule changes), `FavoriteChangeDigestJob` (content changes), and `FavoriteReminderJob`. It handles skipping the person who made the change, skipping people with an RSVP, and deduplicating.

## Emails

All emails go through `EmailTestMode.recipient_for`, like the RSVP mailers.

### `FavoriteMailer`

| Email              | When                                                     | Contents                                              |
|--------------------|----------------------------------------------------------|-------------------------------------------------------|
| `reminder`         | The day before a followed date, and 7 days before a date followed on its own | Date, time, venue, banner, description, `.ics`, RSVP link if open |
| `schedule_changed` | A date is cancelled, postponed, retimed, relocated, or reactivated | What changed, old and new values, link          |
| `series_changed`   | The series is cancelled, postponed, resumed, or its schedule is edited | Summary and the next few dates             |
| `content_changed`  | Batched description, banner, title, or link changes      | Current description and banner, which parts changed  |
| `new_date`         | The event had no upcoming dates and now has one          | The date, with an RSVP link if open                   |

Each email has the "Stop following" link and a link to email preferences.

## Jobs

The schedules go in `config/sidekiq.yml`.

- `FavoriteReminderJob`, hourly. Sends the day-before reminder for each followed date within `favorite_reminder_hours`, and the 7-day heads-up for occurrence favorites within 7 days, when there's no delivery row of that kind. The day-before reminder takes priority, so a date added 2 days out gets only that one.
- `FavoriteChangeDigestJob`, every 10 minutes. Groups undelivered `favorite_changes` by event, sends once the newest change is older than the quiet period, and marks them delivered.
- A daily cleanup in an existing job (or `FavoriteCleanupJob`) deletes delivered `favorite_changes` and delivery rows older than 90 days.

## Lifecycle integration

- **Occurrence cancelled, relocated, rescheduled, or reactivated**: `ScheduleNotifier` calls `FavoriteNotifier` for that date, following the same silence rules it uses for hosts.
- **Occurrence postponed**: move favorites on the old date to the new date, then send one postponement email.
- **Event cancelled, postponed, resumed, rescheduled, or venue changed**: one `series_changed` email to event followers and to followers of any affected date.
- **Event or occurrence soft-deleted**: treat it the same as cancelled, then leave the favorites. They stop showing up because the record is hidden.
- **New dates from `OccurrenceGenerator`**: after a generation run, check each event that went from no upcoming dates to having some and send `new_date`. This check runs outside a silenced series edit. During a series edit, the `series_changed` email covers it.

## UI

### Favorite button

- A star toggle on the event page, the occurrence page, and event cards on the index and calendar. It's a Turbo Stream `button_to`, so the star changes without a page reload.
- On an occurrence page there are two choices: "Follow this date" and "Follow every date". If the user already follows the event, the date shows as followed through the event.
- Logged-out visitors see a "Log in to follow" link, which returns them to the same page after login (`store_location_for`, as the RSVP flow does).

### Dashboard

- **My Favorites** section near the top, alongside "My RSVPs":
  - Upcoming dates from everything the user follows, merged, deduplicated, and sorted, with the next 20 shown. Each one is marked "following event" or "following this date", with an RSVP badge if they have one.
  - Below that, the followed events, each with its next date and buttons to unfollow and turn reminders on or off.
- An empty state with a pointer to the events list.

### Profile / preferences

- A `favorite_emails_enabled` toggle next to `email_reminders_enabled` on the account edit page.

### Site config

- `favorites_enabled`, `favorite_reminder_hours`, and `favorite_change_quiet_minutes` in the admin site config form.

## Phases (each one commits separately with tests)

1. **Schema and models**: migrations, `Favorite`, associations, visibility-aware follower queries, and model tests (uniqueness, cascade, the occurrence-belongs-to-event check).
2. **Favorite UI**: `FavoritesController` (create / destroy / toggle reminders), the star partial on event, occurrence, and card views, the login redirect, and controller and system tests.
3. **Dashboard**: the My Favorites section with merged upcoming dates, plus tests.
4. **Reminders**: `FavoriteMailer#reminder`, `FavoriteReminderJob`, delivery log, RSVP deduplication, and idempotency tests.
5. **Schedule changes**: hook `FavoriteNotifier` into `ScheduleNotifier`, move favorites on postponement, apply the silence rules, deduplicate with RSVPs, and send `series_changed`.
6. **Content changes**: detect human edits in callbacks, the `favorite_changes` queue, `FavoriteChangeDigestJob`, banner rules, and tests showing rotation and pool changes don't send email.
7. **New dates**: the "no upcoming, now has one" check after generation, plus tests for the rolling-window case (no email) and the rescheduled one-time event (email).
8. **Unsubscribe and polish**: signed stop-following links, `List-Unsubscribe`, profile and site config settings, a docs update, a CHANGELOG entry, and the version bump to 0.32.0.

## Decisions

- A one-time event that is still upcoming doesn't send a new-date email when a second date is added. The schedule-edit email covers it, and the reminders follow.
- Single-date favorites get a 7-day heads-up and a day-before reminder. Event favorites get only the day-before reminder.
- Reminders are on by default for every favorite. Users turn them off for each favorite.
