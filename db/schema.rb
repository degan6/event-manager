# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_10_143000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "event_hosts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "notify_on_rsvp", default: false, null: false
    t.index ["event_id", "user_id"], name: "index_event_hosts_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_event_hosts_on_event_id"
    t.index ["user_id"], name: "index_event_hosts_on_user_id"
  end

  create_table "event_images", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.boolean "in_pool", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "position"], name: "index_event_images_on_event_id_and_position"
    t.index ["event_id"], name: "index_event_images_on_event_id"
  end

  create_table "event_journals", force: :cascade do |t|
    t.string "action", null: false
    t.jsonb "change_data", default: {}
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "occurrence_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["action"], name: "index_event_journals_on_action"
    t.index ["created_at"], name: "index_event_journals_on_created_at"
    t.index ["event_id", "created_at"], name: "index_event_journals_on_event_id_and_created_at"
    t.index ["event_id"], name: "index_event_journals_on_event_id"
    t.index ["occurrence_id"], name: "index_event_journals_on_occurrence_id"
    t.index ["user_id"], name: "index_event_journals_on_user_id"
  end

  create_table "event_occurrences", force: :cascade do |t|
    t.text "cancellation_reason"
    t.datetime "created_at", null: false
    t.text "custom_description"
    t.boolean "custom_event_image", default: false, null: false
    t.datetime "deleted_at"
    t.integer "duration_override"
    t.bigint "event_id", null: false
    t.bigint "event_image_id"
    t.bigint "location_id"
    t.datetime "occurs_at", null: false
    t.datetime "postponed_until"
    t.text "relocated_to"
    t.text "reminder_1d_long"
    t.text "reminder_1d_short"
    t.text "reminder_7d_long"
    t.text "reminder_7d_short"
    t.string "slug"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "postponed_to_id"
    t.integer "capacity_override"
    t.boolean "rsvp_disabled", default: false, null: false
    t.datetime "checkin_finalized_at"
    t.text "custom_description_html"
    t.index ["deleted_at"], name: "index_event_occurrences_on_deleted_at"
    t.index ["event_id", "occurs_at"], name: "index_event_occurrences_on_event_id_and_occurs_at"
    t.index ["event_id"], name: "index_event_occurrences_on_event_id"
    t.index ["event_image_id"], name: "index_event_occurrences_on_event_image_id"
    t.index ["location_id"], name: "index_event_occurrences_on_location_id"
    t.index ["occurs_at"], name: "index_event_occurrences_on_occurs_at"
    t.index ["postponed_to_id"], name: "index_event_occurrences_on_postponed_to_id"
    t.index ["slug"], name: "index_event_occurrences_on_slug", unique: true
    t.index ["status", "occurs_at"], name: "index_event_occurrences_on_status_and_occurs_at"
    t.index ["status"], name: "index_event_occurrences_on_status"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'postponed'::character varying::text, 'cancelled'::character varying::text, 'relocated'::character varying::text])", name: "event_occurrences_status_check"
  end

  create_table "events", force: :cascade do |t|
    t.text "cancellation_reason"
    t.datetime "created_at", null: false
    t.boolean "default_to_cancelled", default: false, null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "draft", default: false, null: false
    t.integer "duration", default: 60
    t.integer "event_occurrences_count", default: 0, null: false
    t.bigint "fixed_event_image_id"
    t.string "ical_token"
    t.integer "image_cycle_index", default: 0, null: false
    t.string "image_selection_mode", default: "fixed", null: false
    t.bigint "location_id"
    t.integer "max_occurrences", default: 5, null: false
    t.string "more_info_url"
    t.string "open_to", default: "public", null: false
    t.boolean "permanently_cancelled", default: false, null: false
    t.boolean "permanently_relocated", default: false, null: false
    t.datetime "postponed_until"
    t.text "recurrence_rule"
    t.string "recurrence_type", null: false
    t.text "relocated_to"
    t.text "reminder_1d_long"
    t.text "reminder_1d_short"
    t.text "reminder_7d_long"
    t.text "reminder_7d_short"
    t.boolean "requires_mask", default: false, null: false
    t.boolean "sign_feed", default: true, null: false
    t.boolean "slack_announce", default: true, null: false
    t.string "slug"
    t.boolean "social_reminders", default: true, null: false
    t.datetime "start_time", null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visibility", default: "public", null: false
    t.boolean "rsvp_enabled", default: false, null: false
    t.integer "capacity"
    t.boolean "waitlist_enabled", default: true, null: false
    t.string "waitlist_mode", default: "first_come", null: false
    t.integer "rsvp_closes_minutes_before", default: 0, null: false
    t.text "description_html"
    t.boolean "busy", default: false, null: false
    t.string "exclusive_status", default: "none", null: false
    t.datetime "exclusive_requested_at"
    t.datetime "exclusive_reviewed_at"
    t.text "exclusive_review_note"
    t.integer "conflict_buffer_minutes"
    t.bigint "exclusive_requested_by_id"
    t.bigint "exclusive_reviewed_by_id"
    t.boolean "allow_host_contact", default: false, null: false
    t.index ["deleted_at"], name: "index_events_on_deleted_at"
    t.index ["description"], name: "index_events_on_description_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["exclusive_requested_by_id"], name: "index_events_on_exclusive_requested_by_id"
    t.index ["exclusive_reviewed_by_id"], name: "index_events_on_exclusive_reviewed_by_id"
    t.index ["exclusive_status"], name: "index_events_on_exclusive_status"
    t.index ["fixed_event_image_id"], name: "index_events_on_fixed_event_image_id"
    t.index ["ical_token"], name: "index_events_on_ical_token", unique: true
    t.index ["location_id"], name: "index_events_on_location_id"
    t.index ["open_to"], name: "index_events_on_open_to"
    t.index ["recurrence_type"], name: "index_events_on_recurrence_type"
    t.index ["slug"], name: "index_events_on_slug", unique: true
    t.index ["start_time"], name: "index_events_on_start_time"
    t.index ["status", "start_time"], name: "index_events_on_status_and_start_time"
    t.index ["status", "visibility"], name: "index_events_on_status_and_visibility"
    t.index ["status"], name: "index_events_on_status"
    t.index ["title"], name: "index_events_on_title_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["user_id"], name: "index_events_on_user_id"
    t.index ["visibility"], name: "index_events_on_visibility"
    t.check_constraint "exclusive_status::text = ANY (ARRAY['none'::character varying::text, 'pending'::character varying::text, 'approved'::character varying::text, 'denied'::character varying::text])", name: "events_exclusive_status_check"
    t.check_constraint "open_to::text = ANY (ARRAY['public'::character varying::text, 'members'::character varying::text, 'private'::character varying::text])", name: "events_open_to_check"
    t.check_constraint "recurrence_type::text = ANY (ARRAY['once'::character varying::text, 'weekly'::character varying::text, 'monthly'::character varying::text, 'custom'::character varying::text])", name: "events_recurrence_type_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'postponed'::character varying::text, 'cancelled'::character varying::text])", name: "events_status_check"
    t.check_constraint "visibility::text = ANY (ARRAY['public'::character varying::text, 'members'::character varying::text, 'private'::character varying::text])", name: "events_visibility_check"
    t.check_constraint "waitlist_mode::text = ANY (ARRAY['first_come'::character varying::text, 'sequential'::character varying::text])", name: "events_waitlist_mode_check"
  end

  create_table "favorite_changes", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "event_occurrence_id"
    t.string "kind", null: false
    t.bigint "actor_id"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_favorite_changes_on_actor_id"
    t.index ["event_id", "delivered_at"], name: "index_favorite_changes_on_event_id_and_delivered_at"
    t.index ["event_id"], name: "index_favorite_changes_on_event_id"
    t.index ["event_occurrence_id"], name: "index_favorite_changes_on_event_occurrence_id"
    t.check_constraint "kind::text = ANY (ARRAY['description'::character varying, 'banner'::character varying, 'title'::character varying, 'details'::character varying]::text[])", name: "favorite_changes_kind_check"
  end

  create_table "favorite_reminder_deliveries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "event_occurrence_id", null: false
    t.string "kind", null: false
    t.datetime "sent_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_occurrence_id"], name: "index_favorite_reminder_deliveries_on_event_occurrence_id"
    t.index ["user_id", "event_occurrence_id", "kind"], name: "index_favorite_reminders_on_user_occurrence_and_kind", unique: true
    t.index ["user_id"], name: "index_favorite_reminder_deliveries_on_user_id"
    t.check_constraint "kind::text = ANY (ARRAY['7d'::character varying, '1d'::character varying]::text[])", name: "favorite_reminder_deliveries_kind_check"
  end

  create_table "favorites", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "event_id", null: false
    t.bigint "event_occurrence_id"
    t.boolean "reminders_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_favorites_on_event_id"
    t.index ["event_occurrence_id"], name: "index_favorites_on_event_occurrence_id"
    t.index ["user_id", "event_id"], name: "index_favorites_on_user_and_event", unique: true, where: "(event_occurrence_id IS NULL)"
    t.index ["user_id", "event_occurrence_id"], name: "index_favorites_on_user_and_occurrence", unique: true, where: "(event_occurrence_id IS NOT NULL)"
    t.index ["user_id"], name: "index_favorites_on_user_id"
  end

  create_table "locations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_locations_on_name", unique: true
  end

  create_table "reminder_postings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.bigint "event_id", null: false
    t.bigint "event_occurrence_id", null: false
    t.text "message"
    t.string "platform", null: false
    t.string "post_uid"
    t.string "post_url"
    t.datetime "posted_at", null: false
    t.string "reminder_type"
    t.datetime "updated_at", null: false
    t.index ["deleted_by_id"], name: "index_reminder_postings_on_deleted_by_id"
    t.index ["event_id", "posted_at"], name: "index_reminder_postings_on_event_id_and_posted_at"
    t.index ["event_id"], name: "index_reminder_postings_on_event_id"
    t.index ["event_occurrence_id"], name: "index_reminder_postings_on_event_occurrence_id"
    t.index ["platform"], name: "index_reminder_postings_on_platform"
    t.index ["posted_at"], name: "index_reminder_postings_on_posted_at"
  end

  create_table "rsvps", force: :cascade do |t|
    t.bigint "event_occurrence_id", null: false
    t.bigint "user_id"
    t.string "name"
    t.string "email"
    t.string "status", default: "pending", null: false
    t.datetime "waitlisted_at"
    t.datetime "offer_held_until"
    t.datetime "last_offered_at"
    t.datetime "offer_reminder_sent_at"
    t.datetime "confirmed_at"
    t.datetime "cancelled_at"
    t.bigint "cancelled_by_id"
    t.string "cancellation_reason"
    t.string "cancelled_via"
    t.string "manage_token", null: false
    t.boolean "reminders_opted_out", default: false, null: false
    t.datetime "reminder_7d_sent_at"
    t.datetime "reminder_1d_sent_at"
    t.datetime "reminder_day_of_sent_at"
    t.datetime "release_nag_sent_at"
    t.boolean "attended"
    t.bigint "checked_in_by_id"
    t.datetime "checked_in_at"
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "event_occurrence_id, lower((email)::text)", name: "index_rsvps_on_occurrence_and_lower_email", unique: true, where: "(((status)::text <> 'cancelled'::text) AND (email IS NOT NULL))"
    t.index ["cancelled_by_id"], name: "index_rsvps_on_cancelled_by_id"
    t.index ["checked_in_by_id"], name: "index_rsvps_on_checked_in_by_id"
    t.index ["event_occurrence_id", "status", "waitlisted_at"], name: "index_rsvps_on_occurrence_status_and_waitlisted_at"
    t.index ["event_occurrence_id", "user_id"], name: "index_rsvps_on_occurrence_and_user", unique: true, where: "(((status)::text <> 'cancelled'::text) AND (user_id IS NOT NULL))"
    t.index ["event_occurrence_id"], name: "index_rsvps_on_event_occurrence_id"
    t.index ["manage_token"], name: "index_rsvps_on_manage_token", unique: true
    t.index ["user_id"], name: "index_rsvps_on_user_id"
    t.check_constraint "cancelled_via IS NULL OR (cancelled_via::text = ANY (ARRAY['self'::character varying::text, 'host'::character varying::text, 'admin'::character varying::text, 'occurrence_cancelled'::character varying::text]))", name: "rsvps_cancelled_via_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'confirmed'::character varying::text, 'waitlisted'::character varying::text, 'cancelled'::character varying::text])", name: "rsvps_status_check"
  end

  create_table "site_configs", force: :cascade do |t|
    t.string "address"
    t.text "ai_key"
    t.string "ai_model"
    t.text "ai_reminder_prompt", default: "Create a short, friendly reminder for {{event_title}} happening on {{event_date}} at {{event_time}} at PDX Hackerspace.", null: false
    t.string "ai_url"
    t.string "contact_email"
    t.string "contact_phone"
    t.datetime "created_at", null: false
    t.boolean "disallow_robots", default: false, null: false
    t.string "email_test_mode_address"
    t.boolean "email_test_mode_enabled", default: false, null: false
    t.text "footer_text"
    t.boolean "host_email_reminders_enabled", default: true, null: false
    t.text "location_info"
    t.integer "long_reminder_max_length", default: 800, null: false
    t.boolean "matomo_enabled", default: false, null: false
    t.string "matomo_site_id"
    t.string "matomo_url"
    t.string "organization_name"
    t.integer "short_reminder_max_length", default: 300, null: false
    t.boolean "slack_enabled", default: false, null: false
    t.boolean "social_reminders_enabled", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "website_url"
    t.boolean "rsvps_enabled", default: true, null: false
    t.integer "rsvp_offer_hours", default: 24, null: false
    t.integer "rsvp_last_call_hours", default: 4, null: false
    t.integer "rsvp_guest_retention_days", default: 30, null: false
    t.integer "default_conflict_buffer_minutes", default: 60, null: false
    t.text "host_contact_response"
    t.boolean "favorites_enabled", default: true, null: false
    t.integer "favorite_reminder_hours", default: 24, null: false
    t.integer "favorite_change_quiet_minutes", default: 30, null: false
    t.check_constraint "id = 1", name: "site_configs_singleton"
  end

  create_table "social_credentials", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.json "metadata", default: {}
    t.string "platform", null: false
    t.text "refresh_token"
    t.datetime "updated_at", null: false
    t.index ["platform"], name: "index_social_credentials_on_platform", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "can_create_events", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.boolean "email_reminders_enabled", default: true, null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "user", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.string "username"
    t.boolean "favorite_emails_enabled", default: true, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "((provider IS NOT NULL) AND (uid IS NOT NULL))"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["username"], name: "index_users_on_username"
    t.check_constraint "role::text = ANY (ARRAY['user'::character varying::text, 'admin'::character varying::text])", name: "users_role_check"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "event_hosts", "events"
  add_foreign_key "event_hosts", "users"
  add_foreign_key "event_images", "events"
  add_foreign_key "event_journals", "event_occurrences", column: "occurrence_id", on_delete: :nullify
  add_foreign_key "event_journals", "events"
  add_foreign_key "event_journals", "users"
  add_foreign_key "event_occurrences", "event_images"
  add_foreign_key "event_occurrences", "event_occurrences", column: "postponed_to_id", on_delete: :nullify
  add_foreign_key "event_occurrences", "events"
  add_foreign_key "event_occurrences", "locations"
  add_foreign_key "events", "locations"
  add_foreign_key "events", "users"
  add_foreign_key "events", "users", column: "exclusive_requested_by_id", on_delete: :nullify
  add_foreign_key "events", "users", column: "exclusive_reviewed_by_id", on_delete: :nullify
  add_foreign_key "favorite_changes", "event_occurrences"
  add_foreign_key "favorite_changes", "events"
  add_foreign_key "favorite_changes", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "favorite_reminder_deliveries", "event_occurrences"
  add_foreign_key "favorite_reminder_deliveries", "users"
  add_foreign_key "favorites", "event_occurrences"
  add_foreign_key "favorites", "events"
  add_foreign_key "favorites", "users"
  add_foreign_key "reminder_postings", "event_occurrences"
  add_foreign_key "reminder_postings", "events"
  add_foreign_key "reminder_postings", "users", column: "deleted_by_id"
  add_foreign_key "rsvps", "event_occurrences"
  add_foreign_key "rsvps", "users"
  add_foreign_key "rsvps", "users", column: "cancelled_by_id", on_delete: :nullify
  add_foreign_key "rsvps", "users", column: "checked_in_by_id", on_delete: :nullify
end
