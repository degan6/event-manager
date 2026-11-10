class AddFavorites < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :favorite_emails_enabled, :boolean, null: false, default: true

    change_table :site_configs, bulk: true do |t|
      t.boolean :favorites_enabled, null: false, default: true
      t.integer :favorite_reminder_hours, null: false, default: 24
      t.integer :favorite_change_quiet_minutes, null: false, default: 30
    end

    create_table :favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.references :event_occurrence, foreign_key: true
      t.boolean :reminders_enabled, null: false, default: true
      t.timestamps
    end
    add_index :favorites, %i[user_id event_id],
              unique: true,
              where: 'event_occurrence_id IS NULL',
              name: 'index_favorites_on_user_and_event'
    add_index :favorites, %i[user_id event_occurrence_id],
              unique: true,
              where: 'event_occurrence_id IS NOT NULL',
              name: 'index_favorites_on_user_and_occurrence'

    create_table :favorite_changes do |t|
      t.references :event, null: false, foreign_key: true
      t.references :event_occurrence, foreign_key: true
      t.string :kind, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :favorite_changes, %i[event_id delivered_at]
    add_check_constraint :favorite_changes,
                         "kind IN ('description', 'banner', 'title', 'details')",
                         name: 'favorite_changes_kind_check'

    create_table :favorite_reminder_deliveries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event_occurrence, null: false, foreign_key: true
      t.string :kind, null: false
      t.datetime :sent_at, null: false
      t.timestamps
    end
    add_index :favorite_reminder_deliveries, %i[user_id event_occurrence_id kind],
              unique: true,
              name: 'index_favorite_reminders_on_user_occurrence_and_kind'
    add_check_constraint :favorite_reminder_deliveries,
                         "kind IN ('7d', '1d')",
                         name: 'favorite_reminder_deliveries_kind_check'
  end
end
