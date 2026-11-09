class AddHostContact < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :allow_host_contact, :boolean, null: false, default: false
    add_column :site_configs, :host_contact_response, :text
  end
end
