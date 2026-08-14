class CreateFleetAvailabilityEmailSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :fleet_availability_email_settings do |t|
      t.boolean :enabled, null: false, default: true
      t.text :recipients, null: false, default: ""
      t.text :cc, null: false, default: ""
      t.text :bcc, null: false, default: ""
      t.string :subject, null: false, default: "Disponibilidade da frota - %{date}"
      t.text :body, null: false, default: "Segue em anexo a disponibilidade da frota do dia %{date}."

      t.timestamps
    end
  end
end
